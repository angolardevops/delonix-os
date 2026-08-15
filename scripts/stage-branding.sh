#!/usr/bin/env bash
# Monta o payload do pacote delonix-os-branding em build/branding:
#   ficheiros escritos à mão (packaging/.../payload) + PNG gerados (gen-assets).
#
# Existe para haver UMA definição deste passo — o Makefile e o
# build-os-packages.sh chamam isto, em vez de cada um fazer a sua versão.
set -euo pipefail

# A raiz do repositório: normalmente deduz-se do caminho do script, mas quando
# este corre de uma cópia (build dentro do contentor) tem de vir do ambiente.
REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DEST=${1:-$REPO_DIR/build/branding}

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$REPO_DIR/packaging/delonix-os-branding/payload/." "$DEST/"
python3 "$REPO_DIR/branding/gen-assets.py" --out "$DEST/usr/share" "${@:2}"
