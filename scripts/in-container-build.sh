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
if [[ ! -d $PROFILES_DIR/.git ]]; then
    log "a clonar o iso-profiles oficial"
    rm -rf "$PROFILES_DIR"
    git clone --depth 1 "$UPSTREAM" "$PROFILES_DIR"
fi

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
log "a configurar o manjaro-tools"
install -Dm644 /dev/stdin /etc/manjaro-tools/manjaro-tools.conf <<EOF
# gerado pelo build do DelonixOS
branch=stable
dist_name="${DIST_NAME:-DelonixOS}"
dist_release="${DIST_VER:-1.0}"
dist_codename="${DIST_CODE:-Acacia}"
dist_branding="DELONIX"
iso_name="$(echo "${DIST_NAME:-delonixos}" | tr 'A-Z ' 'a-z-')"
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
    for fs in rootfs desktopfs livefs; do
        [[ -d $CHROOT_BASE/$fs ]] || continue
        install -Dm644 /etc/pacman.d/mirrorlist "$CHROOT_BASE/$fs/etc/pacman.d/mirrorlist"
        # As dbs já descarregadas do mirror atrasado TÊM de sair: o pacman
        # considera-as actuais e nunca chega a usar os mirrors novos. A data
        # delas é a do servidor, por isso dá para ver de onde vieram.
        rm -f "$CHROOT_BASE/$fs"/var/lib/pacman/sync/{core,extra,multilib}.db
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

versao_live=$(pacman -Si manjaro-live-base 2>/dev/null | awk '/^Version/{print $3}')
printf '    manjaro-live-base resolve para: %s\n' "${versao_live:-DESCONHECIDA}"

if [[ ${versao_live:-} != 2026* ]]; then
    cat >&2 <<AVISO

  O pacman resolve manjaro-live-base para ${versao_live:-nada}, e não para uma
  versão de 2026. Só a de 2026 traz /usr/bin/manjaro-live-setup, que é o
  binário que o manjaro-tools invoca na fase live — sem ele, o build morre lá,
  ao fim de horas, com um "No such file or directory".

  As datas das bases de dados estão acima. Se forem antigas, os mirrors ou a
  sincronização falharam. Força um mirror e recomeça a fase live:

      make clean-live
      DELONIX_MIRROR=https://mirrors.ft.uam.es/manjaro make iso

AVISO
    exit 1
fi
log "manjaro-live-base $versao_live — traz o manjaro-live-setup ✓"

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
