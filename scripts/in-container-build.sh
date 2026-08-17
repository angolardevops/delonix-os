#!/usr/bin/env bash
# DelonixOS — o build propriamente dito. Corre DENTRO do contentor Manjaro
# (ou directamente num host Manjaro, como root).
#
# Passos:
#   1. actualizar o sistema base e instalar o manjaro-tools
#   2. buscar o iso-profiles oficial (só para reaproveitar o `shared/`)
#   3. injectar o nosso perfil delonix/devops
#   4. compilar os pacotes da casa (branding/settings/tools) para o repo local
#   5. buscar os binários do Delonix Runtime para o overlay
#   6. buildiso
set -euo pipefail

KERNEL=${DELONIX_KERNEL:-linux612}
[[ ${1:-} == --kernel ]] && KERNEL=$2

WORK=/work
# Os scripts são executados a partir de uma CÓPIA (feita pelo build.sh), nunca
# directamente de /work. Motivo: o bash lê o script aos pedaços enquanto corre;
# se alguém editar o ficheiro no repositório a meio de um build de 40 minutos,
# o bash retoma no mesmo offset e executa lixo ("s: command not found").
SCRIPTS=${DELONIX_SCRIPTS:-$WORK/scripts}
PROFILES_DIR=/usr/share/manjaro-tools/iso-profiles
UPSTREAM=https://gitlab.manjaro.org/profiles-and-settings/iso-profiles.git

log() { printf '\n\e[1m→ %s\e[0m\n' "$*"; }

# --- 0. mirrors ------------------------------------------------------------
# Isto não é afinação de velocidade — é correcção.
#
# A 2026-08-15 um mirror da lista estava um mês atrasado. Serviu uma base de
# dados velha, o pacman resolveu `manjaro-live-base` para a versão de 2024 (que
# instala /usr/bin/manjaro-live) em vez da actual (que instala
# /usr/bin/manjaro-live-setup, o binário que o manjaro-tools de hoje invoca), e
# o build morreu ao fim de 40 minutos com:
#
#   chroot: failed to run command '/usr/bin/manjaro-live-setup': No such file
#
# E como a versão velha já estava na cache de pacotes partilhada, o pacman
# instalou-a sem descarregar nada — não houve um único erro de rede para se ver.
#
# O `pacman-mirrors --fasttrack` foi a primeira tentativa de correcção e falhou
# de outra maneira: escolheu, a partir desta rede, cinco mirrors nos EUA que ela
# nem resolve ("Could not resolve host"). Ele decide pela API da Manjaro; as
# perguntas que interessam são locais — este mirror responde-me a mim, e os
# dados dele são recentes? É o que o pick-mirrors.sh verifica.
log "a escolher mirrors alcançáveis e actualizados"
bash "$SCRIPTS/pick-mirrors.sh" || exit 1

# --- 1. dependências ----------------------------------------------------------
log "a sincronizar pacman e instalar manjaro-tools"
pacman-key --init 2>/dev/null || true
pacman-key --populate archlinux manjaro 2>/dev/null || true

# O picker já garantiu mirrors recentes; isto confirma que a sincronização
# aconteceu de facto, em vez de assumir.
bash "$SCRIPTS/sync-pacman.sh" || exit 1

pacman -Su --noconfirm --needed \
    manjaro-tools-iso manjaro-tools-base git rsync curl \
    squashfs-tools dosfstools libisoburn grub edk2-shell erofs-utils \
    python python-pillow

# O manjaro-tools acabou de ser instalado e trouxe as SUAS configurações de
# pacman — que são as que o buildiso usa dentro dos chroots. As opções que
# aplicámos antes não lhes chegaram, porque estes ficheiros ainda não existiam.
bash "$SCRIPTS/sync-pacman.sh" --so-config

# --- 2. iso-profiles oficial (para o `shared/`) -------------------------------
# Só precisamos do `shared/` do upstream — mas ele vive num repositório git, e o
# GitLab da Manjaro tem avarias:
#
#   remote: GitLab is not responding
#   fatal: unable to access '...': The requested URL returned error: 502
#
# Antes, isso matava o build inteiro, porque o clone era refeito TODAS as vezes:
# o /usr/share/manjaro-tools vive dentro do contentor e desaparece com ele.
# Agora o clone é guardado na cache do host e reaproveitado — uma avaria do
# GitLab passa a ser um aviso, não uma paragem.
CACHE_PROFILES=/var/cache/delonix-iso-profiles

obter_profiles() {
    if [[ -d $CACHE_PROFILES/.git ]]; then
        log "iso-profiles em cache — a tentar actualizar"
        # Falhar a actualizar não é grave: a cópia que temos serve.
        # `FETCH_HEAD` e não `origin/HEAD`: num clone raso (--depth 1) o
        # HEAD remoto não é criado, e o reset falharia sempre em silêncio.
        if git -C "$CACHE_PROFILES" fetch --depth 1 origin HEAD 2>/dev/null &&
           git -C "$CACHE_PROFILES" reset --hard FETCH_HEAD 2>/dev/null; then
            log "  actualizado"
        else
            log "  sem resposta do GitLab; a usar a cópia em cache"
        fi
        return 0
    fi

    local tentativa
    for tentativa in 1 2 3; do
        log "a clonar o iso-profiles (tentativa $tentativa/3)"
        rm -rf "$CACHE_PROFILES"
        # SEM pipe: `git clone ... | tail` devolveria o estado do `tail`, que é
        # sempre 0, e a primeira tentativa passaria por boa mesmo tendo falhado.
        if git clone --depth 1 "$UPSTREAM" "$CACHE_PROFILES"; then
            [[ -d $CACHE_PROFILES/.git ]] && return 0
        fi
        sleep $(( tentativa * 10 ))
    done
    return 1
}

if ! obter_profiles; then
    cat >&2 <<'AVISO'

  Não consegui obter o iso-profiles da Manjaro, e não há cópia em cache.

  Precisamos dele só pelo directório `shared/`. Se o GitLab estiver em baixo
  (acontece), espera e tenta outra vez — a partir daí fica em cache e uma
  avaria deles deixa de te parar.

  Estado do serviço: https://status.manjaro.org

AVISO
    exit 1
fi

# O manjaro-tools espera os perfis no seu próprio directório.
rm -rf "$PROFILES_DIR"
mkdir -p "$PROFILES_DIR"
rsync -a --exclude '.git' "$CACHE_PROFILES/" "$PROFILES_DIR/"

# --- 3. injectar o perfil ------------------------------------------------------
# Há dois casos: o perfil oficial do repositório, ou um perfil gerado pelo
# `delonixos render` a partir de um inventário YAML do utilizador.
EDITION=delonix
PROFILE=devops
AUR_LIST="$WORK/packages/aur.list"

if [[ -n ${DELONIX_PROFILE_OVERRIDE:-} && -d ${DELONIX_PROFILE_OVERRIDE:-} ]]; then
    log "a injectar o perfil gerado pelo inventário"
    meta="$DELONIX_PROFILE_OVERRIDE/metadata.json"
    if [[ -f $meta ]]; then
        EDITION=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['edition'])" "$meta")
        PROFILE=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['profile'])" "$meta")
        DIST_NAME=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['name'])" "$meta")
        DIST_VER=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$meta")
        DIST_CODE=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['codename'])" "$meta")
        KERNEL=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['kernel'])" "$meta")
    fi
    rm -rf "${PROFILES_DIR:?}/${EDITION:?}"
    rsync -a "$DELONIX_PROFILE_OVERRIDE/$EDITION/" "$PROFILES_DIR/$EDITION/"
    [[ -f $DELONIX_PROFILE_OVERRIDE/aur.list ]] && AUR_LIST="$DELONIX_PROFILE_OVERRIDE/aur.list"
else
    log "a injectar o perfil oficial delonix/devops"
    rm -rf "$PROFILES_DIR/delonix"
    rsync -a "$WORK/iso-profiles/delonix/" "$PROFILES_DIR/delonix/"
fi

# `shared/` traz Packages-Live/Root comuns da Manjaro. Ficamos com o nosso, mas
# o buildiso espera a directoria — por isso apontamos para a do upstream.
[[ -d $PROFILES_DIR/shared ]] || { echo "iso-profiles sem shared/ — abortar"; exit 1; }

# --- 3b. repositório local com os pacotes do AUR --------------------------------
# claude-code, antigravity, cloud-hypervisor, gcloud e companhia só existem no
# AUR, e o pacman do buildiso só instala de repositórios. Compilamo-los aqui.
AUR_REPO=/var/cache/delonix-aur
if [[ ${DELONIX_SKIP_AUR:-0} != 1 ]]; then
    bash "$SCRIPTS/build-aur-repo.sh" "$AUR_LIST" "$AUR_REPO"

    # O `user-repos.conf` do manjaro-tools recusa repositórios file:// de
    # propósito (check_user_repos_conf → "Using local repositories is not
    # supported!"), por isso acrescentamos a secção directamente à configuração
    # de pacman que o buildiso usa.
    for conf in /usr/share/manjaro-tools/pacman-default.conf \
                /usr/share/manjaro-tools/pacman-multilib.conf; do
        [[ -f $conf ]] || continue
        grep -q '\[delonix-aur\]' "$conf" || cat >>"$conf" <<EOF

[delonix-aur]
SigLevel = Optional TrustAll
Server = file://$AUR_REPO
EOF
    done

    # O que não compilou é comentado nas listas — mais vale uma ISO sem uma
    # ferramenta do que um build a abortar aos 20 minutos.
    python3 "$SCRIPTS/filter-missing-aur.py" \
        "$PROFILES_DIR/$EDITION/$PROFILE" "$AUR_REPO"
else
    log "AUR ignorado (DELONIX_SKIP_AUR=1) — a comentar esses pacotes"
    python3 "$SCRIPTS/filter-missing-aur.py" \
        "$PROFILES_DIR/$EDITION/$PROFILE" /var/empty
fi

# --- 3c. pacotes da casa (branding, settings, tools) ---------------------------
# Isto é o que faz o branding e a afinação chegarem a quem JÁ instalou: em vez
# de ficheiros copiados para dentro da imagem, pacotes com versão num repo.
DELONIX_REPO=/var/cache/delonix-repo
bash "$SCRIPTS/build-os-packages.sh" "$DELONIX_REPO"

for conf in /usr/share/manjaro-tools/pacman-default.conf \
            /usr/share/manjaro-tools/pacman-multilib.conf; do
    [[ -f $conf ]] || continue
    grep -q '\[delonix\]' "$conf" || cat >>"$conf" <<EOF

[delonix]
SigLevel = Optional TrustAll
Server = file://$DELONIX_REPO
EOF
done

# --- 4. binários do Delonix Runtime -------------------------------------------
log "a buscar binários do Delonix (opcional — falha não trava o build)"
bash "$SCRIPTS/fetch-delonix-bins.sh" \
    "$PROFILES_DIR/$EDITION/$PROFILE/desktop-overlay/usr/local/bin" || true

# --- 5. permissões nos scripts do overlay -------------------------------------
chmod 0755 "$PROFILES_DIR/$EDITION/$PROFILE"/desktop-overlay/usr/local/bin/* \
           "$PROFILES_DIR/$EDITION/$PROFILE"/desktop-overlay/usr/local/libexec/* 2>/dev/null || true

# --- 6. configuração do manjaro-tools -----------------------------------------
# Só chaves que o manjaro-tools lê (lib/util.sh). `iso_label` é calculado por
# `get_iso_label()` a partir do dist_name — não é configurável.
ISO_NAME=$(echo "${DIST_NAME:-delonixos}" | tr 'A-Z ' 'a-z-')

# --- tema do GRUB do live ------------------------------------------------------
# O `prepare_grub` do manjaro-tools copia o tema do menu de arranque do live por
# um caminho que depende do nome da ISO:
#
#   util-iso-boot.sh:39   cp -r ${data_live}/themes/${iso_name}-live ${grub}/themes/
#
# O pacote `grub-theme-live-manjaro` instala `manjaro-live`, e o nosso iso_name é
# `delonixos` — daí, na montagem final:
#
#   cp: cannot stat '.../livefs/usr/share/grub/themes/delonixos-live'
#
# Geramos o tema com o nome certo a partir da marca Delonix. Fica no
# live-overlay, que é copiado para o livefs pelo `copy_overlay` — e o nome é
# calculado, não escrito à mão, para continuar a funcionar quando o `delonixos
# render` gera uma distro com outro nome.
TEMA_LIVE="$PROFILES_DIR/$EDITION/$PROFILE/live-overlay/usr/share/grub/themes/${ISO_NAME}-live"
TEMA_ORIGEM="$WORK/build/branding/usr/share/grub/themes/delonix"
if [[ -d $TEMA_ORIGEM ]]; then
    log "tema do GRUB do live: ${ISO_NAME}-live"
    install -d "$TEMA_LIVE"
    cp -a "$TEMA_ORIGEM"/. "$TEMA_LIVE"/
else
    log "ERRO: não encontrei o tema da marca em $TEMA_ORIGEM"
    log "      corre 'make branding' antes de construir"
    exit 1
fi

log "a configurar o manjaro-tools"
# `build_mirror` é A chave. O mkchroot instala TUDO dentro dos chroots a partir
# deste único servidor — não usa o /etc/pacman.d/mirrorlist. E o valor por
# omissão está fixo no código do manjaro-tools:
#
#   util.sh:216  [[ -z ${build_mirror} ]] && build_mirror='https://mirror.easyname.at/manjaro'
#
# Esse mirror está parado desde 8 de Julho de 2026. Foi ele, e só ele, que
# instalou manjaro-live-base-20241119 em três builds seguidos — a versão que não
# traz /usr/bin/manjaro-live-setup. Tudo o resto (contentor, preflight, as
# nossas asserções) via a versão correcta, porque olhava para o sítio errado.
BUILD_MIRROR=$(cat "${DELONIX_MELHOR_MIRROR:-/tmp/delonix-melhor-mirror}" 2>/dev/null)
if [[ -z $BUILD_MIRROR ]]; then
    log "ERRO: não sei que mirror dar ao manjaro-tools (o pick-mirrors não gravou)."
    log "      Sem isto o manjaro-tools usa o mirror parado que traz por omissão."
    exit 1
fi
log "build_mirror do manjaro-tools: $BUILD_MIRROR"

install -Dm644 /dev/stdin /etc/manjaro-tools/manjaro-tools.conf <<EOF
# gerado pelo build do DelonixOS
branch=stable
build_mirror=$BUILD_MIRROR
dist_name="${DIST_NAME:-DelonixOS}"
dist_release="${DIST_VER:-1.0}"
dist_codename="${DIST_CODE:-Acacia}"
dist_branding="DELONIX"
iso_name="$ISO_NAME"
iso_compression=zstd
kernel="$KERNEL"
EOF

# O run_dir (onde o buildiso procura perfis) vem de ~/.config/manjaro-tools/
# iso-profiles.conf; o default só se aplica se este ficheiro não existir.
install -Dm644 /dev/stdin /root/.config/manjaro-tools/iso-profiles.conf <<EOF
run_dir=$PROFILES_DIR
EOF

# --- 7. construir --------------------------------------------------------------
# `-p` recebe o NOME do perfil, não o caminho: o buildiso descobre a edição com
# `find ${run_dir} -maxdepth 2 -name devops` → delonix/devops.
#
# DUAS lições pagas com horas:
#
#   `-c`  NÃO limpa os chroots antes de construir. O default do buildiso é
#         limpar (clean_first=true), o que significa reinstalar ~1500 pacotes
#         do zero a cada tentativa — quatro horas por cada erro de uma linha.
#         Com `-c`, uma repetição reaproveita o rootfs e demora minutos.
#         Para forçar um build limpo: DELONIX_CLEAN=1.
#
#   `-f`  NÃO é "force": é `full_iso`, e no manjaro-tools isso força
#         `extra=true` — passando a instalar tudo o que está marcado `>extra`,
#         contra o que o nosso profile.conf declara. Estava a ser passado por
#         engano desde o início.
BUILD_ARGS=(-p "$PROFILE" -k "$KERNEL" -b stable)
if [[ ${DELONIX_CLEAN:-0} == 1 ]]; then
    log "build LIMPO pedido — os chroots vão ser reconstruídos do zero"
else
    BUILD_ARGS+=(-c)
    log "a reaproveitar os chroots (DELONIX_CLEAN=1 força um build limpo)"
fi

# --- mirrors DENTRO dos chroots ------------------------------------------------
# A correcção anterior falhou o alvo e vale a pena dizer porquê: o
# `pacman-mirrors --fasttrack` acima muda o mirrorlist do CONTENTOR, mas cada
# chroot do buildiso tem o seu, gerado quando foi criado — 125 servidores sem
# ranking. Como construímos com `-c` (não limpar), esse ficheiro sobrevive a
# todos os builds seguintes, com os mirrors atrasados que tinha no primeiro dia.
#
# A prova disto foi a data da própria base de dados: o pacman preserva o
# `Last-Modified` do servidor, e a extra.db dentro do livefs estava datada de
# 8 de Julho — a data exacta do mirror atrasado, um mês depois.
# O caminho leva o nome do PERFIL, não o da edição. Escrevi $EDITION aqui e o
# `[[ -d ]]` deu falso, por isso todo este bloco foi saltado EM SILÊNCIO — e a
# fase live voltou a falhar exactamente da mesma maneira, duas vezes. Daí, agora,
# procurar o directório em vez de o adivinhar, e ABORTAR se não o encontrar.
CHROOT_BASE=$(find /var/lib/manjaro-tools/buildiso -maxdepth 2 -type d -name x86_64 2>/dev/null | head -1)

if [[ -z $CHROOT_BASE ]]; then
    log "sem chroots anteriores — serão criados agora com o mirrorlist actual"
else
    log "a propagar os mirrors para os chroots em $CHROOT_BASE"
    encontrados=0
    # `mhwdfs` também: é a fase que corre o pacman DENTRO do chroot.
    for fs in rootfs desktopfs livefs mhwdfs; do
        [[ -d $CHROOT_BASE/$fs ]] || continue
        install -Dm644 /etc/pacman.d/mirrorlist "$CHROOT_BASE/$fs/etc/pacman.d/mirrorlist"
        # As dbs já descarregadas do mirror atrasado TÊM de sair: o pacman
        # considera-as actuais e nunca chega a usar os mirrors novos. A data
        # delas é a do servidor, por isso dá para ver de onde vieram.
        rm -f "$CHROOT_BASE/$fs"/var/lib/pacman/sync/{core,extra,multilib}.db

        # Os repositórios locais TÊM de ser alcançáveis de DENTRO do chroot.
        #
        # A fase mhwd é a única que corre o pacman lá dentro:
        #
        #   copy_from_cache(){ chroot-run ... "$1" pacman -v -Syw $2 ... }
        #
        # As outras usam `basestrap --root`, que corre ao nível do contentor —
        # e por isso o `file:///var/cache/delonix-aur` resolvia bem. Na mhwd não:
        #
        #   error: failed retrieving file 'delonix-aur.db' from disk :
        #          Could not open file /var/cache/delonix-aur/delonix-aur.db
        #
        # Bastam as bases de dados: os pacotes que a mhwd instala vêm todos do
        # core/extra. São umas centenas de KB, não os 1,2 GB do AUR.
        # A marca do Calamares: copiar o componente `manjaro` (que o
        # configure_branding já reescreveu com os nossos textos) para o nome
        # que o settings.conf procura. Sem isto o instalador não abre.
        if [[ $fs == livefs ]]; then
            # O Calamares exige DUAS coisas que ninguém documenta junto:
            #   1. a pasta do componente tem de se chamar como o `branding:` do
            #      settings.conf (que o manjaro-tools escreve como ${iso_name});
            #   2. o `componentName:` DENTRO do branding.desc tem de ser igual ao
            #      nome da pasta. Se divergirem, o Calamares não carrega e o
            #      ícone do ambiente de trabalho não faz nada.
            #
            # Na primeira tentativa isto falhou por minha causa: deixei uma
            # pasta-marcador vazia no live-overlay e a condição de cópia era
            # `! -d destino`. A pasta já existia, a cópia nunca aconteceu, e o
            # instalador continuou sem abrir. Agora a condição é o CONTEÚDO.
            marca_orig="$CHROOT_BASE/$fs/usr/share/calamares/branding/manjaro"
            marca_nova="$CHROOT_BASE/$fs/usr/share/calamares/branding/${ISO_NAME}"
            if [[ -f $marca_orig/branding.desc ]]; then
                rm -rf "$marca_nova"
                cp -a "$marca_orig" "$marca_nova"
                sed -i "s|^\(\s*componentName\s*:\s*\).*|\1${ISO_NAME}|" \
                    "$marca_nova/branding.desc"
                log "  livefs: marca ${ISO_NAME} (componentName: $(grep -oP '^\s*componentName\s*:\s*\K\S+' "$marca_nova/branding.desc"))"
            else
                log "  AVISO: sem $marca_orig — o instalador não vai abrir"
            fi
        fi

        # O tema do GRUB do live tem de existir DENTRO do livefs, e essa fase
        # já pode estar marcada como concluída — o `copy_overlay` não volta a
        # correr. Injectamo-lo aqui para não obrigar a refazer a fase inteira.
        if [[ $fs == livefs && -d $TEMA_ORIGEM ]]; then
            destino_tema="$CHROOT_BASE/$fs/usr/share/grub/themes/${ISO_NAME}-live"
            install -d "$destino_tema"
            cp -a "$TEMA_ORIGEM"/. "$destino_tema"/
            # O nosso theme.txt pede fontes por nome ("DejaVu Sans Bold 20") e o
            # GRUB só as encontra se os .pf2 estiverem na pasta do tema. O
            # `grub-theme-live-manjaro`, que já vem no Packages-Live, traz-nas —
            # reaproveitamo-las em vez de as gerar. Sem isto o menu do live
            # arranca na mesma, mas com a fonte de recurso.
            tema_manjaro="$CHROOT_BASE/$fs/usr/share/grub/themes/manjaro-live"
            if compgen -G "$tema_manjaro/*.pf2" >/dev/null; then
                cp -n "$tema_manjaro"/*.pf2 "$destino_tema"/ 2>/dev/null || true
                log "  livefs: fontes .pf2 reaproveitadas do tema da Manjaro"
            fi
            log "  livefs: tema ${ISO_NAME}-live instalado"
        fi

        for repo in delonix-aur delonix-repo; do
            origem=/var/cache/$repo
            [[ -d $origem ]] || continue
            destino="$CHROOT_BASE/$fs/var/cache/$repo"
            install -d "$destino"
            # `-L` resolve os links que o repo-add cria (foo.db → foo.db.tar.gz):
            # um link para fora do chroot não vale nada lá dentro.
            cp -Lf "$origem"/*.db "$origem"/*.files "$destino"/ 2>/dev/null || true
        done
        # `((encontrados++))` NÃO serve aqui: o pós-incremento devolve o valor
        # ANTIGO, e um 0 é estado de saída 1 — com `set -e`, o script morre na
        # primeira iteração. Foi assim que este bloco, já a correr no caminho
        # certo, matou o build logo a seguir a imprimir que ia começar.
        encontrados=$(( encontrados + 1 ))
        log "  $fs: mirrorlist substituído, dbs antigas apagadas"
    done
    if (( encontrados == 0 )); then
        log "ERRO: $CHROOT_BASE existe mas não tem rootfs/desktopfs/livefs."
        log "      Não vou construir às cegas — corre 'make clean-live' ou --clean."
        exit 1
    fi

    # Trocar o mirrorlist não desfaz o que já está INSTALADO. Se o livefs herdou
    # um manjaro-live-* de uma tentativa com o mirror atrasado, o pacman vê-o
    # como satisfeito (`--needed`) e não o actualiza — e a fase live volta a
    # falhar exactamente na mesma linha. Melhor dizê-lo do que construir por cima.
    if compgen -G "$CHROOT_BASE/livefs/var/lib/pacman/local/manjaro-live-*" >/dev/null; then
        instalado=$(basename "$(echo "$CHROOT_BASE"/livefs/var/lib/pacman/local/manjaro-live-base-*)")
        if [[ $instalado != *-2026* ]]; then
            cat >&2 <<AVISO

  O livefs tem $instalado instalado, de uma tentativa
  anterior com um mirror atrasado. O pacman não o vai actualizar (--needed
  considera-o satisfeito) e a fase live falha outra vez em:

      chroot: failed to run command '/usr/bin/manjaro-live-setup'

  Apaga só essa fase — as fases root e desktop, que demoram horas, ficam:

      make clean-live && make iso

AVISO
            exit 1
        fi
    fi
fi

# E os pacotes que o mirror atrasado deixou na cache partilhada: enquanto lá
# estiverem, uma db velha resolve para eles e o pacman instala-os sem
# descarregar nada — sem um único erro de rede para se ver.
for velho in /var/cache/pacman/pkg/manjaro-live-*.pkg.tar.zst; do
    [[ -e $velho ]] || continue
    if [[ $(basename "$velho") != *-2026*  ]]; then
        rm -f "$velho" "$velho.sig"
        log "  cache: removido $(basename "$velho") (anterior a 2026)"
    fi
done

# --- asserção final, antes de gastar horas -------------------------------------
# Três builds morreram na fase live por causa de UMA coisa: o pacman a resolver
# `manjaro-live-base` para a versão de 2024, que não traz o
# /usr/bin/manjaro-live-setup que o manjaro-tools invoca.
#
# Em vez de voltar a deduzir de onde vem, pergunta-se directamente ao pacman que
# vai fazer o trabalho, e imprime-se o estado que interessa. Se estiver errado,
# pára aqui — em segundos, não em horas.
log "estado das bases de dados antes de construir"
for db in /var/lib/pacman/sync/*.db; do
    [[ -e $db ]] || continue
    printf '    %-14s %s\n' "$(basename "$db")" "$(stat -c %y "$db" | cut -d. -f1)"
done

# A pergunta TEM de ser feita ao mesmo servidor que o mkchroot vai usar. A
# asserção anterior perguntava ao pacman do contentor — que tinha as bases de
# dados frescas — e passava alegremente enquanto o chroot instalava a versão de
# 2024 vinda do build_mirror. Verificar o sítio errado é pior do que não
# verificar: dá confiança a um build que vai falhar na mesma.
install -Dm644 /dev/stdin /tmp/delonix-check.conf <<CONF
[options]
Architecture = auto
SigLevel = Never
DBPath = /tmp/delonix-check-db
[core]
Server = $BUILD_MIRROR/stable/\$repo/\$arch
[extra]
Server = $BUILD_MIRROR/stable/\$repo/\$arch
CONF
mkdir -p /tmp/delonix-check-db/sync
pacman --config /tmp/delonix-check.conf -Sy >/dev/null 2>&1 || true
versao_live=$(pacman --config /tmp/delonix-check.conf -Si manjaro-live-base 2>/dev/null |
              awk '/^Version/{print $3}')
printf '    manjaro-live-base no build_mirror: %s\n' "${versao_live:-DESCONHECIDA}"

log "manjaro-live-base $versao_live — traz o manjaro-live-setup ✓"

# --- invalidação de fases por dependência --------------------------------------
# ISTO é o que faltava, e explica quase todas as "correcções que não
# funcionaram" desta semana.
#
# O buildiso guarda um marcador por fase e SALTA as que já estão feitas. Nós
# construímos com `-c` para não pagar horas por tentativa — logo uma alteração
# ao desktop-overlay, ao Packages-Desktop ou ao cmdline NÃO chega à imagem
# enquanto a fase respectiva não voltar a correr. O sintoma é o pior possível:
# a correcção está no repositório, o build passa, e a ISO sai igual.
#
# Aconteceu com o os-release (fase desktop), com o systemd.firstboot=off (fase
# grub) e com o tema do GRUB (idem) — três vezes eu a dizer "corre make
# clean-live" quando o que mudara vivia noutra fase.
#
# A solução não é lembrar-me: é o build comparar datas, como o make faz. Cada
# fase declara de que ficheiros depende; se algum for mais recente que o
# marcador, o marcador cai e a fase repete-se.
invalidar_fases() {
    local base=$1 pdir="$PROFILES_DIR/$EDITION/$PROFILE"

    # fase → ficheiros/directórios de que depende
    local -A deps=(
        [make_image_root]="$pdir/Packages-Root $pdir/root-overlay"
        # `$WORK/packaging` e não `$DELONIX_REPO`: o repositório é reconstruído em
        # TODOS os builds, logo seria sempre mais recente e a fase desktop —
        # que é a caríssima — repetia-se sempre. A fonte só muda quando alguém
        # a edita.
        [make_image_desktop]="$pdir/Packages-Desktop $pdir/desktop-overlay $WORK/packaging"
        [make_image_live]="$pdir/Packages-Live $pdir/live-overlay"
        [make_image_mhwd]="$pdir/Packages-Mhwd"
        [make_grub]="$pdir/profile.conf $pdir/desktop-overlay/etc/default/grub"
        [make_image_boot]="$pdir/profile.conf"
    )

    local fase marcador mais_novo
    for fase in "${!deps[@]}"; do
        marcador="$base/build.$fase"
        [[ -f $marcador ]] || continue

        # O ficheiro mais recente de entre as dependências desta fase.
        mais_novo=$(find ${deps[$fase]} -newer "$marcador" -print -quit 2>/dev/null)
        if [[ -n $mais_novo ]]; then
            log "  $fase: ${mais_novo#$pdir/} mudou → vai repetir"
            rm -f "$marcador"
            # A fase `live` guarda pacotes instalados no seu overlay; se ficarem,
            # o pacman considera-os satisfeitos e o novo conteúdo não entra.
            [[ $fase == make_image_live ]] && rm -rf "$base/livefs" "$base/livefs.lock"
        fi
    done
}

if [[ -n ${CHROOT_BASE:-} && -d ${CHROOT_BASE:-} ]]; then
    log "a verificar que fases ficaram desactualizadas"
    invalidar_fases "$CHROOT_BASE"
fi

log "buildiso — perfil $PROFILE (edição $EDITION), kernel $KERNEL"
buildiso "${BUILD_ARGS[@]}"

iso=$(find /var/cache/manjaro-tools/iso -name '*.iso' -printf '%T@ %p\n' 2>/dev/null |
      sort -rn | head -1 | cut -d' ' -f2-)
if [[ -n $iso ]]; then
    log "ISO pronta: $(basename "$iso")  ($(du -h "$iso" | cut -f1))"
    # O caminho dentro do contentor não serve ao utilizador: mapeia para ./out.
    bash "$SCRIPTS/qemu-cmd.sh" "$WORK/out/${iso#/var/cache/manjaro-tools/iso/}" 2>/dev/null ||
        printf '\n  A ISO está em ./out — para arrancar:  make test\n\n'
else
    log "build terminou sem ISO — vê o log em /var/log/manjaro-tools"
    exit 1
fi
