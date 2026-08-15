#!/usr/bin/env bash
# DelonixOS — arrancar a ISO numa VM para validar o que só se vê a olho:
# splash do Plymouth, tema do GRUB, ecrã do SDDM, tema do Plasma.
#
#   ./scripts/test-vm.sh out/.../delonixos-1.0.iso [--bios]
#
# Por omissão arranca em UEFI (é assim que a maioria do hardware real arranca)
# com 4 GB de RAM e 4 vCPU. Não escreve nada no disco.
set -euo pipefail

ISO=${1:?uso: test-vm.sh <ficheiro.iso> [--bios]}
MODE=${2:-uefi}
RAM=${DELONIX_VM_RAM:-4096}
CPUS=${DELONIX_VM_CPUS:-4}

command -v qemu-system-x86_64 >/dev/null || { echo "instala o qemu primeiro"; exit 1; }

ARGS=(
    -machine q35,accel=kvm:tcg
    -cpu host
    -smp "$CPUS"
    -m "$RAM"
    -device virtio-vga-gl -display gtk,gl=on
    -device virtio-net,netdev=n0 -netdev user,id=n0
    -device qemu-xhci -device usb-tablet
    -audiodev pipewire,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0
    -boot d -cdrom "$ISO"
    -name "DelonixOS live"
)

if [[ $MODE != --bios ]]; then
    # A ordem importa: as variantes 4M são as actuais; as antigas ficam como
    # recurso para distros que ainda as tenham.
    OVMF=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd \
              /usr/share/edk2/x64/OVMF_CODE.4m.fd \
              /usr/share/OVMF/OVMF_CODE.fd \
              /usr/share/edk2-ovmf/x64/OVMF_CODE.fd 2>/dev/null | head -1) || true
    if [[ -n ${OVMF:-} ]]; then
        VARS=$(mktemp /tmp/delonix-ovmf-vars.XXXX.fd)
        cp "${OVMF/CODE/VARS}" "$VARS" 2>/dev/null ||
            cp /usr/share/OVMF/OVMF_VARS.fd "$VARS" 2>/dev/null || true
        ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF")
        [[ -s $VARS ]] && ARGS+=(-drive "if=pflash,format=raw,file=$VARS")
    else
        echo "! OVMF não encontrado — a arrancar em BIOS legada"
    fi
fi

[[ -w /dev/kvm ]] || echo "! sem /dev/kvm — vai correr em emulação (lento)"

echo "→ a arrancar $ISO"
exec qemu-system-x86_64 "${ARGS[@]}"
