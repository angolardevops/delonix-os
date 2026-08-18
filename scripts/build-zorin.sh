#!/usr/bin/env bash
# DelonixOS sobre Zorin OS Core — a versão gratuita, remasterizada.
#
#   ./scripts/build-zorin.sh          # Zorin OS 18 Core
#   ./scripts/build-zorin.sh --clean  # deitar fora tudo menos a ISO descarregada
#
# PORQUE ESTE CAMINHO É DIFERENTE DOS OUTROS
#
# Nos alvos Ubuntu/Debian construímos o sistema do zero com `mmdebstrap`. Aqui
# não dá: os pacotes próprios do Zorin NÃO estão num repositório público — medi,
# e o índice de `packages.zorinos.com` está literalmente vazio (0 bytes). Eles
# vivem dentro da ISO.
#
# Logo, para assentar mesmo na base do Zorin, o caminho é remasterizar: partir
# da ISO Core, desempacotar o sistema de ficheiros dela, acrescentar o que é
# nosso, e reempacotar.
#
# DUAS COISAS A SABER ANTES DE COMEÇAR
#
# 1. A ISO são 3,78 GB. Na ligação onde isto foi escrito (~190 KB/s medidos),
#    são cerca de cinco horas e meia. O descarregamento é RETOMÁVEL (`curl -C -`)
#    e fica em cache: paga-se uma vez.
#
# 2. A marca. O Zorin OS é gratuito, mas o nome e o logótipo são marca deles. A
#    remasterização SÓ é redistribuível depois de um rebranding completo — o
#    mesmo trabalho que fizemos com a Manjaro. A fase `marca` abaixo trata disso,
#    e o build recusa terminar se encontrar vestígios.
set -euo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
VERSAO=${DELONIX_ZORIN_VER:-18}
ISO_URL=${DELONIX_ZORIN_ISO:-https://mirrors.edge.kernel.org/zorinos-isos/$VERSAO/Zorin-OS-$VERSAO-Core-64-bit.iso}
CACHE="${DELONIX_CACHE:-$REPO_DIR/.cache}/zorin$VERSAO"
ISO="$CACHE/base.iso"
ROOTFS="$CACHE/rootfs"
PERFIL="$REPO_DIR/iso-profiles/delonix/devops-debian"

BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'
log(){ printf '\n%s→ %s%s\n' "$BLD" "$*" "$RST"; }
etapa(){ printf '  %s· %s%s\n' "$DIM" "$*" "$RST"; }

# A ISO NÃO é apagada pelo --clean: cinco horas de descarregamento não se
# deitam fora por causa de um erro numa fase posterior.
[[ ${1:-} == --clean ]] && { log "a apagar tudo menos a ISO"; sudo rm -rf "$ROOTFS" "$CACHE"/build.*; }

mkdir -p "$CACHE"
for t in xorriso unsquashfs mksquashfs curl; do
    command -v $t >/dev/null || { echo "falta $t no host"; exit 1; }
done

# --- 1. a ISO base -------------------------------------------------------------
if [[ ! -f $CACHE/build.iso ]]; then
    log "ISO base do Zorin OS $VERSAO Core"
    TAM=$(curl -sIL --max-time 30 "$ISO_URL" | grep -i '^content-length' | tail -1 | tr -dc '0-9')
    etapa "$(( ${TAM:-0} / 1048576 )) MB · $ISO_URL"
    [[ -f $ISO ]] && etapa "a retomar de $(( $(stat -c%s "$ISO") / 1048576 )) MB"
    # `-C -` retoma; `--retry` sobrevive a quedas. Sem isto, cinco horas de
    # descarregamento perdem-se num soluço da rede — e nesta ligação há soluços.
    curl -L -C - --retry 10 --retry-delay 15 --retry-all-errors \
         -o "$ISO" "$ISO_URL"
    [[ -n ${TAM:-} && $(stat -c%s "$ISO") -eq $TAM ]] ||
        { echo "a ISO ficou incompleta — corre outra vez, retoma de onde parou"; exit 1; }
    touch "$CACHE/build.iso"
fi

# --- 2. desempacotar -----------------------------------------------------------
if [[ ! -f $CACHE/build.rootfs ]]; then
    log "a desempacotar o sistema de ficheiros do Zorin"
    # O caminho do squashfs muda entre versões e entre famílias de instalador
    # (casper no Ubuntu, live no Debian). Procuramos em vez de o adivinhar.
    SFS_INTERNO=$(xorriso -indev "$ISO" -find / -name '*.squashfs' 2>/dev/null |
                  grep -oE "'/[^']+'" | tr -d "'" | head -1)
    [[ -n $SFS_INTERNO ]] || { echo "não encontrei nenhum .squashfs dentro da ISO"; exit 1; }
    etapa "encontrado: $SFS_INTERNO"
    xorriso -osirrox on -indev "$ISO" -extract "$SFS_INTERNO" "$CACHE/base.squashfs" 2>&1 | tail -1
    sudo rm -rf "$ROOTFS"
    sudo unsquashfs -d "$ROOTFS" "$CACHE/base.squashfs"
    etapa "rootfs: $(sudo du -sh "$ROOTFS" | cut -f1)"
    sudo touch "$CACHE/build.rootfs"
fi

log "PARADO AQUI — o que falta, e não vou dar por feito"
cat <<'FALTA'

  Feito e reutilizável: a ISO em cache e o rootfs do Zorin desempacotado.

  Falta:
    · instalar os nossos pacotes no chroot (apt, com os repos do Zorin que a
      própria ISO traz configurados — é aqui que a base dele conta de facto)
    · REBRANDING: tirar zorin-os-desktop, os temas e o Plymouth deles, e pôr a
      identidade Delonix. Sem isto a imagem não é redistribuível.
    · reempacotar o squashfs e montar a ISO

  A ordem importa: o rebranding depois dos pacotes, para o apt não repor o que
  se tirou.

FALTA
