#!/usr/bin/env bash
# DelonixOS — construir a ISO.
#
# O manjaro-tools (buildiso) só corre em cima de Arch/Manjaro E precisa de root
# real (chroot, mount, loop, mksquashfs). Este script trata das duas coisas:
# levanta um contentor Manjaro privilegiado e constrói lá dentro.
#
#   ./scripts/build.sh                     # ISO completa
#   ./scripts/build.sh --engine docker     # forçar motor
#   ./scripts/build.sh --shell             # entrar no contentor sem construir
#   ./scripts/build.sh --clean             # deitar fora os chroots e recomeçar
#
# Por omissão os chroots são REAPROVEITADOS entre tentativas: um erro numa lista
# de pacotes deixa de custar quatro horas. Usa `--clean` quando quiseres ter a
# certeza de que nada ficou de uma tentativa anterior.
#   ./scripts/build.sh --kernel linux612   # escolher o kernel
#
# Requisitos no host: podman (root) ou docker, ~25 GB livres, ~30-60 min.
# Se o teu host JÁ é Manjaro/Arch, corre antes:  sudo ./scripts/build-native.sh
set -euo pipefail

# A raiz do repositório: normalmente deduz-se do caminho do script, mas quando
# este corre de uma cópia (build dentro do contentor) tem de vir do ambiente.
REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
OUT_DIR="$REPO_DIR/out"
CACHE_DIR="${DELONIX_CACHE:-$REPO_DIR/.cache}"
IMAGE="docker.io/manjarolinux/base:latest"
KERNEL="linux612"
ENGINE=""
SHELL_ONLY=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --engine)  ENGINE=$2; shift 2 ;;
        --clean)   export DELONIX_CLEAN=1; shift ;;
        --kernel)  KERNEL=$2; shift 2 ;;
        --shell)   SHELL_ONLY=1; shift ;;
        --image)   IMAGE=$2; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

# --- motor de contentores -----------------------------------------------------
if [[ -z $ENGINE ]]; then
    if command -v podman >/dev/null; then ENGINE=podman
    elif command -v docker >/dev/null; then ENGINE=docker
    else echo "preciso de podman ou docker no host" >&2; exit 1; fi
fi

# buildiso precisa de root REAL dentro do contentor (loop devices, mount).
# Com podman isso significa `sudo podman`, não rootless.
RUN=("$ENGINE")
if [[ $ENGINE == podman && $(id -u) -ne 0 ]]; then
    # Falhar AQUI, no primeiro segundo, e não daqui a dois minutos com um erro
    # em bruto do sudo. É o mesmo princípio do preflight: o que vai correr mal
    # descobre-se antes de gastar tempo, não a meio.
    if ! sudo -n true 2>/dev/null; then
        if [[ ! -t 0 ]]; then
            cat >&2 <<'AVISO'

  Este build precisa da tua palavra-passe e não há terminal para a pedir.

  O `buildiso` monta loop devices e cria o squashfs — são privilégios reais,
  não é rootless. Por isso corre `sudo podman`, e o sudo precisa de te
  perguntar.

  Corre isto NUM TERMINAL, à mão:

      make iso

  (Ou, se preferires aquecer o sudo primeiro:  sudo -v && make iso)

AVISO
            exit 1
        fi
        echo "→ buildiso precisa de privilégios reais; o sudo vai pedir a palavra-passe"
    fi
    echo "→ a usar 'sudo podman'"
    RUN=(sudo podman)
fi

# O chroot do buildiso ocupa ~15 GB; guardá-lo fora do contentor torna os
# rebuilds incrementais (e evita encher a storage do podman/docker).
mkdir -p "$OUT_DIR" "$CACHE_DIR"/{pkg,chroots,aur,repo,iso-profiles}

echo "→ a preparar o payload da marca (tema + PNG gerados)"
"$REPO_DIR/scripts/stage-branding.sh" >/dev/null

echo "→ a validar o perfil"
"$REPO_DIR/scripts/verify-profile.sh"

# Copiar os scripts para dentro do contentor antes de correr: um build demora
# dezenas de minutos, e editar o ficheiro no repositório a meio faria o bash
# retomar a leitura no offset errado e executar fragmentos.
BOOTSTRAP='set -e
rm -rf /tmp/delonix-scripts
cp -a /work/scripts /tmp/delonix-scripts
export DELONIX_SCRIPTS=/tmp/delonix-scripts
export DELONIX_REPO_DIR=/work
exec bash /tmp/delonix-scripts/in-container-build.sh --kernel "$1"'
CMD=(bash -c "$BOOTSTRAP" _ "$KERNEL")

# Perfil gerado pelo `delonixos render` a partir de um inventário YAML. Quando
# existe, é ele que entra na imagem em vez do perfil oficial.
OVERRIDE_MOUNT=()
if [[ -n ${DELONIX_PROFILE_OVERRIDE:-} && -d ${DELONIX_PROFILE_OVERRIDE:-} ]]; then
    echo "→ perfil vindo do inventário: $DELONIX_PROFILE_OVERRIDE"
    OVERRIDE_MOUNT=(-v "$DELONIX_PROFILE_OVERRIDE:/profile-override:z"
                    -e DELONIX_PROFILE_OVERRIDE=/profile-override)
fi
(( SHELL_ONLY )) && CMD=(bash)

# Espaço: o chroot + os pacotes + a ISO passam dos 30 GB. Descobrir isso ao
# minuto 35, com "No space left on device", é a pior forma de o descobrir.
LIVRE_GB=$(df -BG --output=avail "$CACHE_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -n ${LIVRE_GB:-} ]] && (( LIVRE_GB < 35 )); then
    echo "⚠ só ${LIVRE_GB} GB livres em $CACHE_DIR — são precisos ~35 GB" >&2
    echo "  (liberta espaço ou aponta DELONIX_CACHE para outro disco)" >&2
    (( LIVRE_GB < 20 )) && exit 1
fi

# DNS: se o host resolve por um resolver em loopback (systemd-resolved, dnsmasq),
# o contentor não lhe chega — a netns dele não tem esse 127.0.0.x. Aprendemos
# isto no test-distros.sh, e vale exactamente o mesmo aqui.
DNS_ARGS=()
if grep -qE '^nameserver\s+127\.' /etc/resolv.conf 2>/dev/null; then
    echo "→ o host usa um resolver em loopback; a dar DNS explícito ao contentor"
    DNS_ARGS=(--dns=1.1.1.1 --dns=8.8.8.8)
fi

echo "→ a construir com $ENGINE (imagem: $IMAGE, kernel: $KERNEL)"
"${RUN[@]}" run --rm -it \
    --privileged \
    "${DNS_ARGS[@]}" \
    --cap-add=SYS_ADMIN,MKNOD \
    --device /dev/fuse \
    --security-opt seccomp=unconfined \
    --security-opt label=disable \
    -v "$REPO_DIR:/work:z" \
    -v "$OUT_DIR:/var/cache/manjaro-tools/iso:z" \
    -v "$CACHE_DIR/pkg:/var/cache/pacman/pkg:z" \
    -v "$CACHE_DIR/chroots:/var/lib/manjaro-tools:z" \
    -v "$CACHE_DIR/aur:/var/cache/delonix-aur:z" \
    -v "$CACHE_DIR/repo:/var/cache/delonix-repo:z" \
    -v "$CACHE_DIR/iso-profiles:/var/cache/delonix-iso-profiles:z" \
    -w /work \
    -e DELONIX_KERNEL="$KERNEL" \
    -e DELONIX_SKIP_AUR="${DELONIX_SKIP_AUR:-0}" \
    -e DELONIX_CLEAN="${DELONIX_CLEAN:-0}" \
    -e DELONIX_MIRROR="${DELONIX_MIRROR:-}" \
    "${OVERRIDE_MOUNT[@]}" \
    "$IMAGE" "${CMD[@]}"
status=$?

# A ISO pertence ao root (saiu de um contentor privilegiado): devolve-a a quem
# lançou o build, senão o `make test` não a consegue ler.
if [[ ${RUN[0]} == sudo ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR" 2>/dev/null || true
fi

(( status == 0 )) || { echo "build falhou (código $status)" >&2; exit $status; }

# E, no fim de tudo, o comando para arrancar a ISO.
"$REPO_DIR/scripts/qemu-cmd.sh" || true
