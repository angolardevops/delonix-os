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
# E TUDO ISTO SEM ROOT
#
# Remasterizar pede, à primeira vista, um `sudo` em cada passo: desempacotar
# preserva posses, o `apt` corre num chroot, o `mksquashfs` grava ficheiros do
# root. Nesta máquina o sudo pede senha — e um build que pára a pedir senha não
# corre em CI nem de madrugada.
#
# A saída é a mesma que o `delonix-runtime` usa para containers: um user
# namespace. Dentro dele somos uid 0, e o `--map-auto` estende o mapa às faixas
# de `/etc/subuid`, que é o que faz um ficheiro do uid 999 sobreviver ao ciclo.
# Medido, e não suposto:
#
#   dentro do namespace   uid 999
#   no disco do host      uid 100998   (999 + a base 100000 do subuid)
#   depois de reempacotar uid 999      ✓
#
# Duas limitações reais do namespace, ambas contornadas abaixo:
#
#   · `mknod` é recusado pelo kernel, sempre. O `unsquashfs` deita fora os nós
#     de dispositivo em SILÊNCIO — diz «created 0 devices» e devolve 0. Por isso
#     a fase 2 lê a lista de nós da imagem original ANTES de desempacotar, e a
#     fase 5 recria-os com `mksquashfs -p`, que os sintetiza dentro da imagem
#     sem precisar de os criar no disco.
#   · o `mount -t sysfs` não é permitido; usamos bind do /sys do host.
#
# A MARCA
#
# O Zorin OS é gratuito, mas o nome e o logótipo são marca deles. A
# remasterização SÓ é redistribuível depois de um rebranding completo — o mesmo
# trabalho que fizemos com a Manjaro. A fase 4 trata disso, e o build RECUSA
# terminar se ainda encontrar vestígios.
set -euo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
VERSAO=${DELONIX_ZORIN_VER:-18}
ISO_URL=${DELONIX_ZORIN_ISO:-https://mirrors.edge.kernel.org/zorinos-isos/$VERSAO/Zorin-OS-$VERSAO-Core-64-bit.iso}
CACHE="${DELONIX_CACHE:-$REPO_DIR/.cache}/zorin$VERSAO"
ISO="$CACHE/base.iso"
ROOTFS="$CACHE/rootfs"
ARVORE="$CACHE/iso"                       # o resto da ISO, sem o squashfs
PERFIL="$REPO_DIR/iso-profiles/delonix/devops-debian"
SAIDA=${DELONIX_SAIDA:-$REPO_DIR/out}
ALVO="zorin$VERSAO"

BLD=$'\e[1m'; DIM=$'\e[2m'; VRM=$'\e[31m'; RST=$'\e[0m'
log(){ printf '\n%s→ %s%s\n' "$BLD" "$*" "$RST"; }
etapa(){ printf '  %s· %s%s\n' "$DIM" "$*" "$RST"; }
erro(){ printf '\n%s✗ %s%s\n\n' "$VRM" "$*" "$RST" >&2; exit 1; }

# Corre o que lhe for dado dentro do namespace, como root. Tudo o que toca no
# rootfs passa por aqui.
sem_root(){ unshare --map-auto --map-root-user --mount --pid --fork "$@"; }

##############################################################################
# --interno: os troços que já correm DENTRO do namespace.
##############################################################################
if [[ ${1:-} == --interno ]]; then
    case $2 in
    desempacotar)
        unsquashfs -d "$ROOTFS" "$CACHE/base.squashfs"
        ;;
    pacotes)
        # O `apt` de um chroot precisa de /proc para ler cmdline e de resolução
        # de nomes. O /sys vai por bind porque `mount -t sysfs` é recusado num
        # user namespace sem netns próprio.
        mount --bind /proc "$ROOTFS/proc"
        mount --bind /sys  "$ROOTFS/sys"
        mount --bind /dev  "$ROOTFS/dev"
        cp -f /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

        # Sem isto o dpkg tenta ARRANCAR os serviços que instala, dentro de um
        # chroot que não tem systemd a correr — e cada um falha ruidosamente.
        printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
        chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"

        mkdir -p "$ROOTFS/tmp/debs"
        cp "$CACHE"/debs/*.deb "$ROOTFS/tmp/debs/" 2>/dev/null || true
        cp "$CACHE/lista-pacotes" "$ROOTFS/tmp/lista-pacotes"

        chroot "$ROOTFS" /bin/bash -eu <<'DENTRO'
export DEBIAN_FRONTEND=noninteractive LANG=C
apt-get update -qq
# `--no-install-recommends`: os recommends do Ubuntu arrastam ~1,5 GB de coisas
# que ninguém pediu. O que for mesmo preciso está na lista, por nome.
xargs -a /tmp/lista-pacotes apt-get install -y -qq --no-install-recommends
apt-get install -y -qq /tmp/debs/*.deb
apt-get clean
DENTRO
        rm -f "$ROOTFS/usr/sbin/policy-rc.d" "$ROOTFS/tmp/lista-pacotes"
        rm -rf "$ROOTFS/tmp/debs"
        umount -l "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev"
        ;;
    marca)
        chroot "$ROOTFS" /bin/bash -eu <<'DENTRO'
export DEBIAN_FRONTEND=noninteractive
# A ordem é esta de propósito: purgar PRIMEIRO, escrever a identidade DEPOIS.
# Ao contrário, o apt repõe por cima o que se tinha acabado de escrever — foi
# exactamente o que aconteceu na edição Manjaro com o os-release.
alvos=$(dpkg-query -W -f='${Package}\n' 2>/dev/null |
        grep -E '^zorin-(os-)?(desktop|themes|icons|wallpapers|plymouth|appearance|artwork)' || true)
[[ -n $alvos ]] && apt-get purge -y -qq $alvos || true
apt-get autoremove -y -qq
DENTRO
        # A identidade. Escrita a partir do que o repositório já tem — uma só
        # fonte para as duas edições.
        . "$PERFIL/../devops/desktop-overlay/usr/lib/os-release" 2>/dev/null || true
        cat > "$ROOTFS/usr/lib/os-release" <<EOF
NAME="DelonixOS"
PRETTY_NAME="DelonixOS (Zorin base)"
ID=delonixos
ID_LIKE="ubuntu debian"
BUILD_ID=$(date -u +%Y.%m.%d)
ANSI_COLOR="1;31"
HOME_URL="https://github.com/angolardevops/delonix-os"
SUPPORT_URL="https://github.com/angolardevops/delonix-os/issues"
BUG_REPORT_URL="https://github.com/angolardevops/delonix-os/issues"
LOGO=delonix
EOF
        ln -sf ../usr/lib/os-release "$ROOTFS/etc/os-release"
        printf 'DelonixOS \\n \\l\n\n' > "$ROOTFS/etc/issue"
        printf 'DelonixOS\n' > "$ROOTFS/etc/issue.net"
        cat > "$ROOTFS/etc/lsb-release" <<EOF
DISTRIB_ID=DelonixOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=delonix
DISTRIB_DESCRIPTION="DelonixOS"
EOF
        ;;
    empacotar)
        # Os nós de dispositivo que o namespace não deixou criar voltam AQUI,
        # sintetizados pelo mksquashfs a partir da lista lida na fase 2.
        mapfile -t pseudo < "$CACHE/nos-de-dispositivo"
        args=()
        for p in "${pseudo[@]}"; do [[ -n $p ]] && args+=(-p "$p"); done
        # zstd-19: a descompressão é o que conta num live — a imagem é lida a
        # cada arranque e comprimida uma só vez.
        mksquashfs "$ROOTFS" "$CACHE/novo.squashfs" \
            -comp zstd -Xcompression-level 19 -b 1M -noappend -no-progress \
            "${args[@]}"
        ;;
    esac
    exit 0
fi

##############################################################################
# o fluxo
##############################################################################
[[ ${1:-} == --clean ]] && { log "a apagar tudo menos a ISO"; rm -rf "$ROOTFS" "$ARVORE" "$CACHE"/build.* "$CACHE"/*.squashfs; }

mkdir -p "$CACHE" "$SAIDA"
for t in xorriso unsquashfs mksquashfs curl unshare dpkg-deb; do
    command -v $t >/dev/null || erro "falta $t no host"
done
grep -q "^$USER:" /etc/subuid ||
    erro "sem faixa em /etc/subuid — sem ela o namespace não preserva as posses dos ficheiros"

# --- 1. a ISO base -------------------------------------------------------------
if [[ ! -f $CACHE/build.iso ]]; then
    log "ISO base do Zorin OS $VERSAO Core"
    TAM=$(curl -sIL --max-time 30 "$ISO_URL" | grep -i '^content-length' | tail -1 | tr -dc '0-9')
    etapa "$(( ${TAM:-0} / 1048576 )) MB · $ISO_URL"
    [[ -f $ISO ]] && etapa "a retomar de $(( $(stat -c%s "$ISO") / 1048576 )) MB"
    curl -L -C - --retry 10 --retry-delay 15 --retry-all-errors -o "$ISO" "$ISO_URL"
    [[ -n ${TAM:-} && $(stat -c%s "$ISO") -eq $TAM ]] ||
        erro "a ISO ficou incompleta — corre outra vez, retoma de onde parou"
    touch "$CACHE/build.iso"
fi

# --- 2. desempacotar -----------------------------------------------------------
if [[ ! -f $CACHE/build.rootfs ]]; then
    log "a desempacotar o sistema de ficheiros do Zorin"
    # O caminho do squashfs muda entre versões e entre famílias de instalador
    # (casper no Ubuntu, live no Debian). Procuramos em vez de o adivinhar.
    SFS=$(xorriso -indev "$ISO" -find / -name '*.squashfs' 2>/dev/null |
          grep -oE "'/[^']+'" | tr -d "'" | head -1)
    [[ -n $SFS ]] || erro "não encontrei nenhum .squashfs dentro da ISO"
    etapa "encontrado: $SFS"

    rm -rf "$ARVORE"; mkdir -p "$ARVORE"
    xorriso -osirrox on -indev "$ISO" -extract / "$ARVORE" 2>&1 | tail -1
    cp "$ARVORE/$SFS" "$CACHE/base.squashfs"
    rm -f "$ARVORE/$SFS"
    echo "$SFS" > "$CACHE/caminho-squashfs"

    # A lista dos nós de dispositivo, LIDA DA IMAGEM antes de desempacotar. O
    # unsquashfs vai deitá-los fora sem se queixar; esta lista é o que os traz
    # de volta na fase 5.
    unsquashfs -ll "$CACHE/base.squashfs" 2>/dev/null |
      awk '/^[bc]/ {
             tipo = substr($1,1,1)
             perm = 0
             for (i=2;i<=10;i++) { c=substr($1,i,1); perm = perm*2 + (c!="-") }
             # perm binário → octal, três a três
             o = sprintf("%d%d%d", int(perm/64)%8, int(perm/8)%8, perm%8)
             maior = $3; menor = $4; gsub(/,/,"",maior)
             cam = $NF; sub(/^squashfs-root/,"",cam)
             print cam, tipo, o, 0, 0, maior, menor
           }' > "$CACHE/nos-de-dispositivo"
    etapa "$(wc -l < "$CACHE/nos-de-dispositivo") nós de dispositivo guardados para a remontagem"

    rm -rf "$ROOTFS"
    sem_root "$0" --interno desempacotar 2>&1 | tail -3
    etapa "rootfs: $(du -sh --apparent-size "$ROOTFS" 2>/dev/null | cut -f1)"
    touch "$CACHE/build.rootfs"
fi

# --- 3. os nossos pacotes ------------------------------------------------------
if [[ ! -f $CACHE/build.pacotes ]]; then
    log "a instalar a camada DelonixOS sobre a base do Zorin"
    # shellcheck source=lib-debian.sh
    source "$REPO_DIR/scripts/lib-debian.sh"
    # `remaster`: o bloco do ambiente de trabalho exclui-se sozinho — a base já
    # traz um, e um segundo por cima seriam ~2 GB e dois menus a competir.
    DELONIX_FAMILIA_EXTRA=remaster \
        expandir_pacotes "$PERFIL/Packages" "$ALVO" > "$CACHE/lista-pacotes"
    etapa "$(wc -l < "$CACHE/lista-pacotes") pacotes do apt"

    "$REPO_DIR/scripts/deb-da-casa.sh" "$CACHE/debs" | tail -5

    sem_root "$0" --interno pacotes
    touch "$CACHE/build.pacotes"
fi

# --- 4. a marca ----------------------------------------------------------------
if [[ ! -f $CACHE/build.marca ]]; then
    log "rebranding — sem isto a imagem não é redistribuível"
    sem_root "$0" --interno marca 2>&1 | grep -vE '^\(Reading|^Removing|^\s*$' | tail -6

    # O portão. Não é decoração: uma remasterização com a marca deles dentro é
    # um problema legal, não um defeito estético. Procura-se nos sítios que o
    # utilizador VÊ e que seguem na imagem.
    restos=$(grep -rlisI 'zorin' \
                "$ROOTFS/etc/os-release" "$ROOTFS/usr/lib/os-release" \
                "$ROOTFS/etc/lsb-release" "$ROOTFS/etc/issue" \
                "$ROOTFS/usr/share/applications" 2>/dev/null | head -10 || true)
    if [[ -n $restos ]]; then
        printf '%s\n' "$restos" | sed 's/^/    /'
        erro "ainda há vestígios da marca Zorin — ver acima"
    fi
    etapa "sem vestígios da marca nos caminhos verificados"
    touch "$CACHE/build.marca"
fi

# --- 5. reempacotar ------------------------------------------------------------
log "a reempacotar"
rm -f "$CACHE/novo.squashfs"
sem_root "$0" --interno empacotar 2>&1 | tail -4

SFS=$(cat "$CACHE/caminho-squashfs")
mkdir -p "$(dirname "$ARVORE/$SFS")"
cp "$CACHE/novo.squashfs" "$ARVORE/$SFS"
# O casper lê este ficheiro para mostrar o tamanho na instalação; se mentir, a
# barra de progresso do instalador mente com ele.
du -sx --block-size=1 "$ROOTFS" | cut -f1 > "$ARVORE/${SFS%.squashfs}.size" 2>/dev/null || true

ISO_SAIDA="$SAIDA/delonixos-$(date -u +%Y%m%d)-zorin$VERSAO-x86_64.iso"
log "a montar a ISO"
# `-boot_image any replay` copia a configuração de arranque da ISO original —
# El Torito para BIOS e a partição EFI — em vez de a reconstruir. É o que faz a
# imagem continuar a arrancar nas duas máquinas sem adivinharmos parâmetros.
xorriso -indev "$ISO" -outdev "$ISO_SAIDA" \
        -boot_image any replay \
        -map "$ARVORE/$SFS" "$SFS" \
        -compliance no_emul_toc 2>&1 | tail -3

printf '\n%s✓ %s · %s%s\n\n' "$BLD" "$(basename "$ISO_SAIDA")" \
       "$(du -h "$ISO_SAIDA" | cut -f1)" "$RST"
