#!/usr/bin/env bash
# DelonixOS — compila os pacotes do AUR para um repositório pacman local.
#
# Porquê: o `buildiso` instala apenas de repositórios. Sem isto, tudo o que vem
# do AUR (claude-code, antigravity, cloud-hypervisor, gcloud, …) teria de ser
# instalado à mão depois do primeiro arranque — e o pedido era "pronto a usar".
#
# Corre DENTRO do contentor de build, como root. Cria o utilizador `builder`
# (o makepkg recusa-se a correr como root, e com razão).
#
#   ./scripts/build-aur-repo.sh <lista> <destino-do-repo>
#
# Tolerante a falhas: um pacote do AUR que não compile NÃO trava a ISO — fica
# registado em <destino>/FALHADOS e o filter-missing-aur.py remove-o das listas.
set -uo pipefail

LIST=${1:?uso: build-aur-repo.sh <packages/aur.list> <dir-do-repo>}
REPO=${2:?uso: build-aur-repo.sh <packages/aur.list> <dir-do-repo>}
REPO_NAME=delonix-aur
BUILDER=builder

log()  { printf '\n\e[1m→ %s\e[0m\n' "$*"; }
warn() { printf '\e[33m!\e[0m %s\n' "$*"; }

mkdir -p "$REPO"
: >"$REPO/FALHADOS"

# --- utilizador de build ------------------------------------------------------
if ! id "$BUILDER" &>/dev/null; then
    useradd -m -s /bin/bash "$BUILDER"
    echo "$BUILDER ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/99-builder
fi
install -d -o "$BUILDER" -g "$BUILDER" /home/$BUILDER/aur "$REPO"
chown -R "$BUILDER:$BUILDER" "$REPO"

pacman -S --needed --noconfirm base-devel git go rust nodejs npm unzip >/dev/null

mapfile -t PKGS < <(sed 's/#.*//' "$LIST" | tr -d ' \t' | grep -v '^$')
log "${#PKGS[@]} pacote(s) do AUR a compilar"

for pkg in "${PKGS[@]}"; do
    log "$pkg"
    src=/home/$BUILDER/aur/$pkg

    if ! sudo -u "$BUILDER" git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$src" 2>/dev/null; then
        warn "$pkg: clone falhou"
        echo "$pkg" >>"$REPO/FALHADOS"
        continue
    fi

    # --syncdeps instala dependências dos repos; --noconfirm para não bloquear.
    if sudo -u "$BUILDER" bash -c "cd '$src' && makepkg --syncdeps --noconfirm --clean --skippgpcheck"; then
        cp "$src"/*.pkg.tar.* "$REPO"/ 2>/dev/null && printf '  \e[32m✓\e[0m %s\n' "$pkg"
    else
        warn "$pkg: makepkg falhou (a ISO sai sem ele)"
        echo "$pkg" >>"$REPO/FALHADOS"
    fi
done

# --- índice do repositório ------------------------------------------------------
log "a indexar $REPO_NAME"
shopt -s nullglob
pkgs=("$REPO"/*.pkg.tar.*)
if (( ${#pkgs[@]} == 0 )); then
    warn "nenhum pacote do AUR compilou — o repositório fica vazio"
    exit 0
fi
repo-add -q "$REPO/$REPO_NAME.db.tar.gz" "${pkgs[@]}"
chmod -R a+rX "$REPO"

printf '\n\e[32m✓\e[0m %d pacote(s) no repositório local\n' "${#pkgs[@]}"
if [[ -s $REPO/FALHADOS ]]; then
    warn "falharam: $(tr '\n' ' ' <"$REPO/FALHADOS")"
fi
