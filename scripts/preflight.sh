#!/usr/bin/env bash
# Resolve a transação de pacotes SEM instalar nada, num contentor Manjaro.
#
#   ./scripts/preflight.sh            # ~2 minutos
#   make preflight
#
# Porquê: o `make verify --online` confirma que cada pacote EXISTE. Isso não
# chega. O que mata um build de 40 minutos é o pacman a recusar a transação —
# um conflito não declarado, uma dependência impossível, ou um pacote virtual
# com vários fornecedores à espera que alguém escolha.
#
# Isto pede ao próprio pacman para resolver a lista completa (`-Sp`, que calcula
# tudo e não descarrega nada) e mostra exactamente o que ele diria depois de
# meia hora de trabalho.
#
# O que NÃO é verificado aqui: os pacotes que vêm dos repositórios locais
# ([delonix] e [delonix-aur]), porque só existem depois de serem compilados
# durante o build. São listados no fim, para não parecer que foram esquecidos.
set -uo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PROFILE="$REPO_DIR/iso-profiles/delonix/devops"
ENGINE=${DELONIX_ENGINE:-podman}
IMAGE=${DELONIX_IMAGE:-docker.io/manjarolinux/base:latest}
KERNEL=${DELONIX_KERNEL:-linux612}

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1"; }

command -v "$ENGINE" >/dev/null || { echo "preciso do $ENGINE"; exit 1; }

# --- expandir as listas como o manjaro-tools as expande -----------------------
# Replica o `load_pkgs()` do lib/util.sh: substitui KERNEL, resolve os
# condicionais e tira comentários. Se isto divergir do original, o preflight
# testa uma lista que não é a que vai ser instalada — daí estar tão colado.
expandir() {
    local ficheiro=$1 multilib=${2:-true} nonfree=${3:-true} extra=${4:-false}
    sed 's/#.*//' "$ficheiro" | while read -r linha; do
        [[ -z ${linha// /} ]] && continue
        local tokens=($linha)
        local nome=""
        case ${tokens[0]} in
            '>multilib')       $multilib && nome=${tokens[1]} ;;
            '>nonfree_x86_64') $nonfree  && nome=${tokens[1]} ;;
            '>nonfree_multi')  { $nonfree && $multilib; } && nome=${tokens[1]} ;;
            '>extra')          $extra    && nome=${tokens[1]} ;;
            '>office'|'>blacklist'|'>cleanup') ;;              # ignorados
            '>'*)              ;;                              # condicional desconhecido
            *)                 nome=${tokens[0]} ;;
        esac
        [[ -z $nome ]] && continue
        nome=${nome//KERNEL/$KERNEL}
        echo "$nome"
    done
}

LISTA=$(mktemp); LOCAIS=$(mktemp)
trap 'rm -f "$LISTA" "$LOCAIS"' EXIT

for f in Packages-Root Packages-Desktop Packages-Live Packages-Mhwd; do
    [[ -f $PROFILE/$f ]] && expandir "$PROFILE/$f"
done | sort -u >"$LISTA"

# Separar o que vem dos repositórios locais (ainda não existem)
grep -oE '^[a-z0-9][a-z0-9._+-]*' "$REPO_DIR/packages/aur.list" | sort -u >"$LOCAIS"
printf 'delonix-os\ndelonix-os-branding\ndelonix-os-settings\ndelonix-os-tools\n' >>"$LOCAIS"
sort -u -o "$LOCAIS" "$LOCAIS"

REMOTOS=$(comm -23 "$LISTA" "$LOCAIS" | tr '\n' ' ')
N_REMOTOS=$(comm -23 "$LISTA" "$LOCAIS" | wc -l)
N_LOCAIS=$(comm -12 "$LISTA" "$LOCAIS" | wc -l)

printf '\n%sPreflight%s — a resolver %d pacotes com o pacman (sem instalar)\n' \
    "$BLD" "$RST" "$N_REMOTOS"
printf '%s%d vêm dos repositórios locais e só existem durante o build%s\n\n' \
    "$DIM" "$N_LOCAIS" "$RST"

# --- resolver dentro do contentor --------------------------------------------
SAIDA=$(mktemp); trap 'rm -f "$LISTA" "$LOCAIS" "$SAIDA"' EXIT
"$ENGINE" run --rm \
    --dns=1.1.1.1 --dns=8.8.8.8 \
    -e PACOTES="$REMOTOS" \
    "$IMAGE" bash -c '
        set -o pipefail
        pacman-key --init >/dev/null 2>&1
        pacman-key --populate archlinux manjaro >/dev/null 2>&1
        # O build usa `pacman-multilib.conf`; a imagem base não tem multilib
        # ligado. Sem isto o preflight reprova todos os lib32-* — e mandava-nos
        # corrigir uma coisa que não estava partida.
        grep -q "^\[multilib\]" /etc/pacman.conf ||
            printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >>/etc/pacman.conf
        # Os mesmos mirrors que o build vai usar — senão o preflight aprova uma
        # transação que não é a que vai acontecer. Ver in-container-build.sh.
        pacman-mirrors --api --protocol https --set-branch stable >/dev/null 2>&1 || true
        pacman-mirrors --fasttrack 5 >/dev/null 2>&1 || true
        pacman -Syy --noconfirm >/dev/null 2>&1 || { echo "PREFLIGHT-SYNC-FALHOU"; exit 1; }
        idade=$(( ($(date +%s) - $(stat -c %Y /var/lib/pacman/sync/extra.db 2>/dev/null || date +%s)) / 86400 ))
        (( idade > 7 )) && echo "PREFLIGHT-DB-VELHA:$idade"
        # -Sp: resolve tudo (dependências, conflitos, fornecedores) e imprime as
        # URLs em vez de descarregar. É a transação verdadeira, a seco.
        pacman -Sp --needed --noconfirm $PACOTES 2>&1
    ' >"$SAIDA" 2>&1
RC=$?

falhas=0

if grep -q 'PREFLIGHT-SYNC-FALHOU' "$SAIDA"; then
    bad "não consegui sincronizar os repositórios dentro do contentor (rede?)"
    exit 1
fi

# Um mirror atrasado resolve pacotes que já não são os actuais, e o build só
# falha lá à frente com um erro que não aponta para aqui. Aconteceu.
if grep -q 'PREFLIGHT-DB-VELHA' "$SAIDA"; then
    dias=$(grep -oP 'PREFLIGHT-DB-VELHA:\K[0-9]+' "$SAIDA" | head -1)
    bad "as bases de dados têm $dias dias — os mirrors estão atrasados"
    bad "  o build ia instalar versões antigas e falhar de maneiras estranhas"
    exit 1
fi

# --- 1. pacotes que o pacman não encontra ------------------------------------
if grep -qE 'target not found' "$SAIDA"; then
    while read -r p; do
        bad "não existe: $p"
        ((falhas++))
    done < <(grep -oP 'target not found: \K\S+' "$SAIDA" | sort -u)
else
    ok "todos os pacotes foram encontrados"
fi

# --- 2. conflitos ------------------------------------------------------------
if grep -qiE 'are in conflict|unresolvable package conflicts' "$SAIDA"; then
    while read -r l; do
        bad "conflito: $l"
        ((falhas++))
    done < <(grep -iE 'are in conflict' "$SAIDA" | sed 's/^:: //' | sort -u)
else
    ok "sem conflitos"
fi

# --- 3. dependências impossíveis ---------------------------------------------
if grep -qiE 'unable to satisfy dependency|could not satisfy dependencies' "$SAIDA"; then
    while read -r l; do
        bad "dependência: $l"
        ((falhas++))
    done < <(grep -iE 'unable to satisfy dependency' "$SAIDA" | sed 's/^:: //' | sort -u)
else
    ok "todas as dependências resolvem"
fi

# --- 4. escolhas de fornecedor (o build fica à espera de uma tecla) ----------
if grep -q 'providers available' "$SAIDA"; then
    while read -r l; do
        warn "escolha de fornecedor: $l"
        warn "  → declara o que queres na lista, senão o pacman escolhe por ti"
    done < <(grep -oP 'There are \d+ providers available for \K\S+' "$SAIDA" | sort -u)
else
    ok "sem escolhas de fornecedor pendentes"
fi

# --- 5. tamanho estimado -----------------------------------------------------
# `grep -c` devolve 0 e sai com 1 quando não há linhas; o `|| echo 0` juntava
# um segundo valor e a aritmética rebentava.
pacotes_resolvidos=$(grep -cE '^https?://' "$SAIDA" 2>/dev/null) || pacotes_resolvidos=0
if (( pacotes_resolvidos > 0 )); then
    ok "$pacotes_resolvidos pacotes na transação (com dependências)"
else
    warn "o pacman não devolveu URLs — vê a saída completa:"
    tail -20 "$SAIDA" | sed 's/^/      /'
fi

printf '\n'
if (( falhas )); then
    printf '%s✗ %d problema(s) — o buildiso ia falhar com estes%s\n\n' "$RED" "$falhas" "$RST"
    exit 1
fi
printf '%s✓ a transação resolve; o build não vai falhar por causa de pacotes%s\n\n' "$GRN" "$RST"
