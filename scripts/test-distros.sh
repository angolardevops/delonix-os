#!/usr/bin/env bash
# Prova que o `delonixos` funciona nas distros que diz suportar.
#
# Corre o caminho completo (doctor → init → validate → render) DENTRO de um
# contentor de cada distro. Não é uma afirmação no README: é o comando a
# correr num Ubuntu 22.04 a sério, num Fedora a sério.
#
#   ./scripts/test-distros.sh                 # o conjunto por omissão
#   ./scripts/test-distros.sh ubuntu:22.04 fedora:43
#   ./scripts/test-distros.sh --all
#
# O que NÃO é testado aqui: o build da ISO em si. Isso precisa de root, de loop
# devices e de 35 GB — e é o mesmo contentor Manjaro em todos os hosts, por
# isso o que varia entre distros é exactamente o que este teste cobre.
set -uo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CLI="$REPO_DIR/cli/delonixos"
ENGINE=${DELONIX_ENGINE:-podman}

GRN=$'\e[32m'; RED=$'\e[31m'; YLW=$'\e[33m'; BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'

# Distro → imagem + como lá pôr o python3. As imagens base não o trazem todas.
declare -A IMAGEM=(
    [ubuntu:24.04]="docker.io/library/ubuntu:24.04"
    [ubuntu:22.04]="docker.io/library/ubuntu:22.04"
    [debian:12]="docker.io/library/debian:12"
    [debian:13]="docker.io/library/debian:13"
    [fedora:43]="registry.fedoraproject.org/fedora:43"
    [fedora:42]="registry.fedoraproject.org/fedora:42"
    [arch:latest]="docker.io/library/archlinux:latest"
    [manjaro:latest]="docker.io/manjarolinux/base:latest"
    [opensuse-tumbleweed:latest]="registry.opensuse.org/opensuse/tumbleweed:latest"
    # O Zorin não publica imagem oficial; é Ubuntu por baixo, e é essa base que
    # o `delonixos` usa. Testamos a base e dizemos que foi isso que testámos.
    [zorin:18]="docker.io/library/ubuntu:24.04"
    [zorin:17]="docker.io/library/ubuntu:22.04"
)
# `ForceIPv4`: dentro do contentor rootless o DNS devolve AAAA mas não há rota
# IPv6 — o apt resolve e depois fica pendurado. Custou meia hora a perceber.
declare -A PREPARAR=(
    # `python3-minimal` + `--no-install-recommends`: ~4 MB em vez de ~25 MB. Numa
    # ligação lenta é a diferença entre o teste correr e o teste expirar — e o
    # CLI só precisa do interpretador da biblioteca padrão.
    [debian]="apt-get -o Acquire::ForceIPv4=true update -qq >/dev/null 2>&1 &&
              apt-get -o Acquire::ForceIPv4=true install -y -qq --no-install-recommends \
                  python3 >/dev/null 2>&1"
    [fedora]="command -v python3 >/dev/null ||
              dnf install -y -q --setopt=ip_resolve=4 python3 >/dev/null 2>&1"
    [arch]="command -v python3 >/dev/null ||
            pacman -Sy --noconfirm --quiet python >/dev/null 2>&1"
    [suse]="command -v python3 >/dev/null || zypper -q install -y python3 >/dev/null 2>&1"
)

familia() {
    case ${1%%:*} in
        ubuntu|debian|zorin|linuxmint|pop) echo debian ;;
        fedora|rhel|rocky|almalinux)       echo fedora ;;
        arch|manjaro|endeavouros)          echo arch ;;
        opensuse*)                         echo suse ;;
        *)                                 echo debian ;;
    esac
}

ALVOS=("ubuntu:24.04" "ubuntu:22.04" "debian:12" "fedora:43" "arch:latest" "zorin:18")
if [[ ${1:-} == --all ]]; then
    ALVOS=("${!IMAGEM[@]}")
elif (( $# )); then
    ALVOS=("$@")
fi

command -v "$ENGINE" >/dev/null || { echo "preciso do $ENGINE"; exit 1; }

printf '\n%sA testar o delonixos em %d distro(s)%s\n' "$BLD" "${#ALVOS[@]}" "$RST"
printf '%s(cada uma: doctor → init → validate → render, dentro do contentor)%s\n\n' "$DIM" "$RST"

falhas=0
declare -A RESULTADO
for alvo in "${ALVOS[@]}"; do
    imagem=${IMAGEM[$alvo]:-}
    if [[ -z $imagem ]]; then
        printf '  %s?%s %-28s sem imagem conhecida\n' "$YLW" "$RST" "$alvo"
        continue
    fi
    fam=$(familia "$alvo")
    printf '  %s…%s %-28s ' "$DIM" "$RST" "$alvo"

    # `--dns`: o host resolve por systemd-resolved em 127.0.0.53, que a netns
    # do contentor não alcança. Sem isto, nenhuma distro instala nada.
    # Uma segunda tentativa: o `apt`/`dnf` falha por rede com frequência
    # suficiente para um único ensaio dar falsos negativos. Duas seguidas já
    # querem dizer alguma coisa.
    saida=""
    for tentativa in 1 2; do
    saida=$("$ENGINE" run --rm \
        --dns=1.1.1.1 --dns=8.8.8.8 \
        -v "$REPO_DIR:/repo:ro,z" \
        -e "DELONIXOS_HOME=/repo" \
        -e "ALVO=$alvo" \
        "$imagem" \
        sh -c "${PREPARAR[$fam]:-true}
               command -v python3 >/dev/null || { echo 'REDE'; exit 1; }
               cp /repo/cli/delonixos /tmp/delonixos && chmod +x /tmp/delonixos
               mkdir -p /tmp/proj && cd /tmp/proj
               /tmp/delonixos doctor --distro \"\$ALVO\" >/tmp/doctor.log 2>&1
               /tmp/delonixos init . --distro \"\${ALVO%%:*}\" --name teste --force >/dev/null 2>&1 || { echo 'INIT-FALHOU'; exit 1; }
               /tmp/delonixos validate >/dev/null 2>&1 || { echo 'VALIDATE-FALHOU'; exit 1; }
               /tmp/delonixos render  >/dev/null 2>&1 || { echo 'RENDER-FALHOU'; exit 1; }
               test -f build/profile/delonix/devops/Packages-Desktop || { echo 'SEM-PERFIL'; exit 1; }
               grep -q 'python' /tmp/doctor.log && echo OK || echo 'DOCTOR-ESTRANHO'
              " 2>&1 | tail -1)
        [[ $saida == OK ]] && break
        [[ $saida == REDE ]] || break     # falha real: não vale a pena repetir
    done

    case $saida in
        OK) printf '%s✓%s\n' "$GRN" "$RST"; RESULTADO[$alvo]=ok ;;
        REDE)
            # Não é uma falha do delonixos: é o mirror desta distro a não
            # responder a partir desta máquina. Dizê-lo como falha do produto
            # seria mentir sobre o que foi testado.
            printf '%s!%s  rede: não consegui instalar o python3 (mirror lento/inacessível)\n' "$YLW" "$RST"
            RESULTADO[$alvo]="não verificado (rede)" ;;
        *)  printf '%s✗%s  %s\n' "$RED" "$RST" "$saida"
            RESULTADO[$alvo]=falhou; ((falhas++)) ;;
    esac
done

printf '\n%sResumo%s\n' "$BLD" "$RST"
for alvo in "${ALVOS[@]}"; do
    printf '  %-28s %s\n' "$alvo" "${RESULTADO[$alvo]:-não testado}"
done

nao_verificadas=0
for alvo in "${ALVOS[@]}"; do
    [[ ${RESULTADO[$alvo]:-} == "não verificado (rede)" ]] && ((nao_verificadas++))
done

printf '\n'
if (( falhas )); then
    printf '%s✗ %d distro(s) falharam%s\n' "$RED" "$falhas" "$RST"
    exit 1
fi
if (( nao_verificadas )); then
    printf '%s✓%s as distros testadas passaram; %s%d não deram para verificar daqui (rede)%s\n' \
        "$GRN" "$RST" "$YLW" "$nao_verificadas" "$RST"
    exit 0
fi
printf '%s✓ o delonixos corre em todas as distros testadas%s\n' "$GRN" "$RST"
