#!/usr/bin/env bash
# DelonixOS — edição Fedora. Base própria: rpm e dnf, sem tradução de nada.
#
#   ./scripts/build-fedora.sh          # Fedora 41
#   ./scripts/build-fedora.sh 42
#
# O equivalente do mmdebstrap aqui é o `dnf --installroot`, que instala um
# sistema completo noutra raiz. Provado neste projecto antes de escrever o
# script, e a primeira tentativa falhou de forma instrutiva:
#
#   No repositories were loaded from the installroot.
#   To use the configuration and repositories of the host system,
#   pass --use-host-config.
#
# Sem `--use-host-config` o dnf procura os repositórios DENTRO da raiz nova, que
# ainda está vazia. Com ela: 44 pacotes, 164 MB, bash e rg no sítio.
set -euo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PERFIL="$REPO_DIR/iso-profiles/delonix/devops-fedora"
RELEASE=${1:-41}
CACHE="${DELONIX_CACHE:-$REPO_DIR/.cache}/fedora/$RELEASE"
ROOTFS="$CACHE/rootfs"

BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'
log(){ printf '\n%s→ %s%s\n' "$BLD" "$*" "$RST"; }

[[ -f $PERFIL/Packages ]] || {
    cat >&2 <<AVISO

  Falta $PERFIL/Packages

  A edição Fedora tem a fundação (este script, e o `dnf --installroot` provado)
  mas ainda não tem a lista de pacotes mapeada. Em Fedora os nomes divergem
  outra vez — `ripgrep` é igual, mas `fd-find` chama-se `fd-find`, o `bat` é
  `bat`, o `podman` é nativo, e o KDE vem por grupos (`@kde-desktop`).

  O caminho é o mesmo que provou valer nas outras duas edições: escrever a
  lista, correr o preflight (`dnf install --assumeno`), corrigir o que ele
  apanhar, e só depois construir.

AVISO
    exit 1
}

command -v dnf >/dev/null || { echo "este build precisa de dnf no host (ou de um contentor Fedora)"; exit 1; }

log "sistema base — Fedora $RELEASE"
mkdir -p "$CACHE"
PACOTES=$(sed 's/#.*//' "$PERFIL/Packages" | tr -s ' \t' '\n' | grep -E '^[@a-z0-9]' | sort -u)
# `install_weak_deps=False` é o equivalente do `--no-install-recommends`: sem
# isto a imagem cresce com sugestões que ninguém pediu.
sudo dnf -y --installroot="$ROOTFS" --releasever="$RELEASE" --use-host-config \
    --setopt=install_weak_deps=False install $PACOTES

log "PARADO AQUI — o mesmo ponto da edição Debian"
printf '  %sFalta: overlay, squashfs, dracut com dmsquash-live, GRUB e xorriso.%s\n\n' "$DIM" "$RST"
