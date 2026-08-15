#!/usr/bin/env bash
# DelonixOS — imprime o comando QEMU para arrancar a ISO gerada.
#
# Não corre nada: escreve o comando para copiares (o `make test` /
# `scripts/test-vm.sh` é que arranca mesmo). Serve para o fim do build, e para
# quando quiseres o comando à mão.
#
#   ./scripts/qemu-cmd.sh [ficheiro.iso]
#
# Sem argumento, usa a ISO mais recente em ./out.
set -uo pipefail

# A raiz do repositório: normalmente deduz-se do caminho do script, mas quando
# este corre de uma cópia (build dentro do contentor) tem de vir do ambiente.
REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ISO=${1:-}

if [[ -z $ISO ]]; then
    ISO=$(find "$REPO_DIR/out" -name '*.iso' -printf '%T@ %p\n' 2>/dev/null |
          sort -rn | head -1 | cut -d' ' -f2-)
fi

if [[ -z $ISO || ! -f $ISO ]]; then
    echo "sem ISO em $REPO_DIR/out — corre primeiro: make iso" >&2
    exit 1
fi

# Caminho relativo fica mais legível no comando final.
REL=${ISO#"$REPO_DIR"/}
SIZE=$(du -h "$ISO" | cut -f1)

# OVMF: caminho varia entre distros. Damos o que existir nesta máquina, e o
# fallback documentado para as outras.
OVMF=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd \
          /usr/share/OVMF/OVMF_CODE.fd \
          /usr/share/edk2/x64/OVMF_CODE.4m.fd \
          /usr/share/edk2-ovmf/x64/OVMF_CODE.fd 2>/dev/null | head -1)
OVMF=${OVMF:-/usr/share/OVMF/OVMF_CODE_4M.fd}
VARS=${OVMF/CODE/VARS}

cat <<EOF

  ISO: $REL  ($SIZE)

  ── arrancar em UEFI (é assim que o hardware real arranca) ──────────────────

  cp $VARS /tmp/delonix-vars.fd && \\
  qemu-system-x86_64 \\
    -machine q35,accel=kvm -cpu host -smp 4 -m 4096 \\
    -drive if=pflash,format=raw,readonly=on,file=$OVMF \\
    -drive if=pflash,format=raw,file=/tmp/delonix-vars.fd \\
    -device virtio-vga-gl -display gtk,gl=on \\
    -device virtio-net,netdev=n0 -netdev user,id=n0 \\
    -device qemu-xhci -device usb-tablet \\
    -boot d -cdrom $REL \\
    -name "DelonixOS live"

  ── BIOS legada (mais simples, sem OVMF) ────────────────────────────────────

  qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 -m 4096 \\
    -device virtio-vga-gl -display gtk,gl=on -boot d -cdrom $REL

  ── atalho equivalente ──────────────────────────────────────────────────────

  make test

  Nota: sem /dev/kvm acessível, tira \`accel=kvm\` — arranca na mesma, em
  emulação (lento). O splash animado só se vê com a janela gráfica (-display),
  não em -nographic.

EOF
