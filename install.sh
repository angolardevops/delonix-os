#!/usr/bin/env sh
# Instalador do `delonixos` — a ferramenta que constrói o DelonixOS (ou a tua
# própria distro) a partir de qualquer Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/angolardevops/delonix-os/main/install.sh | sh
#
# Instala em ~/.local/bin por omissão (sem sudo). Para instalar no sistema:
#   curl -fsSL .../install.sh | sudo PREFIX=/usr/local sh
#
# POSIX sh de propósito: tem de correr num Ubuntu mínimo, num Fedora, num
# contentor Alpine — sem assumir bash.
set -eu

REPO_URL="${DELONIXOS_REPO:-https://github.com/angolardevops/delonix-os.git}"
RAW_URL="https://raw.githubusercontent.com/angolardevops/delonix-os/main/cli/delonixos"
PREFIX="${PREFIX:-$HOME/.local}"
SHARE="${DELONIXOS_HOME:-$HOME/.local/share/delonixos/delonix-os}"

red=''; grn=''; ylw=''; bld=''; rst=''
if [ -t 1 ]; then
    red=$(printf '\033[31m'); grn=$(printf '\033[32m'); ylw=$(printf '\033[33m')
    bld=$(printf '\033[1m'); rst=$(printf '\033[0m')
fi
say()  { printf '%s→%s %s\n' "$bld" "$rst" "$1"; }
ok()   { printf '  %s✓%s %s\n' "$grn" "$rst" "$1"; }
warn() { printf '  %s!%s %s\n' "$ylw" "$rst" "$1"; }
die()  { printf '%s✗%s %s\n' "$red" "$rst" "$1" >&2; exit 1; }

# --- pré-requisito mínimo ------------------------------------------------------
command -v python3 >/dev/null 2>&1 || die "preciso do python3 (>= 3.8)"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' ||
    die "preciso do python 3.8 ou mais recente"

# --- o CLI ---------------------------------------------------------------------
say "a instalar o delonixos em $PREFIX/bin"
mkdir -p "$PREFIX/bin"

if [ -f "$(dirname "$0")/cli/delonixos" ]; then
    # A correr de dentro de um clone do repositório.
    cp "$(dirname "$0")/cli/delonixos" "$PREFIX/bin/delonixos"
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_URL" -o "$PREFIX/bin/delonixos"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$PREFIX/bin/delonixos" "$RAW_URL"
else
    die "preciso do curl ou do wget para descarregar o delonixos"
fi
chmod 0755 "$PREFIX/bin/delonixos"
ok "delonixos instalado"

# --- o perfil base -------------------------------------------------------------
# O CLI precisa do repositório para o perfil base e para os scripts de build.
# Sem isto ele clona sozinho na primeira utilização; fazê-lo agora dá um erro
# cedo e claro em vez de uma surpresa a meio.
if [ -d "$SHARE/.git" ]; then
    say "a actualizar o perfil base em $SHARE"
    git -C "$SHARE" pull --ff-only --quiet 2>/dev/null || warn "não consegui actualizar (segue o que já lá está)"
    ok "perfil base actualizado"
elif command -v git >/dev/null 2>&1; then
    say "a obter o perfil base para $SHARE"
    mkdir -p "$(dirname "$SHARE")"
    git clone --depth 1 --quiet "$REPO_URL" "$SHARE" && ok "perfil base obtido"
else
    warn "sem git — o delonixos vai buscá-lo na primeira utilização"
fi

# --- PATH ----------------------------------------------------------------------
case ":$PATH:" in
    *":$PREFIX/bin:"*) ;;
    *)
        warn "$PREFIX/bin não está no PATH. Acrescenta ao teu shell:"
        printf '        export PATH="%s/bin:$PATH"\n' "$PREFIX"
        ;;
esac

printf '\n'
ok "instalado"
printf '
  %sPróximos passos%s

    delonixos doctor                  esta máquina consegue construir?
    delonixos init --distro ubuntu    cria um projecto com inventário
    delonixos build --from ubuntu     constrói a ISO oficial

  Documentação: https://github.com/angolardevops/delonix-os
\n' "$bld" "$rst"
