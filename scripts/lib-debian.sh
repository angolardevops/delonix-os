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
# ZORIN: o que MEDI, e não o que eu esperava encontrar.
#
# Os repositórios do Zorin existem e respondem 200 — `stable`, `patches`, `apps`
# — e eu já ia dar por assente que davam a base. O índice de pacotes está VAZIO:
#
#   .../stable/dists/noble/main/binary-amd64/Packages   0 bytes
#   SHA256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
#           (é o SHA256 do ficheiro vazio)
#
# O mesmo em `jammy`, ou seja no Zorin 17. Os pacotes próprios do Zorin vêm
# DENTRO da ISO deles, não de um repositório público.
#
# Consequência honesta: `make iso zorinos` constrói sobre **Ubuntu 24.04**, que
# é a base real do Zorin 18, com os repositórios dele configurados para quando
# passarem a publicar. Não é o mesmo que a ISO do Zorin, e não vale a pena
# fingir que é. Se o que se quer é a aparência do Zorin, isso é uma escolha de
# tema — e essa está ao nosso alcance.
declare -A ALVOS=(
    [zorin18]="zorin|http://archive.ubuntu.com/ubuntu|Zorin OS 18 (Ubuntu 24.04 + repos Zorin)"
    [zorin17]="zorin|http://archive.ubuntu.com/ubuntu|Zorin OS 17 (Ubuntu 22.04 + repos Zorin)"
    [noble]="ubuntu|http://archive.ubuntu.com/ubuntu|Ubuntu 24.04 LTS (base do Zorin 18)"
    [jammy]="ubuntu|http://archive.ubuntu.com/ubuntu|Ubuntu 22.04 LTS (base do Zorin 17)"
    [bookworm]="debian|http://deb.debian.org/debian|Debian 12"
    [trixie]="debian|http://deb.debian.org/debian|Debian 13"
)

alvo_familia() { cut -d'|' -f1 <<<"${ALVOS[$1]}"; }

# A suite APT por trás de cada alvo. O Zorin não tem suite própria: usa a do
# Ubuntu de que deriva, e acrescenta-lhe os seus repositórios.
alvo_suite() {
    case $1 in
        zorin18) echo noble ;;
        zorin17) echo jammy ;;
        *)       echo "$1" ;;
    esac
}

# Repositórios ADICIONAIS do alvo, um por linha, no formato do mmdebstrap.
alvo_repos_extra() {
    local suite; suite=$(alvo_suite "$1")
    case $1 in
        zorin*)
            printf 'deb http://packages.zorinos.com/stable %s main\n' "$suite"
            printf 'deb http://packages.zorinos.com/patches %s main\n' "$suite"
            printf 'deb http://packages.zorinos.com/apps %s main\n' "$suite"
            ;;
    esac
}
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
    # `>ubuntu` também vale para o Zorin: é Ubuntu por baixo, e escrever a mesma
    # condição duas vezes na lista seria só ruído.
    [[ $familia == zorin ]] && familia="ubuntu zorin"

    sed 's/#.*//' "$ficheiro" | while read -r linha; do
        [[ -z ${linha// /} ]] && continue
        local tokens=($linha) nome=""
        case ${tokens[0]} in
            '>'!*)
                # negação: >!debian foo
                local excl=${tokens[0]#>!}
                [[ " $familia " != *" $excl "* && $excl != "$suite" ]] && nome=${tokens[1]:-}
                ;;
            '>'*)
                local cond=${tokens[0]#>}
                [[ " $familia " == *" $cond "* || $cond == "$suite" ]] && nome=${tokens[1]:-}
                ;;
            *) nome=${tokens[0]} ;;
        esac
        [[ -n $nome ]] && echo "$nome"
    done | sort -u
}
