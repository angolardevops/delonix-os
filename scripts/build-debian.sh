#!/usr/bin/env bash
# DelonixOS — construir a ISO da edição Debian/Ubuntu.
#
#   ./scripts/build-debian.sh              # ISO completa
#   ./scripts/build-debian.sh --clean      # deitar fora o rootfs e recomeçar
#
# PORQUE NÃO `live-build`
#
# O `live-build` é a ferramenta clássica do Debian e faz isto tudo. Não a usamos
# por uma razão que esta semana tornou muito clara: o valor está em conseguir
# DEPURAR. O live-build esconde as fases atrás de configuração própria, e quando
# falha a meio é preciso aprender as convenções dele para descobrir onde.
#
# O que se segue são cinco passos legíveis — debootstrap, pacotes, overlay,
# squashfs, ISO — cada um com o seu marcador. Se falhar, vê-se onde e repete-se
# só esse. É o mesmo modelo do buildiso, mas escrito por nós e sem surpresas.
set -euo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PERFIL="$REPO_DIR/iso-profiles/delonix/devops-debian"
CACHE="${DELONIX_CACHE:-$REPO_DIR/.cache}/debian"
OUT="$REPO_DIR/out/debian"
SUITE=${DELONIX_SUITE:-noble}          # Ubuntu 24.04 LTS, a base do Zorin 18
MIRROR=${DELONIX_APT_MIRROR:-http://archive.ubuntu.com/ubuntu}
ROOTFS="$CACHE/rootfs"

BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'
log()  { printf '\n%s→ %s%s\n' "$BLD" "$*" "$RST"; }
etapa(){ printf '  %s· %s%s\n' "$DIM" "$*" "$RST"; }

[[ ${1:-} == --clean ]] && { log "a apagar $ROOTFS"; sudo rm -rf "$CACHE"; }

mkdir -p "$CACHE" "$OUT"

# --- 0. o que é preciso no host ------------------------------------------------
# Falhar aqui, no primeiro segundo, e não a meio. A lição do sudo sem terminal
# vale para tudo o resto: o que vai correr mal descobre-se antes de gastar tempo.
FALTA=()
for t in mmdebstrap xorriso mksquashfs; do command -v $t >/dev/null || FALTA+=("$t"); done
if (( ${#FALTA[@]} )); then
    cat >&2 <<AVISO

  Faltam ferramentas no host: ${FALTA[*]}

  Em Debian/Ubuntu:
      sudo apt-get install -y mmdebstrap xorriso squashfs-tools
  Em Arch/Manjaro:
      sudo pacman -S --needed xorriso squashfs-tools   # o mmdebstrap vem do AUR

  Ao contrário da edição Manjaro, este build NÃO corre dentro de um contentor:
  o mmdebstrap sabe construir um sistema Debian a partir de qualquer host, e
  isso poupa-nos a camada que mais problemas deu na outra edição.

AVISO
    exit 1
fi
if ! sudo -n true 2>/dev/null && [[ ! -t 0 ]]; then
    echo "este build precisa de sudo e não há terminal para o pedir — corre à mão" >&2
    exit 1
fi

# --- 1. rootfs -----------------------------------------------------------------
if [[ ! -f $CACHE/build.rootfs ]]; then
    log "a criar o sistema base ($SUITE)"
    PACOTES=$(sed 's/#.*//' "$PERFIL/Packages" | tr -s ' \t' '\n' |
              grep -E '^[a-z0-9]' | sort -u | paste -sd,)
    # `--variant=important` dá o mínimo utilizável sem os `recommends` que
    # enchem a imagem — é o equivalente do que fizemos com o `--needed`.
    sudo mmdebstrap \
        --variant=important \
        --components='main,universe,multiverse,restricted' \
        --include="$PACOTES" \
        --aptopt='Apt::Install-Recommends "false"' \
        "$SUITE" "$ROOTFS" "$MIRROR"
    sudo touch "$CACHE/build.rootfs"
else
    etapa "rootfs já existe (--clean para refazer)"
fi

# --- 2. overlay e identidade ---------------------------------------------------
# O overlay é copiado SEMPRE: é barato, e foi por assumir o contrário que na
# edição Manjaro várias correcções nunca chegaram à imagem.
log "a aplicar a identidade Delonix"
if [[ -d $PERFIL/rootfs-overlay ]]; then
    sudo cp -a "$PERFIL/rootfs-overlay/." "$ROOTFS/"
    etapa "rootfs-overlay aplicado"
fi
# A marca vem do mesmo sítio que a edição Manjaro — um único conjunto de assets
# para as duas, que é metade da razão de o branding ser um pacote.
if [[ -d $REPO_DIR/build/branding ]]; then
    sudo cp -a "$REPO_DIR/build/branding/usr" "$ROOTFS/"
    etapa "marca Delonix aplicada"
fi

# --- 3. squashfs ---------------------------------------------------------------
log "a comprimir o sistema de ficheiros"
SFS="$CACHE/filesystem.squashfs"
sudo rm -f "$SFS"
# zstd nível 19: comprime como o xz e descomprime muito mais depressa — num live
# é a descompressão que se sente, em cada ficheiro aberto.
sudo mksquashfs "$ROOTFS" "$SFS" -comp zstd -Xcompression-level 19 -noappend -quiet
etapa "$(du -h "$SFS" | cut -f1)"

log "PARADO AQUI DE PROPÓSITO"
cat <<'FALTA'

  O que falta para haver ISO, e não vou fingir que já está:

    · initramfs com live-boot (para arrancar de um squashfs só de leitura)
    · entradas de arranque GRUB para EFI e BIOS
    · xorriso a montar tudo com El Torito nas duas plataformas
    · Calamares configurado para a família Debian

  O rootfs e o squashfs acima são reais e reutilizáveis. O resto é o próximo
  passo, e é onde a edição Manjaro gastou mais tempo — vale a pena fazê-lo com
  calma em vez de o esboçar.

FALTA
