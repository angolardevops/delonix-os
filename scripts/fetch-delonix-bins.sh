#!/usr/bin/env bash
# Coloca os binários da casa (Delonix Runtime + delonixctl) dentro do overlay,
# para virem já na ISO em vez de serem instalados depois.
#
#   ./scripts/fetch-delonix-bins.sh <destino>
#
# Fontes, por ordem:
#   1. DELONIX_BIN_DIR — binários já compilados localmente (dev)
#   2. releases publicados no GitHub
#
# Sem rede e sem binários locais: avisa e sai com 0 (a ISO fica sem o motor da
# casa, e o `delonix-toolbox install delonix` resolve depois).
set -euo pipefail

DEST=${1:?uso: fetch-delonix-bins.sh <directoria-destino>}
REPO=${DELONIX_REPO:-angolardevops/delonix-runtime}
TARGET=x86_64-unknown-linux-gnu

mkdir -p "$DEST"

if [[ -n ${DELONIX_BIN_DIR:-} && -d $DELONIX_BIN_DIR ]]; then
    echo "→ a copiar binários locais de $DELONIX_BIN_DIR"
    for bin in delonix delonixctl; do
        [[ -x $DELONIX_BIN_DIR/$bin ]] && install -Dm755 "$DELONIX_BIN_DIR/$bin" "$DEST/$bin" &&
            echo "  ✓ $bin"
    done
    exit 0
fi

echo "→ a tentar releases de $REPO"
for bin in delonix delonixctl; do
    url="https://github.com/$REPO/releases/latest/download/${bin}-${TARGET}"
    if curl -fsSL --retry 2 --max-time 120 "$url" -o "$DEST/$bin.tmp"; then
        install -Dm755 "$DEST/$bin.tmp" "$DEST/$bin"
        rm -f "$DEST/$bin.tmp"
        echo "  ✓ $bin"
    else
        rm -f "$DEST/$bin.tmp"
        echo "  ! $bin indisponível — a ISO sai sem ele"
    fi
done
