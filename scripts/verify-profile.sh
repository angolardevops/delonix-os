#!/usr/bin/env bash
# DelonixOS — validação do perfil antes de gastar 40 minutos num build.
#
#   ./scripts/verify-profile.sh              # verificações locais
#   ./scripts/verify-profile.sh --online     # + confirma que os pacotes existem
#
# Falha (exit 1) se: faltar ficheiro obrigatório, um pacote da blocklist voltar
# às listas, um script não passar no `bash -n`, ou faltar um asset de branding.
set -uo pipefail

# A raiz do repositório: normalmente deduz-se do caminho do script, mas quando
# este corre de uma cópia (build dentro do contentor) tem de vir do ambiente.
REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PROFILE="$REPO_DIR/iso-profiles/delonix/devops"
OVERLAY="$PROFILE/desktop-overlay"
ONLINE=0
[[ ${1:-} == --online ]] && ONLINE=1

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; RST=$'\e[0m'
fails=0
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; ((fails++)); }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1"; }

echo "== ficheiros obrigatórios =="
for f in profile.conf Packages-Root Packages-Desktop Packages-Live Packages-Mhwd; do
    [[ -s $PROFILE/$f ]] && ok "$f" || bad "$f em falta ou vazio"
done

# O branding é gerado para build/ e embrulhado no pacote delonix-os-branding —
# já não é copiado para dentro da imagem (era isso que o impedia de receber
# actualizações depois de instalado).
BRANDING="$REPO_DIR/build/branding"
echo "== branding (payload do delonix-os-branding) =="
if [[ ! -d $BRANDING ]]; then
    bad "build/branding não existe — corre 'make branding'"
fi
for f in \
    usr/share/plymouth/themes/delonix/delonix.plymouth \
    usr/share/plymouth/themes/delonix/delonix.script \
    usr/share/plymouth/themes/delonix/logo.png \
    usr/share/plymouth/themes/delonix/background.png \
    usr/share/sddm/themes/delonix/Main.qml \
    usr/share/sddm/themes/delonix/background.png \
    usr/share/plasma/look-and-feel/org.delonix.desktop/metadata.json \
    usr/share/plasma/look-and-feel/org.delonix.desktop/contents/defaults \
    usr/share/plasma/look-and-feel/org.delonix.desktop/contents/splash/Splash.qml \
    usr/share/color-schemes/DelonixDark.colors \
    usr/share/wallpapers/Delonix/metadata.json \
    usr/share/grub/themes/delonix/theme.txt
do
    [[ -s $BRANDING/$f ]] && ok "${f##*/}" || bad "$f em falta (corre make branding)"
done

wall_count=$(find "$BRANDING/usr/share/wallpapers/Delonix/contents/images" -name '*.png' 2>/dev/null | wc -l)
(( wall_count >= 1 )) && ok "$wall_count wallpapers" || bad "sem wallpapers gerados"

# A animação do splash: o delonix.script tem o número de frames FIXO. Se os
# ficheiros e o script discordarem, o Plymouth aborta e o arranque fica sem
# splash nenhum — daí ser um erro, não um aviso.
ply_dir="$BRANDING/usr/share/plymouth/themes/delonix"
frames=$(find "$ply_dir" -name 'anim-*.png' 2>/dev/null | wc -l)
declared=$(grep -oP '^frame_count = \K[0-9]+' "$ply_dir/delonix.script" 2>/dev/null)
if [[ $frames -eq ${declared:-0} && $frames -gt 0 ]]; then
    ok "animação do splash: $frames frames (igual ao delonix.script)"
else
    bad "frames=$frames mas o script declara ${declared:-?} — corre branding/gen-assets.py"
fi

echo "== pacotes do AUR (têm de ser compilados no build) =="
aur_list=$(grep -oE '^[a-z0-9][a-z0-9._+-]*' "$REPO_DIR/packages/aur.list" | sort -u)
marked=$(grep -hE '^\s*[a-z0-9][a-z0-9._+-]*\s+#.*\[aur\]' "$PROFILE"/Packages-* |
         grep -oE '^\s*[a-z0-9][a-z0-9._+-]*' | tr -d ' ' | sort -u)
orphans=$(comm -23 <(echo "$marked") <(echo "$aur_list"))
if [[ -z $orphans ]]; then
    ok "todos os pacotes marcados [aur] estão em packages/aur.list"
else
    while read -r p; do [[ -n $p ]] && bad "[aur] fora do aur.list: $p (o buildiso não o encontraria)"; done <<<"$orphans"
fi

echo "== blocklist (bloat que não pode voltar) =="
listed=$(grep -hoE '^[a-z0-9][a-z0-9._+-]*' "$PROFILE"/Packages-* | sort -u)
blocked=$(grep -oE '^[a-z0-9][a-z0-9._+-]*' "$REPO_DIR/packages/blocklist.txt" | sort -u)
violations=$(comm -12 <(echo "$listed") <(echo "$blocked"))
if [[ -z $violations ]]; then
    ok "nenhum pacote bloqueado nas listas"
else
    while read -r p; do [[ -n $p ]] && bad "pacote bloqueado presente: $p"; done <<<"$violations"
fi

# As listas Packages-* não são a única porta de entrada. Um pacote da casa que
# declare `depends=('ttf-jetbrains-mono-nerd')` traz de volta, pelo pacman, os
# mesmos 233 MB que tirámos da lista — e nada acima o detecta, porque o nome
# nunca chega a aparecer num Packages-*. Aconteceu a 2026-08-15.
echo "== dependências dos pacotes da casa =="
dep_viol=0
while IFS= read -r -d '' pkgbuild; do
    nome_pkg=$(basename "$(dirname "$pkgbuild")")
    # Extrai depends=(...) e optdepends=(...), tira as descrições depois de ':'
    deps=$(sed -n '/^\(opt\)\?depends=(/,/)/p' "$pkgbuild" |
           grep -oE "'[^']+'" | tr -d "'" | cut -d: -f1 |
           sed 's/[<>=].*//' | sort -u)
    [[ -z $deps ]] && continue
    while read -r d; do
        [[ -z $d ]] && continue
        if grep -qxF "$d" <<<"$blocked"; then
            bad "$nome_pkg depende de '$d', que está na blocklist"
            ((dep_viol++))
        fi
    done <<<"$deps"
done < <(find "$REPO_DIR/packaging" -name PKGBUILD -print0)
(( dep_viol == 0 )) && ok "nenhum pacote da casa reintroduz o que foi removido"

# O `bash -n` NÃO apanha crases dentro de aspas duplas: a substituição de comando
# só é analisada quando corre, por isso o script passa na verificação de sintaxe
# e depois cospe um erro do bash em cima de quem o usa. Foi assim que duas
# mensagens do delonix-doctor iam partir — uma delas só numa sessão Wayland sem
# wl-clipboard, ou seja, no ramo que ninguém testa.
# O instalador não abriu em TRÊS ISOs seguidas, sempre pela mesma razão e nunca
# detectada antes do arranque: o Calamares exige que
#   settings.conf `branding:`  ==  nome da pasta  ==  `componentName:` interno
# e qualquer divergência dá um "Cowardly refusing to continue startup without
# branding" que só se vê a correr o binário à mão no live.
echo "== marca do Calamares (o instalador não abre se isto divergir) =="
LIVE="$PROFILE/live-overlay/usr/share/calamares/branding"
iso_nome=$(grep -oP '^iso_name\s*=\s*"?\K[^"]+' "$PROFILE/profile.conf" 2>/dev/null)
iso_nome=${iso_nome:-delonixos}
comp="$LIVE/$iso_nome"
if [[ ! -f $comp/branding.desc ]]; then
    bad "sem $comp/branding.desc — o Calamares recusa arrancar"
else
    interno=$(grep -oP '^\s*componentName\s*:\s*\K\S+' "$comp/branding.desc")
    if [[ $interno == "$iso_nome" ]]; then
        ok "componente '$iso_nome' com componentName coerente"
    else
        bad "componentName='$interno' mas a pasta é '$iso_nome' — o Calamares recusa"
    fi
    for img in $(grep -oP '^\s+product\w+:\s*"\K[^"]+' "$comp/branding.desc"); do
        [[ -f $comp/$img ]] && ok "  imagem: $img" || bad "  imagem em falta: $img"
    done
fi

echo "== crases dentro de aspas (o bash -n não as vê) =="
crases=0
while IFS= read -r -d '' f; do
    if grep -nE '"[^"]*`[^"]*`[^"]*"' "$f" >/dev/null 2>&1; then
        while IFS= read -r linha; do
            bad "${f#$REPO_DIR/}:$linha"
            ((crases++))
        done < <(grep -nE '"[^"]*`[^"]*`[^"]*"' "$f" | cut -d: -f1)
    fi
done < <(find "$REPO_DIR/packaging" "$REPO_DIR/scripts" -type f \
            \( -name 'delonix-*' -o -name '*.sh' -o -name 'firstboot' \) -print0 2>/dev/null)
(( crases == 0 )) && ok "nenhuma crase acidental em texto"

# O shellcheck vê o que o bash -n não vê. Está na ISO; aqui é opcional para não
# obrigar quem constrói a tê-lo instalado.
if command -v shellcheck >/dev/null; then
    sc=0
    while IFS= read -r -d '' f; do
        shellcheck -S error -f gcc "$f" 2>/dev/null | while read -r l; do
            bad "shellcheck: $l"
        done
        shellcheck -S error "$f" >/dev/null 2>&1 || ((sc++))
    done < <(find "$REPO_DIR/packaging" -name 'delonix-*' -type f -print0 2>/dev/null)
    (( sc == 0 )) && ok "shellcheck sem erros nas ferramentas" || ((fails+=sc))
else
    warn "shellcheck não instalado — 'make lint' corre-o num contentor"
fi

# `((n++))` devolve o valor ANTIGO. Quando esse valor é 0, o estado de saída é
# 1 — e num script com `set -e` isso mata o processo ali mesmo. É invisível ao
# `bash -n`, o shellcheck só o assinala como "info", e custou-nos um build que
# morreu logo a seguir a imprimir que ia começar a trabalhar.
echo "== aritmética que mata scripts com set -e =="
inc=0
while IFS= read -r -d '' f; do
    grep -qE '^set -[a-z]*e' "$f" || continue          # só nos scripts com set -e
    while IFS= read -r linha; do
        bad "${f#$REPO_DIR/}:${linha%%:*} usa (( x++ )) — devolve 0 e mata o set -e"
        ((inc++))
        # `sed 's/#.*//'` primeiro: senão o próprio comentário que explica esta
        # armadilha é apanhado como se fosse a armadilha. Aconteceu.
    done < <(sed 's/#.*//' "$f" | grep -nE '\(\([a-zA-Z_]+(\+\+|--)\)\)')
done < <(find "$REPO_DIR/scripts" "$REPO_DIR/packaging" -type f \
            \( -name '*.sh' -o -name 'delonix-*' -o -name 'firstboot' \) -print0 2>/dev/null)
(( inc == 0 )) && ok "nenhum pós-incremento perigoso"

echo "== sintaxe dos scripts =="
while IFS= read -r -d '' s; do
    if bash -n "$s" 2>/dev/null; then ok "${s#$REPO_DIR/}"; else bad "sintaxe: ${s#$REPO_DIR/}"; fi
done < <(find "$REPO_DIR/scripts" "$OVERLAY/usr/local" -type f \
            \( -name '*.sh' -o -name 'delonix-*' \) -print0 2>/dev/null)

echo "== profile.conf (só chaves que o manjaro-tools lê) =="
for key in displaymanager efi_boot_loader user_shell login_shell; do
    grep -q "^${key}=" "$PROFILE/profile.conf" && ok "$key definido" || bad "$key em falta"
done
# Chaves que não existem no manjaro-tools são ignoradas em silêncio — o erro
# clássico é inventar `plymouth_theme=` e passar a tarde a perguntar porquê.
known='displaymanager|autologin|user_shell|login_shell|multilib|nonfree_mhwd|extra|full_iso'
known+='|efi_boot_loader|custom_boot_args|hostname|username|password|addgroups|netinstall'
known+='|chrootcfg|geoip|office_installer|smb_workgroup|enable_systemd|disable_systemd'
known+='|enable_systemd_timers|enable_systemd_live|disable_systemd_live|snap_channel'
known+='|strict_snaps|classic_snaps|needs_internet|netinstall_label|mhwd_used|oem_used'
known+='|set_oem_user|oem_use_postcfg|no_multilib'
while IFS='=' read -r key _; do
    [[ $key =~ ^[a-z_]+$ ]] || continue
    [[ $key =~ ^($known)$ ]] || bad "chave desconhecida em profile.conf: $key (será ignorada)"
done < <(grep -oE '^[a-z_]+=' "$PROFILE/profile.conf")
ok "chaves do profile.conf verificadas"

grep -q "^KERNEL$" "$PROFILE/Packages-Root" &&
    ok "Packages-Root contém o marcador KERNEL" ||
    bad "Packages-Root sem 'KERNEL' — a ISO sairia sem kernel"
grep -q "custom_boot_args=.*splash" "$PROFILE/profile.conf" &&
    ok "custom_boot_args inclui 'splash' (Plymouth no live)" ||
    bad "sem 'splash' em custom_boot_args — o live arranca sem splash"
for d in root-overlay live-overlay; do
    [[ -d $PROFILE/$d ]] && ok "$d/ existe (exigido pelo check_profile)" ||
        bad "$d/ em falta — o buildiso recusa o perfil"
done

# O `buildiso` copia os overlays com `cp -LR`, que SEGUE os links. Um link para
# uma unidade systemd que não existe na máquina de build mata o build depois de
# 40 minutos — já aconteceu com o podman.socket e o psd.service.
echo "== links simbólicos nos overlays (o buildiso segue-os) =="
links=$(find "$PROFILE"/*-overlay -type l 2>/dev/null)
if [[ -z $links ]]; then
    ok "nenhum link simbólico nos overlays"
else
    while read -r l; do
        [[ -n $l ]] || continue
        if [[ -e $l ]]; then
            warn "link (resolve nesta máquina, pode não resolver na de build): ${l#$PROFILE/}"
        else
            bad "link PENDURADO: ${l#$PROFILE/} → $(readlink "$l")"
        fi
    done <<<"$links"
fi

echo "== coerência (overlay + pacotes) =="
SETTINGS="$REPO_DIR/packaging/delonix-os-settings/payload"
grep -q "Current=delonix" "$SETTINGS/etc/sddm.conf.d/10-delonix.conf" &&
    ok "sddm aponta para o tema delonix" || bad "sddm não aponta para o tema delonix"
grep -q "Theme=delonix" "$OVERLAY/etc/plymouth/plymouthd.conf" &&
    ok "plymouthd aponta para o tema delonix" || bad "plymouthd não aponta para o tema"
grep -q "LookAndFeelPackage=org.delonix.desktop" "$OVERLAY/etc/skel/.config/kdeglobals" &&
    ok "skel usa o tema global Delonix" || bad "skel sem LookAndFeelPackage"
grep -q "plymouth" "$SETTINGS/etc/mkinitcpio.conf.d/delonix.conf" 2>/dev/null &&
    ok "hook plymouth no initramfs" ||
    bad "sem hook plymouth em mkinitcpio.conf.d — o splash não aparece"

echo "== pacotes da casa (é o que permite actualizar depois de instalado) =="
VER=$(tr -d '[:space:]' <"$REPO_DIR/VERSION" 2>/dev/null)
[[ -n $VER ]] && ok "VERSION = $VER" || bad "ficheiro VERSION em falta ou vazio"
for pkg in delonix-os delonix-os-branding delonix-os-settings delonix-os-tools; do
    [[ -s $REPO_DIR/packaging/$pkg/PKGBUILD ]] && ok "PKGBUILD: $pkg" ||
        bad "packaging/$pkg/PKGBUILD em falta"
done
grep -q '^delonix-os\b' "$PROFILE/Packages-Desktop" &&
    ok "a ISO instala o meta-pacote delonix-os" ||
    bad "Packages-Desktop não instala delonix-os — a imagem sairia sem branding"
# O que é gerido por pacote não pode voltar ao overlay: senão o pacman escreve
# .pacnew e o ficheiro do overlay fica congelado para sempre.
dupes=$(find "$OVERLAY/usr/share" -maxdepth 1 \( -name plymouth -o -name sddm -o -name plasma \
        -o -name wallpapers -o -name grub -o -name color-schemes \) 2>/dev/null)
[[ -z $dupes ]] && ok "o overlay não duplica ficheiros dos pacotes" ||
    bad "overlay a duplicar ficheiros de pacote: $dupes"
for h in 95-delonix-plymouth.hook 96-delonix-grub.hook apply-plymouth apply-grub; do
    [[ -s $REPO_DIR/packaging/delonix-os-branding/hooks/$h ]] && ok "gancho: $h" ||
        bad "gancho do pacman em falta: $h"
done

if (( ONLINE )); then
    echo "== pacotes existem na Manjaro (é lá que se constrói) =="
    python3 - "$PROFILE" "$REPO_DIR" <<'PY'
"""
Confirma que cada pacote existe MESMO onde a ISO vai ser construída.

Lição paga com um build: validar contra o archlinux.org não chega. Construímos
contra a Manjaro **stable**, que anda semanas atrás do Arch — o `kind` e o
`intel-npu-driver` existiam no Arch e não na Manjaro, e o buildiso só o disse ao
fim de 40 minutos, com um "target not found".

Por isso a fonte de verdade aqui são as bases de dados da própria Manjaro
(core.db, extra.db, multilib.db), com o AUR como segunda hipótese.
"""
import json, os, re, sys, tarfile, time, urllib.parse, urllib.request
from pathlib import Path

profile = Path(sys.argv[1])
repo_dir = Path(sys.argv[2])
BRANCH = os.environ.get("DELONIX_BRANCH", "stable")
# NUNCA um mirror único e fixo. O que estava aqui antes (mirror.easyname.at)
# ficou um mês atrasado sem avisar, e durante esse mês esta verificação aprovou
# alegremente uma lista de pacotes contra uma fotografia velha do repositório —
# incluindo o `manjaro-live-base` que fez o build falhar a 40 minutos.
#
# Um mirror atrasado é pior do que um mirror em baixo: em baixo dá erro, atrasado
# dá respostas erradas com ar de certas. Daí experimentarmos vários e escolhermos
# pelo `Last-Modified`, não pelo primeiro que responder.
MIRRORS = [os.environ["DELONIX_MIRROR"]] if os.environ.get("DELONIX_MIRROR") else [
    "https://mirror.alpix.eu/manjaro",
    "https://ftp.gwdg.de/pub/linux/manjaro",
    "https://mirror.netcologne.de/manjaro",
    "https://manjaro.ipacct.com/manjaro",
]
CACHE = Path(os.environ.get("DELONIX_CACHE", repo_dir / ".cache")) / "repo-db"
MAX_IDADE = 12 * 3600      # 12 h: as dbs mudam devagar, mas não são eternas
MAX_ATRASO_MIRROR = 7 * 86400   # um mirror com mais de uma semana não serve


def escolher_mirror() -> str:
    """O mirror mais RECENTE dos que respondem, não o primeiro."""
    melhor, melhor_data = None, 0
    for m in MIRRORS:
        try:
            req = urllib.request.Request(f"{m}/{BRANCH}/extra/x86_64/extra.db",
                                         method="HEAD")
            with urllib.request.urlopen(req, timeout=15) as r:
                lm = r.headers.get("Last-Modified")
                if not lm:
                    continue
                ts = time.mktime(time.strptime(lm, "%a, %d %b %Y %H:%M:%S %Z"))
                if ts > melhor_data:
                    melhor, melhor_data = m, ts
        except Exception:
            continue
        if len(MIRRORS) == 1:      # forçado pelo ambiente: não há escolha a fazer
            break
    if melhor is None:
        print("  \033[33m!\033[0m nenhum mirror respondeu — a usar a cache local")
        return MIRRORS[0]
    atraso = time.time() - melhor_data
    if atraso > MAX_ATRASO_MIRROR:
        print(f"  \033[31m✗\033[0m o mirror mais recente tem {atraso/86400:.0f} dias "
              f"de atraso ({melhor})")
        print("      validar contra isto dá aprovações falsas — corrige os mirrors")
    else:
        print(f"  \033[32m✓\033[0m mirror com {atraso/3600:.0f}h: {melhor}")
    return melhor


def manjaro_index() -> set:
    """Nomes de pacote na Manjaro do ramo escolhido (com cache local)."""
    CACHE.mkdir(parents=True, exist_ok=True)
    nomes = set()
    mirror = None
    for repo in ("core", "extra", "multilib"):
        alvo = CACHE / f"{BRANCH}-{repo}.db"
        idade = time.time() - alvo.stat().st_mtime if alvo.exists() else 1e9
        if idade > MAX_IDADE:
            if mirror is None:
                mirror = escolher_mirror()
            url = f"{mirror}/{BRANCH}/{repo}/x86_64/{repo}.db"
            try:
                urllib.request.urlretrieve(url, alvo)
            except Exception as e:
                if not alvo.exists():
                    print(f"  \033[33m!\033[0m não consegui obter {repo}.db ({e})")
                    continue
        try:
            with tarfile.open(alvo) as t:
                for m in t.getmembers():
                    nome = m.name.strip("/")
                    if m.isdir() and "/" not in nome:
                        # <nome>-<versão>-<release>
                        nomes.add(nome.rsplit("-", 2)[0])
                    elif m.isfile() and nome.endswith("/desc"):
                        # O pacman também satisfaz um pedido por `provides` — é
                        # assim que `redis` é servido pelo `valkey`. Sem ler
                        # isto, o verificador reprovava nomes perfeitamente
                        # instaláveis.
                        conteudo = t.extractfile(m).read().decode(errors="replace")
                        bloco = re.search(r"%PROVIDES%\n(.*?)(?:\n\n|\Z)", conteudo, re.S)
                        if bloco:
                            for linha in bloco.group(1).split("\n"):
                                linha = linha.strip()
                                if linha:
                                    nomes.add(re.split(r"[<>=]", linha)[0])
        except Exception as e:
            print(f"  \033[33m!\033[0m {alvo.name} ilegível ({e})")
    return nomes


def aur_existe(nome: str) -> bool:
    q = urllib.parse.quote(nome, safe="")
    for _ in range(3):
        try:
            d = json.load(urllib.request.urlopen(
                f"https://aur.archlinux.org/rpc/?v=5&type=info&arg[]={q}", timeout=20))
            return bool(d["resultcount"])
        except Exception:
            time.sleep(1.2)
    return False


# --- o que as listas pedem ------------------------------------------------------
nossos = {"delonix-os", "delonix-os-branding", "delonix-os-settings", "delonix-os-tools"}
nomes = []
for f in profile.glob("Packages-*"):
    for linha in f.read_text().splitlines():
        linha = linha.split("#")[0].strip()
        if not linha:
            continue
        tok = [t for t in linha.split() if not t.startswith(">")]
        if not tok:
            continue
        nome = tok[-1].split("=")[0]          # aceita fixação de versão
        if nome == "KERNEL" or nome.startswith("KERNEL-"):
            continue                          # marcador substituído no build
        nomes.append(nome)
nomes = sorted(set(nomes) - nossos)

indice = manjaro_index()
if not indice:
    print("  \033[33m!\033[0m sem índice da Manjaro — verificação impossível")
    sys.exit(0)
print(f"  \033[32m✓\033[0m índice Manjaro {BRANCH}: {len(indice)} pacotes")

em_falta, do_aur = [], []
for n in nomes:
    if n in indice:
        continue
    (do_aur if aur_existe(n) else em_falta).append(n)

# --- coerência com o aur.list ---------------------------------------------------
aur_list = {
    l.split("#")[0].strip()
    for l in (repo_dir / "packages/aur.list").read_text().splitlines()
    if l.split("#")[0].strip()
}
orfaos = [p for p in do_aur if p not in aur_list]
if orfaos:
    print(f"  \033[31m✗\033[0m só existem no AUR e faltam em packages/aur.list: {' '.join(orfaos)}")
if em_falta:
    print(f"  \033[31m✗\033[0m {len(em_falta)} pacote(s) que a Manjaro {BRANCH} NÃO tem "
          f"(nem o AUR): {' '.join(em_falta)}")
    print(f"      É este o erro que o buildiso dá como 'target not found', aos 40 minutos.")

if em_falta or orfaos:
    sys.exit(1)
print(f"  \033[32m✓\033[0m {len(nomes)} pacotes existem na Manjaro {BRANCH} "
      f"({len(do_aur)} vêm do AUR, todos declarados)")
PY
    (( $? )) && ((fails++))

    # Os pacotes do AUR são a ÚNICA classe que o preflight não cobre: não vivem
    # em nenhum repositório, são compilados durante o build. Um nome que mudou
    # ou um pacote que foi apagado só dá erro depois de meia hora de compilação.
    # A consulta à API custa um segundo.
    echo "== pacotes do AUR (compilados durante o build) =="
    aur_nomes=$(grep -oE '^[a-z0-9][a-z0-9._+-]*' "$REPO_DIR/packages/aur.list" | sort -u)
    aur_query=$(echo "$aur_nomes" | sed 's/^/\&arg[]=/' | tr -d '\n')
    if aur_json=$(curl -sf --max-time 20 \
            "https://aur.archlinux.org/rpc/?v=5&type=info${aur_query}" 2>/dev/null); then
        AUR_JSON="$aur_json" AUR_NOMES="$aur_nomes" python3 - <<'PY'
import json, os, sys
d = json.loads(os.environ['AUR_JSON'])
achados = {r['Name']: r for r in d.get('results', [])}
pedidos = os.environ['AUR_NOMES'].split()
falta = [p for p in pedidos if p not in achados]
orfaos = [p for p in pedidos if p in achados and not achados[p].get('Maintainer')]
for p in falta:
    print(f"  \033[31m✗\033[0m '{p}' já não existe no AUR — o build ia falhar a compilá-lo")
for p in orfaos:
    print(f"  \033[33m!\033[0m '{p}' está órfão no AUR (sem quem o mantenha)")
if falta:
    sys.exit(1)
print(f"  \033[32m✓\033[0m {len(pedidos)} pacotes do AUR existem"
      + (f" ({len(orfaos)} órfãos)" if orfaos else ""))
PY
        (( $? )) && ((fails++))
    else
        warn "não consegui falar com o AUR — os $(wc -l <<<"$aur_nomes") pacotes ficam por confirmar"
    fi
fi

printf '\n'
if (( fails )); then
    printf '%s✗ %d problema(s)%s\n' "$RED" "$fails" "$RST"; exit 1
fi
printf '%s✓ perfil válido%s\n' "$GRN" "$RST"
