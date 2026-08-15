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

# `--so-config`: aplicar as opções e sair, sem sincronizar. Serve para voltar a
# correr DEPOIS do manjaro-tools ser instalado — as configurações de pacman dele
# não existem antes disso, e são precisamente as que o buildiso usa para
# instalar dentro dos chroots.
SO_CONFIG=0
[[ ${1:-} == --so-config ]] && SO_CONFIG=1

# Estas duas opções vão para TODAS as configurações de pacman em jogo: a do
# contentor E as do manjaro-tools, que são as que o buildiso usa para instalar
# dentro dos chroots. Mudar só a primeira não chega — foi o erro que já custou
# dois builds noutro sítio deste ficheiro.
CONFS=(/etc/pacman.conf
       /usr/share/manjaro-tools/pacman-default.conf
       /usr/share/manjaro-tools/pacman-multilib.conf)

for conf in "${CONFS[@]}"; do
    [[ -f $conf ]] || continue

    # 1. Menos descargas em paralelo. O default são 5, e dezenas de ligações
    #    simultâneas são o que faz o resolver de DNS começar a recusar.
    if grep -q '^ParallelDownloads' "$conf"; then
        sed -i 's/^ParallelDownloads.*/ParallelDownloads = 2/' "$conf"
    else
        sed -i '/^\[options\]/a ParallelDownloads = 2' "$conf"
    fi

    # 2. Desligar o tempo-limite de descarga. Por omissão o pacman aborta a
    #    TRANSAÇÃO INTEIRA quando um ficheiro fica abaixo de 1 byte/s durante
    #    10 segundos:
    #
    #      error: failed retrieving file 'systemd-libs-261.2-1-x86_64.pkg.tar.zst.sig'
    #             Operation too slow. Less than 1 bytes/sec transferred
    #      error: failed to commit transaction (unexpected error)
    #
    #    Numa ligação a ~120 KB/s com soluços, isso acontece a meio de uma
    #    descarga de milhares de pacotes e deita fora tudo o que já foi feito.
    #    Uma pausa não é uma falha; deixá-lo esperar é o comportamento correcto.
    grep -q '^DisableDownloadTimeout' "$conf" ||
        sed -i '/^\[options\]/a DisableDownloadTimeout' "$conf"
done

(( SO_CONFIG )) && { printf '  ✓ opções de pacman aplicadas\n' >&2; exit 0; }

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
