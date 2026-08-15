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

# --- 0. mirrors ACTUALIZADOS --------------------------------------------------
# Isto não é afinação de velocidade — é correcção.
#
# O que aconteceu a 2026-08-15: um mirror da lista estava um mês atrasado, serviu
# uma base de dados velha, e o pacman resolveu `manjaro-live-base` para a versão
# 20241119 em vez da 20260802. Essa versão antiga instala /usr/bin/manjaro-live;
# a nova instala /usr/bin/manjaro-live-setup — que é o que o manjaro-tools ACTUAL
# invoca. Resultado, a 40 minutos de build:
#
#   chroot: failed to run command '/usr/bin/manjaro-live-setup': No such file
#
# Pior: como a versão velha já estava na cache de pacotes partilhada, o pacman
# instalou-a sem descarregar nada. Não houve erro de rede nenhum para se ver.
#
# `--fasttrack` só mantém mirrors que estão MESMO sincronizados, e é para isso
# que existe. Se falhar (sem rede para a API), seguimos com a lista da imagem —
# a verificação de frescura abaixo é que decide se isso é aceitável.
log "a escolher mirrors sincronizados (--fasttrack)"
pacman-mirrors --api --protocol https --set-branch "${BRANCH:-stable}" >/dev/null 2>&1 || true
pacman-mirrors --fasttrack 5 >/dev/null 2>&1 || log "aviso: pacman-mirrors falhou; a usar a lista da imagem"

# --- 1. dependências ----------------------------------------------------------
log "a sincronizar pacman e instalar manjaro-tools"
pacman-key --init 2>/dev/null || true
pacman-key --populate archlinux manjaro 2>/dev/null || true

# `-Syy` e não `-Sy`: força o descarregamento das bases de dados mesmo que o
# pacman as considere actuais. Uma db em cache vinda de um mirror atrasado é
# exactamente o problema que estamos a evitar.
pacman -Syy --noconfirm >/dev/null 2>&1 || true

# Guarda de frescura: se as bases de dados que vamos usar têm mais de uma
# semana, alguma coisa está errada com os mirrors e mais vale parar aqui do que
# construir uma ISO com pacotes de há meses.
db_idade=$(( ($(date +%s) - $(stat -c %Y /var/lib/pacman/sync/extra.db 2>/dev/null || date +%s)) / 86400 ))
if (( db_idade > 7 )); then
    log "ERRO: a base de dados 'extra' tem $db_idade dias — os mirrors estão atrasados."
    log "      Construir assim dá uma ISO com pacotes desactualizados e falhas"
    log "      difíceis de explicar. Tenta outra vez, ou força um mirror:"
    log "      DELONIX_MIRROR=https://mirror.alpix.eu/manjaro make iso"
    exit 1
fi
log "bases de dados com $db_idade dia(s)"

pacman -Su --noconfirm --needed \
    manjaro-tools-iso manjaro-tools-base git rsync curl \
    squashfs-tools dosfstools libisoburn grub edk2-shell erofs-utils \
    python python-pillow

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
