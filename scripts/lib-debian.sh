#!/usr/bin/env bash
# Funções partilhadas entre o preflight e o build da edição Debian.
#
# A razão de existir: o preflight tem de resolver EXACTAMENTE a lista que o
# build vai instalar. Na edição Manjaro os dois divergiram — o preflight usava
# os mirrors do contentor e o build um `build_mirror` diferente — e isso deixou
# passar uma versão de 2024 que custou três builds. Uma só fonte para as duas.

# --- alvos suportados ----------------------------------------------------------
# suite → família|mirror|descrição. O Zorin não tem repositórios próprios de
# base: é Ubuntu por baixo, e é a suite do Ubuntu que se usa.
declare -A ALVOS=(
    [noble]="ubuntu|http://archive.ubuntu.com/ubuntu|Ubuntu 24.04 LTS (base do Zorin 18)"
    [jammy]="ubuntu|http://archive.ubuntu.com/ubuntu|Ubuntu 22.04 LTS (base do Zorin 17)"
    [bookworm]="debian|http://deb.debian.org/debian|Debian 12"
    [trixie]="debian|http://deb.debian.org/debian|Debian 13"
)

alvo_familia() { cut -d'|' -f1 <<<"${ALVOS[$1]}"; }
alvo_mirror()  { cut -d'|' -f2 <<<"${ALVOS[$1]}"; }
alvo_desc()    { cut -d'|' -f3 <<<"${ALVOS[$1]}"; }

alvo_valido() {
    [[ -n ${ALVOS[$1]:-} ]] && return 0
    {
        printf '\n  alvo desconhecido: %s\n\n  suportados:\n' "$1"
        for s in "${!ALVOS[@]}"; do printf '    %-10s %s\n' "$s" "$(alvo_desc "$s")"; done
    } >&2
    return 1
}

# --- expandir a lista de pacotes para um alvo ----------------------------------
# Sintaxe, igual em espírito à do manjaro-tools:
#
#   ripgrep            entra em todos os alvos
#   >ubuntu eza        só na família Ubuntu
#   >bookworm foo      só nessa suite
#   >!debian bar       em tudo MENOS na família Debian
#
# Porquê: medido, três dos catorze pacotes que testei não existem no Debian 12
# (`eza`, `just`, `docker-compose-v2`). Sem condicionais, ou se perde a
# ferramenta em todos os alvos ou o build parte no alvo onde ela não existe.
expandir_pacotes() {
    local ficheiro=$1 suite=$2 familia
    familia=$(alvo_familia "$suite")

    sed 's/#.*//' "$ficheiro" | while read -r linha; do
        [[ -z ${linha// /} ]] && continue
        local tokens=($linha) nome=""
        case ${tokens[0]} in
            '>'!*)
                # negação: >!debian foo
                local excl=${tokens[0]#>!}
                [[ $excl != "$familia" && $excl != "$suite" ]] && nome=${tokens[1]:-}
                ;;
            '>'*)
                local cond=${tokens[0]#>}
                [[ $cond == "$familia" || $cond == "$suite" ]] && nome=${tokens[1]:-}
                ;;
            *) nome=${tokens[0]} ;;
        esac
        [[ -n $nome ]] && echo "$nome"
    done | sort -u
}
