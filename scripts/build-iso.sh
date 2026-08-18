#!/usr/bin/env bash
# DelonixOS — um comando para qualquer distro.
#
#   make iso                 # Manjaro (a edição de referência)
#   make iso zorinos         # Zorin OS 18 — base Ubuntu + repositórios Zorin
#   make iso ubuntu          # Ubuntu 24.04 LTS
#   make iso debian          # Debian 12
#   make iso fedora          # Fedora 41
#
# CADA DISTRO ASSENTA NA SUA PRÓPRIA BASE. Não há tradução nem emulação: o alvo
# escolhe o motor de construção, os repositórios e o gestor de pacotes que essa
# distribuição usa de facto.
#
#   manjaro, arch          → manjaro-tools (pacman)      scripts/build.sh
#   zorinos, ubuntu, debian → mmdebstrap (apt)           scripts/build-debian.sh
#   fedora                 → dnf --installroot (rpm)     scripts/build-fedora.sh
#
# O Zorin é um alvo PRÓPRIO, não um apelido de Ubuntu: assenta na base Ubuntu
# como todos os derivados, mas com os repositórios `stable`, `patches` e `apps`
# do Zorin acrescentados. É o que distingue construir sobre o Zorin de construir
# sobre o Ubuntu e chamar-lhe Zorin.
set -euo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
DISTRO=${1:-manjaro}; shift || true

BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'

case ${DISTRO,,} in
    manjaro|arch)
        printf '\n%s→ Manjaro%s %s(manjaro-tools · pacman)%s\n' "$BLD" "$RST" "$DIM" "$RST"
        exec "$REPO_DIR/scripts/build.sh" "$@"
        ;;
    zorinos|zorin|zorin18)
        # A base REAL do Zorin: a ISO Core gratuita, remasterizada. Os pacotes
        # próprios dele NÃO estão em repositório público — medido, o índice de
        # packages.zorinos.com tem 0 bytes — vivem dentro da ISO. Por isso este
        # alvo não usa o mmdebstrap como os outros da família Debian.
        printf '\n%s→ Zorin OS 18 Core%s %s(ISO gratuita remasterizada)%s\n' "$BLD" "$RST" "$DIM" "$RST"
        exec "$REPO_DIR/scripts/build-zorin.sh" "$@"
        ;;
    zorin-ubuntu)
        # A alternativa honesta: Ubuntu 24.04 puro, a base de que o Zorin deriva.
        # Horas mais rápido e sem questões de marca — mas sem nada do Zorin.
        printf '\n%s→ Ubuntu 24.04%s %s(a base do Zorin, sem o Zorin)%s\n' "$BLD" "$RST" "$DIM" "$RST"
        exec "$REPO_DIR/scripts/build-debian.sh" noble "$@"
        ;;
    zorin17)
        exec "$REPO_DIR/scripts/build-debian.sh" zorin17 "$@" ;;
    ubuntu|noble)
        printf '\n%s→ Ubuntu 24.04 LTS%s %s(mmdebstrap · apt)%s\n' "$BLD" "$RST" "$DIM" "$RST"
        exec "$REPO_DIR/scripts/build-debian.sh" noble "$@"
        ;;
    ubuntu22|jammy)
        exec "$REPO_DIR/scripts/build-debian.sh" jammy "$@" ;;
    debian|bookworm)
        printf '\n%s→ Debian 12%s %s(mmdebstrap · apt)%s\n' "$BLD" "$RST" "$DIM" "$RST"
        exec "$REPO_DIR/scripts/build-debian.sh" bookworm "$@"
        ;;
    trixie)
        exec "$REPO_DIR/scripts/build-debian.sh" trixie "$@" ;;
    fedora|fedora41)
        printf '\n%s→ Fedora 41%s %s(dnf --installroot · rpm)%s\n' "$BLD" "$RST" "$DIM" "$RST"
        exec "$REPO_DIR/scripts/build-fedora.sh" 41 "$@"
        ;;
    *)
        cat >&2 <<AVISO

  distro desconhecida: $DISTRO

  Cada uma constrói sobre a SUA base, com o gestor de pacotes dela:

    make iso                 Manjaro      manjaro-tools · pacman
    make iso zorinos         Zorin OS 18  mmdebstrap · apt + repos Zorin
    make iso ubuntu          Ubuntu 24.04 mmdebstrap · apt
    make iso debian          Debian 12    mmdebstrap · apt
    make iso fedora          Fedora 41    dnf --installroot · rpm

AVISO
        exit 2
        ;;
esac
