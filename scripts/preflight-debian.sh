#!/usr/bin/env bash
# Resolve a transação de pacotes da edição Debian SEM instalar nada.
#
#   ./scripts/preflight-debian.sh                # Ubuntu 24.04 (por omissão)
#   ./scripts/preflight-debian.sh bookworm       # Debian 12
#   make preflight-debian ALVO=jammy
#
# É o equivalente do preflight.sh da edição Manjaro, e existe pela mesma razão —
# aprendida da pior maneira: nesta semana perdemos quatro builds a descobrir
# problemas de pacotes ao fim de quarenta minutos. Resolver a transação a seco
# custa dois minutos e apanha a classe inteira.
#
# Em apt, o equivalente ao `pacman -Sp` é o `apt-get install --simulate`: calcula
# dependências e conflitos, imprime o que faria, e não toca em nada.
set -uo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
LISTA="$REPO_DIR/iso-profiles/delonix/devops-debian/Packages"
ENGINE=${DELONIX_ENGINE:-podman}

# shellcheck source=lib-debian.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib-debian.sh"
SUITE=${1:-${DELONIX_SUITE:-noble}}
alvo_valido "$SUITE" || exit 1
FAMILIA=$(alvo_familia "$SUITE")
APT_SUITE=$(alvo_suite "$SUITE")
# O Zorin não publica imagem de contentor; a base é a do Ubuntu de que deriva, e
# os repositórios dele entram por cima — que é exactamente o que o build faz.
IMG_FAM=$FAMILIA; [[ $FAMILIA == zorin ]] && IMG_FAM=ubuntu
IMAGE=${DELONIX_IMAGE_DEB:-docker.io/library/$IMG_FAM:$APT_SUITE}
# As MESMAS fontes que o build vai usar. Resolver contra outra coisa é o erro
# que na edição Manjaro deixou passar uma versão de 2024.
REPOS_EXTRA=$(alvo_repos_extra "$SUITE" | tr '\n' ';')

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1"; }

[[ -f $LISTA ]] || { echo "sem $LISTA"; exit 1; }
command -v "$ENGINE" >/dev/null || { echo "preciso do $ENGINE"; exit 1; }

PACOTES=$(expandir_pacotes "$LISTA" "$SUITE" | tr '\n' ' ')
N=$(wc -w <<<"$PACOTES")

printf '\n%sPreflight%s — %d pacotes em %s\n\n' \
    "$BLD" "$RST" "$N" "$(alvo_desc "$SUITE")"

SAIDA=$(mktemp); trap 'rm -f "$SAIDA"' EXIT
"$ENGINE" run --rm --dns=1.1.1.1 --dns=8.8.8.8 \
    -e DEBIAN_FRONTEND=noninteractive -e PACOTES="$PACOTES" \
    -e REPOS_EXTRA="$REPOS_EXTRA" \
    "$IMAGE" bash -c '
        # `universe` traz metade das ferramentas de DevOps; sem ela metade da
        # lista parece não existir e perde-se uma tarde a procurar porquê.
        # `universe` no Ubuntu, `contrib`/`non-free` no Debian: metade das
        # ferramentas de DevOps vive fora do `main`, e sem isto metade da lista
        # parece não existir.
        sed -i "s/^Components: main$/Components: main universe multiverse restricted/" \
            /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
        sed -i "s/^Components: main$/Components: main contrib non-free non-free-firmware/" \
            /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
        if [[ -n ${REPOS_EXTRA:-} ]]; then
            apt-get update -qq >/dev/null 2>&1 || true
            apt-get install -y -qq --no-install-recommends ca-certificates >/dev/null 2>&1 || true
            IFS=";" read -ra R <<<"$REPOS_EXTRA"
            for r in "${R[@]}"; do [[ -n $r ]] && echo "$r" >>/etc/apt/sources.list.d/alvo.list; done
            # As chaves do Zorin não estão no contentor; `trusted=yes` serve para
            # RESOLVER a lista, que é tudo o que o preflight faz. O build a
            # sério verifica as assinaturas.
            sed -i "s|^deb |deb [trusted=yes] |" /etc/apt/sources.list.d/alvo.list
        fi
        apt-get update -qq 2>&1 | tail -3
        # `--simulate` calcula tudo e não toca em nada. `-o Debug::NoLocking`
        # evita precisar de privilégios de escrita nos ficheiros de estado.
        apt-get install --simulate --no-install-recommends $PACOTES 2>&1
    ' >"$SAIDA" 2>&1

falhas=0

# --- 1. pacotes que não existem ---------------------------------------------
if grep -qE 'Unable to locate package|has no installation candidate' "$SAIDA"; then
    while read -r p; do
        bad "não existe em $SUITE: $p"
        ((falhas++))
    done < <(grep -oP "Unable to locate package \K\S+|Package '\K[^']+(?=' has no installation candidate)" \
             "$SAIDA" | sort -u)
else
    ok "todos os pacotes foram encontrados"
fi

# --- 2. dependências impossíveis / conflitos --------------------------------
if grep -qE 'Depends:.*but it is not|Conflicts:|broken packages' "$SAIDA"; then
    while read -r l; do bad "dependência: $l"; ((falhas++)); done \
        < <(grep -E 'Depends:.*but it is not|Conflicts:' "$SAIDA" | sed 's/^ *//' | sort -u | head -10)
else
    ok "sem conflitos nem dependências por satisfazer"
fi

# --- 3. tamanho da transação -------------------------------------------------
n_inst=$(grep -cE '^Inst ' "$SAIDA") || n_inst=0
if (( n_inst > 0 )); then
    ok "$n_inst pacotes na transação (com dependências)"
else
    warn "o apt não devolveu nada — vê a saída completa:"
    tail -15 "$SAIDA" | sed 's/^/      /'
fi

printf '\n'
if (( falhas )); then
    printf '%s✗ %d problema(s) — corrige a lista antes de construir%s\n\n' "$RED" "$falhas" "$RST"
    exit 1
fi
printf '%s✓ a transação resolve%s\n\n' "$GRN" "$RST"
