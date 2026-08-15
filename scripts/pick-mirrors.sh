#!/usr/bin/env bash
# Escreve um /etc/pacman.d/mirrorlist com mirrors que estão ACTUALIZADOS e que
# esta máquina consegue mesmo alcançar.
#
#   ./scripts/pick-mirrors.sh            # escreve /etc/pacman.d/mirrorlist
#   ./scripts/pick-mirrors.sh --check    # só reporta, não escreve
#   DELONIX_MIRROR=https://... ./scripts/pick-mirrors.sh
#
# PORQUE NÃO O `pacman-mirrors --fasttrack`
#
# Tentámos primeiro o `--fasttrack`, que é a ferramenta oficial. Ele escolhe
# pela API da Manjaro — estado de sincronização e velocidade medida do lado
# deles — e a partir daqui escolheu cinco mirrors em `*.mm.fcix.net` que esta
# rede nem sequer resolve:
#
#   error: failed retrieving file 'core.db' from ohioix.mm.fcix.net:
#          Could not resolve host
#   error: failed to synchronize all databases (invalid url for server)
#
# Ou seja, trocámos um problema (mirror atrasado) por outro (mirror
# inalcançável). As duas perguntas que interessam são estas, e são locais:
#
#   1. este mirror responde-me a mim, daqui?      → o pedido HEAD ou falha
#   2. os dados dele são recentes?                → o cabeçalho Last-Modified
#
# É isso que este script faz. Nada de API, nada de confiar na palavra de
# ninguém: pergunta-se a cada candidato e ordena-se pelo mais recente.
set -uo pipefail

CHECK_ONLY=0
[[ ${1:-} == --check ]] && CHECK_ONLY=1

BRANCH=${DELONIX_BRANCH:-stable}
MAX_DIAS=${DELONIX_MAX_DIAS_MIRROR:-7}
# Só para descartar mirrors praticamente mortos. NÃO é um alvo de qualidade:
# medido a partir desta rede, TODOS os mirrors dão entre 60 e 130 KB/s, por isso
# um limiar alto rejeitaria a lista inteira. A ordenação por débito é que faz o
# trabalho — usa-se o melhor que houver, seja ele qual for.
MIN_KBS=${DELONIX_MIN_KBS:-20}
DESTINO=${DELONIX_MIRRORLIST:-/etc/pacman.d/mirrorlist}

# Escolhidos por cobertura geográfica e por serem mirrors de instituições, que
# são os que costumam manter a sincronização. Não é uma lista fechada: o
# DELONIX_MIRROR passa à frente de tudo.
CANDIDATOS=(
    https://mirror.alpix.eu/manjaro
    https://ftp.gwdg.de/pub/linux/manjaro
    https://mirror.netcologne.de/manjaro
    https://manjaro.ipacct.com/manjaro
    https://mirrors.ft.uam.es/manjaro
    https://ftp.yz.yamagata-u.ac.jp/pub/linux/manjaro
    https://mirror.dogado.de/manjaro
)
[[ -n ${DELONIX_MIRROR:-} ]] && CANDIDATOS=("$DELONIX_MIRROR")

agora=$(date +%s)
declare -a bons=()
declare -a idades=()
declare -a debitos=()

for m in "${CANDIDATOS[@]}"; do
    # `--retry`: um pedido que não responde à primeira não significa mirror mau.
    # Sem isto, um soluço de rede deixava a lista vazia, o script saía com erro,
    # e o mirrorlist ficava o da imagem base — mirrors nos EUA que esta rede nem
    # resolve. O sintoma aparecia lá à frente, no pacman, sem apontar para aqui.
    lm=$(curl -sI --max-time 12 --retry 2 --retry-delay 1 \
              "$m/$BRANCH/extra/x86_64/extra.db" 2>/dev/null |
         grep -i '^last-modified:' | cut -d' ' -f2- | tr -d '\r')
    if [[ -z $lm ]]; then
        printf '  ✗ %-50s sem resposta\n' "$m" >&2
        continue
    fi
    ts=$(date -d "$lm" +%s 2>/dev/null) || { printf '  ✗ %-50s data ilegível\n' "$m" >&2; continue; }
    horas=$(( (agora - ts) / 3600 ))
    if (( horas > MAX_DIAS * 24 )); then
        printf '  ✗ %-50s ATRASADO (%d dias)\n' "$m" "$(( horas / 24 ))" >&2
        continue
    fi
    # Frescura não chega: um mirror pode estar sincronizado e servir a 2 KB/s
    # daqui. O pacman aborta a transação inteira quando um ficheiro fica abaixo
    # de 1 byte/s durante 10 segundos — e foi assim que um build morreu já
    # depois de passar a fase live:
    #
    #   error: failed retrieving file 'systemd-libs-...' : Operation too slow
    #
    # Medimos o débito a sério: descarregamos a core.db (~150 KB) e cronometramos.
    kbs=$(curl -so /dev/null --max-time 25 -w '%{speed_download}' \
              "$m/$BRANCH/core/x86_64/core.db" 2>/dev/null)
    kbs=$(( ${kbs%%.*} / 1024 ))
    if (( kbs < MIN_KBS )); then
        printf '  ✗ %-50s %dh mas só %d KB/s\n' "$m" "$horas" "$kbs" >&2
        continue
    fi
    printf '  ✓ %-50s %dh · %d KB/s\n' "$m" "$horas" "$kbs" >&2
    bons+=("$m")
    idades+=("$horas")
    debitos+=("$kbs")
done

if (( ${#bons[@]} == 0 )); then
    cat >&2 <<'AVISO'

  Nenhum mirror serve: ou não responderam, ou os dados estão atrasados, ou o
  débito está abaixo do mínimo. A linha de cada um, acima, diz qual foi o caso.
  Construir assim dá uma ISO com pacotes antigos e falhas que não apontam para
  a causa — foi o que aconteceu a 2026-08-15 com o manjaro-live-setup.

  Para forçar um mirror específico:
      DELONIX_MIRROR=https://o.teu.mirror/manjaro make iso

AVISO
    exit 1
fi

# Ordenar pelo MAIS RÁPIDO. O pacman usa o primeiro que responder, por isso a
# ordem não é decoração — é a diferença entre descarregar 4 GB e desistir.
# (Todos os que chegam aqui já passaram o filtro de frescura.)
ordem=$(for i in "${!bons[@]}"; do
            printf '%s\t%s\t%s\n' "${debitos[$i]}" "${idades[$i]}" "${bons[$i]}"
        done | sort -rn)

(( CHECK_ONLY )) && { printf '\n%d mirror(s) utilizáveis\n' "${#bons[@]}" >&2; exit 0; }

{
    printf '## DelonixOS — mirrors verificados em %s\n' "$(date -Is)"
    printf '## Escolhidos por RESPONDEREM daqui e por terem dados recentes.\n'
    printf '## Regenera com: scripts/pick-mirrors.sh\n##\n'
    while IFS=$'\t' read -r kbs h m; do
        printf '## %s KB/s · %sh de atraso\nServer = %s/%s/$repo/$arch\n' \
            "$kbs" "$h" "$m" "$BRANCH"
    done <<<"$ordem"
} >"$DESTINO"

printf '  → %s escrito com %d servidor(es)\n' "$DESTINO" "${#bons[@]}" >&2

# O melhor débito disponível dá uma estimativa honesta. Uma ISO destas são
# ~4 GB comprimidos; a ligação é que manda, e mais vale saber-se à partida do
# que descobrir-se às três horas de build.
melhor=$(head -1 <<<"$ordem" | cut -f1)
if (( melhor > 0 )); then
    horas=$(( 4000000 / melhor / 3600 ))
    printf '  ℹ a %d KB/s, descarregar ~4 GB leva cerca de %dh\n' "$melhor" "$horas" >&2
    (( horas >= 4 )) && printf '  ℹ os pacotes ficam em .cache/pkg — uma segunda tentativa reaproveita-os\n' >&2
fi

