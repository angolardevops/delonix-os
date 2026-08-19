#!/usr/bin/env bash
# Constrói os pacotes .deb da casa a partir das MESMAS árvores `payload/` que
# alimentam os PKGBUILD da edição Manjaro.
#
#   ./scripts/deb-da-casa.sh <destino>
#
# PORQUE .deb E NÃO COPIAR OS FICHEIROS PARA DENTRO
#
# Copiar era mais fácil e seria a segunda vez que cometíamos o mesmo erro. Na
# edição Manjaro os quatro pacotes nasceram com `pkgver=1.0.0` fixo, e o efeito
# só se viu meses depois: numa máquina instalada o gestor de pacotes nunca via
# nada mais recente, e a afinação ficava congelada na versão que veio na ISO.
# Ficheiros soltos são o caso extremo disso — não têm sequer versão para
# comparar, e não há caminho nenhum para os actualizar.
#
# A versão vem do git, tal como na outra edição, e cada commit produz uma
# estritamente maior. Ver `docs/pt-AO/revisao-2026-08.md`, bug 1.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DESTINO=${1:?uso: deb-da-casa.sh <destino>}
mkdir -p "$DESTINO"

# 1.0.0.r39.gaa90d23 → 1.0.0+r39.gaa90d23, por convenção do Debian: o `+`
# marca uma revisão local acima de um upstream 1.0.0.
#
# Escrevi aqui, primeiro, que o `.` quebrava a ordenação — que `1.0.0.r5` viria
# depois de `1.0.0.r40`. É falso, e o `dpkg` diz-o:
#
#   dpkg --compare-versions 1.0.0.r5 lt 1.0.0.r40   → verdadeiro
#
# O algoritmo do dpkg parte a versão em troços de letras e de dígitos e compara
# os dígitos COMO NÚMEROS, por isso 5 < 40 tal como se espera. O `+` fica por
# ser a convenção, não por corrigir coisa nenhuma.
N=$(git -C "$REPO_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
G=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo desconhecido)
VERSAO="1.0.0+r$N.g$G"

# Caminhos que só fazem sentido em Arch. Se entrassem num .deb ficariam lá a
# não fazer nada — ou pior, o `apt` reclamaria de um conflito com um pacote
# real que use o mesmo directório.
declare -a SO_ARCH=(
    'usr/share/libalpm'          # ganchos do pacman
    'etc/mkinitcpio.conf.d'      # o Debian usa initramfs-tools/dracut
    'etc/pacman.d'
)

# nome|depende|descrição
declare -a PACOTES=(
  "delonix-os-settings|systemd, tuned|Afinação de sistema do DelonixOS (energia, PSI, cgroups, udev)"
  "delonix-os-branding|plymouth|Identidade visual do DelonixOS (temas, papéis de parede, os-release)"
  "delonix-os-tools|bash, curl|Ferramentas do DelonixOS (delonix-toolbox, doctor, tune, autotune)"
)

BLD=$'\e[1m'; RST=$'\e[0m'
printf '\n%s→ pacotes .deb da casa · versão %s%s\n' "$BLD" "$VERSAO" "$RST"

for entrada in "${PACOTES[@]}"; do
    IFS='|' read -r nome depende descricao <<<"$entrada"
    origem="$REPO_DIR/packaging/$nome/payload"
    [[ -d $origem ]] || { echo "  · $nome: sem payload, saltado"; continue; }

    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
    cp -a "$origem/." "$tmp/"

    removidos=0
    for c in "${SO_ARCH[@]}"; do
        [[ -e $tmp/$c ]] && { rm -rf "${tmp:?}/$c"; removidos=$((removidos + 1)); }
    done

    mkdir -p "$tmp/DEBIAN"
    cat > "$tmp/DEBIAN/control" <<EOF
Package: $nome
Version: $VERSAO
Section: admin
Priority: optional
Architecture: all
Depends: $depende
Maintainer: Walter Angolar <ss.system@kaeso.co>
Description: $descricao
 Parte do DelonixOS — a distribuição de engenharia de plataforma.
 https://github.com/angolardevops/delonix-os
EOF

    # Os ficheiros de configuração entram como `conffiles`: quem editar um
    # deles não o perde na actualização seguinte, e o dpkg pergunta em vez de
    # decidir sozinho. É o comportamento que se espera de /etc.
    ( cd "$tmp" && find etc -type f 2>/dev/null | sed 's|^|/|' ) > "$tmp/DEBIAN/conffiles" || true
    [[ -s $tmp/DEBIAN/conffiles ]] || rm -f "$tmp/DEBIAN/conffiles"

    find "$tmp" -type f -path '*/usr/bin/*' -exec chmod 755 {} +
    find "$tmp" -type f -path '*/usr/lib/delonix/*' -exec chmod 755 {} +

    dpkg-deb --root-owner-group --build "$tmp" "$DESTINO/${nome}_${VERSAO}_all.deb" >/dev/null
    printf '  · %-22s %4s ficheiros%s\n' "$nome" \
        "$(find "$tmp" -type f -not -path '*/DEBIAN/*' | wc -l)" \
        "$( ((removidos)) && echo "  (menos $removidos caminho(s) de Arch)" )"
    rm -rf "$tmp"; trap - RETURN
done

printf '\n  em %s\n' "$DESTINO"
