#!/usr/bin/env bash
# Sincroniza as bases de dados do pacman, com paciência.
#
# PORQUÊ NÃO CHEGA UM `pacman -Syy`
#
# Dentro do contentor a resolução de DNS é intermitente: o `curl` alcança um
# mirror e, segundos depois, o pacman falha no mesmo com "Could not resolve
# host". E o `-Syy` só devolve êxito se TODOS os repositórios forem obtidos de
# ALGUM servidor — basta o `extra` falhar em todos para a operação inteira
# falhar, mesmo com o `core` já descarregado.
#
# Duas medidas, ambas medidas e não adivinhadas:
#   1. menos descargas em paralelo — dezenas de ligações ao mesmo tempo são o
#      que faz o resolver começar a recusar;
#   2. tentar outra vez. Uma falha de DNS não é um mirror mau.
set -uo pipefail

TENTATIVAS=${DELONIX_SYNC_TENTATIVAS:-4}

# O default são 5 descargas em paralelo, e é aí que o resolver se afoga.
if grep -q '^ParallelDownloads' /etc/pacman.conf 2>/dev/null; then
    sed -i 's/^ParallelDownloads.*/ParallelDownloads = 2/' /etc/pacman.conf
else
    sed -i '/^\[options\]/a ParallelDownloads = 2' /etc/pacman.conf
fi

for (( i=1; i<=TENTATIVAS; i++ )); do
    if pacman -Syy --noconfirm >/tmp/delonix-sync.log 2>&1; then
        printf '  ✓ bases de dados sincronizadas (tentativa %d)\n' "$i" >&2
        exit 0
    fi
    printf '  ! sincronização falhou (tentativa %d/%d)\n' "$i" "$TENTATIVAS" >&2
    grep -oE "Could not resolve host: \S+" /tmp/delonix-sync.log | sort -u |
        sed 's/^/      /' >&2
    sleep $(( i * 3 ))
done

printf '\n  ✗ não consegui sincronizar ao fim de %d tentativas\n' "$TENTATIVAS" >&2
tail -8 /tmp/delonix-sync.log | sed 's/^/      /' >&2
cat >&2 <<'AVISO'

  Se são todos "Could not resolve host", o problema é a resolução de DNS a
  partir do contentor, não os mirrors. O build.sh já passa --dns quando detecta
  um resolver em loopback no host; se o teu DNS for outro, força um mirror:

      DELONIX_MIRROR=https://ftp.gwdg.de/pub/linux/manjaro make iso

AVISO
exit 1
