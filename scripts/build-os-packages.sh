#!/usr/bin/env bash
# DelonixOS — compila os pacotes da casa para o repositório local `[delonix]`.
#
# É este passo que resolve o problema do overlay: o branding, a afinação de
# sistema e as ferramentas passam a ser pacotes normais, com versão, e chegam a
# quem já instalou através do `pacman -Syu`. Um ficheiro copiado para dentro da
# imagem nunca mais muda.
#
#   ./scripts/build-os-packages.sh [dir-do-repo]
#
# Corre dentro do contentor de build (como root, cria o utilizador `builder`) ou
# num host Arch/Manjaro. Fora de um host com `makepkg` sai sem fazer nada — não
# há como compilar um pacote pacman noutro sítio.
set -euo pipefail

# A raiz do repositório: normalmente deduz-se do caminho do script, mas quando
# este corre de uma cópia (build dentro do contentor) tem de vir do ambiente.
REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
OUT_REPO=${1:-/var/cache/delonix-repo}
REPO_NAME=delonix
VER=$(tr -d '[:space:]' <"$REPO_DIR/VERSION")
BUILDER=${DELONIX_BUILDER:-builder}
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

log()  { printf '\n\e[1m→ %s\e[0m\n' "$*"; }
warn() { printf '\e[33m!\e[0m %s\n' "$*"; }

command -v makepkg >/dev/null || {
    warn "sem makepkg — os pacotes do DelonixOS só se compilam em Arch/Manjaro"
    exit 0
}

# --- 1. o branding tem de estar montado --------------------------------------
if [[ ! -f $REPO_DIR/build/branding/usr/share/plymouth/themes/delonix/anim-00.png ]]; then
    log "a montar o payload da marca (ficheiros do tema + PNG gerados)"
    bash "$REPO_DIR/scripts/stage-branding.sh" >/dev/null
fi

# --- 2. tarball único com os três payloads -----------------------------------
log "a preparar o tarball de origem (v$VER)"
mkdir -p "$STAGE/src"
cp -a "$REPO_DIR/build/branding" "$STAGE/src/branding"
cp -a "$REPO_DIR/packaging/delonix-os-settings/payload" "$STAGE/src/settings"
cp -a "$REPO_DIR/packaging/delonix-os-tools/payload" "$STAGE/src/tools"
cp -a "$REPO_DIR/packaging/delonix-os-branding/hooks" "$STAGE/src/branding-hooks"

TARBALL="delonix-os-$VER.tar.gz"
tar czf "$STAGE/$TARBALL" -C "$STAGE/src" branding settings tools branding-hooks

# --- 3. compilar --------------------------------------------------------------
mkdir -p "$OUT_REPO"
if [[ $(id -u) -eq 0 ]]; then
    id "$BUILDER" &>/dev/null || {
        useradd -m -s /bin/bash "$BUILDER"
        echo "$BUILDER ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/99-builder
    }
    RUN=(sudo -u "$BUILDER")
    chmod -R a+rX "$STAGE"
else
    RUN=()
fi

built=0
for pkg in delonix-os-branding delonix-os-settings delonix-os-tools delonix-os; do
    log "$pkg $VER"
    work="$STAGE/build/$pkg"
    mkdir -p "$work"
    cp -a "$REPO_DIR/packaging/$pkg/." "$work/"
    rm -rf "$work/payload" "$work/hooks"        # já estão dentro do tarball
    cp "$STAGE/$TARBALL" "$work/" 2>/dev/null || true

    # A versão vem do ficheiro VERSION — uma fonte de verdade só.
    sed -i "s|^pkgver=.*|pkgver=$VER|" "$work/PKGBUILD"

    chmod -R a+rwX "$work"
    if (cd "$work" && "${RUN[@]}" makepkg --noconfirm --clean --nodeps --skipinteg); then
        cp "$work"/*.pkg.tar.* "$OUT_REPO"/ 2>/dev/null && ((built++)) &&
            printf '  \e[32m✓\e[0m %s\n' "$pkg"
    else
        warn "$pkg falhou a compilar"
    fi
done

(( built )) || { warn "nenhum pacote da casa compilou"; exit 1; }

# --- 4. índice do repositório --------------------------------------------------
log "a indexar [$REPO_NAME]"
shopt -s nullglob
repo-add -q "$OUT_REPO/$REPO_NAME.db.tar.gz" "$OUT_REPO"/*.pkg.tar.*
chmod -R a+rX "$OUT_REPO"

printf '\n\e[32m✓\e[0m %d pacote(s) em %s\n' "$built" "$OUT_REPO"
printf '  Para publicar (é isto que faz as actualizações chegarem aos utilizadores):\n'
printf '    rsync -av %s/ servidor:/srv/repo/delonix/x86_64/\n' "$OUT_REPO"
printf '    e no cliente, em /etc/pacman.conf:\n'
printf '      [delonix]\n      Server = https://repo.ngolacloud.com/delonix/$arch\n\n'
