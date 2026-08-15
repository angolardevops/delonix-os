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
    echo "== pacotes existem nos repos (Arch/AUR) =="
    python3 - "$PROFILE" "$REPO_DIR" <<'PY'
import json, re, sys, time, urllib.parse, urllib.request
from pathlib import Path

profile = Path(sys.argv[1])
# Vem do shell: dentro de um heredoc o `__file__` é "<stdin>", por isso não dá
# para derivar a raiz do repositório a partir do próprio ficheiro.
repo_dir = Path(sys.argv[2])
# Pacotes que SÓ existem nos repos da Manjaro — não estão no Arch nem no AUR.
manjaro_only = {
    "manjaro-system", "manjaro-release", "manjaro-keyring", "manjaro-hotfixes",
    "mhwd", "mhwd-db", "mhwd-nvidia", "manjaro-settings-manager",
    "manjaro-kde-settings", "manjaro-browser-settings", "manjaro-printer",
    "manjaro-live-systemd", "manjaro-live-skel", "manjaro-rescue",
    "grub-theme-live-manjaro", "pamac-cli", "mkinitcpio-openswap",
    "install-grub", "update-grub", "udev-usb-sync", "manjaro-alsa",
    # Existem nos repos da Manjaro mas já não no Arch (o `shared/Packages-Root`
    # oficial da Manjaro usa-os na mesma).
    "calamares", "vi",
}
# Os nossos: vivem no repositório local [delonix], construído no build.
manjaro_only |= {"delonix-os", "delonix-os-branding", "delonix-os-settings",
                 "delonix-os-tools"}
names = []
for f in profile.glob("Packages-*"):
    for line in f.read_text().splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        # tokens condicionais do manjaro-tools: >extra, >multilib, >nonfree_*
        name = [t for t in line.split() if not t.startswith(">")][-1:]
        if not name:
            continue
        name = name[0]
        # KERNEL é um marcador substituído no build (KERNEL, KERNEL-nvidia, …)
        if name == "KERNEL" or name.startswith("KERNEL-"):
            continue
        names.append(name)
names = sorted(set(names) - manjaro_only)

def fetch(url):
    """Devolve (dados, erro). Distinguir erro de rede de "não existe" é o que
    evita falsos positivos: 3 timeouts seguidos não significam pacote inválido."""
    last = None
    for _ in range(3):
        try:
            return json.load(urllib.request.urlopen(url, timeout=20)), None
        except Exception as e:          # noqa: BLE001 — queremos o motivo
            last = e
            time.sleep(1.5)
    return None, last


missing, flaky, from_aur = [], [], []
declared_conflicts = {}
for n in names:
    q = urllib.parse.quote(n, safe="")   # nomes com '+' (memtest86+) partem sem isto
    d, err = fetch(f"https://archlinux.org/packages/search/json/?name={q}")
    hits = [r for r in (d or {}).get("results", []) if r["arch"] in ("x86_64", "any")]
    if hits:
        # Guardamos os conflitos declarados: é o que apanha um `tlp` vs `tuned`
        # ANTES de gastar uma hora de build a descobri-lo.
        if hits[0].get("conflicts"):
            declared_conflicts[n] = hits[0]["conflicts"]
        continue
    arch_err = err
    d, err = fetch(f"https://aur.archlinux.org/rpc/?v=5&type=info&arg[]={q}")
    if d and d["resultcount"]:
        from_aur.append(n)
        continue
    if arch_err or err:
        flaky.append(n)                  # rede falhou: não acusamos o pacote
    else:
        missing.append(n)
    time.sleep(0.15)

# Um pacote que só existe no AUR TEM de estar em packages/aur.list, senão o
# buildiso não o encontra (o pacman não fala com o AUR).
aur_list = {
    line.split("#")[0].strip()
    for line in (repo_dir / "packages/aur.list").read_text().splitlines()
    if line.split("#")[0].strip()
}
orphans = [p for p in from_aur if p not in aur_list]
if orphans:
    print(f"  \033[31m✗\033[0m só existem no AUR e faltam em packages/aur.list: {' '.join(orphans)}")

if flaky:
    print(f"  \033[33m!\033[0m não deu para confirmar (rede): {' '.join(flaky)}")

# --- conflitos entre pacotes da nossa própria lista ---------------------------
# Um conflito SEM versão é fatal: o pacman recusa a transação e o build morre a
# meio do make_image_desktop(). Com versão (ex.: `mkinitcpio<38`) é histórico —
# refere-se a versões antigas que já não existem nos repositórios.
name_set = set(names)
clashes = []
for pkg, conflicts in declared_conflicts.items():
    for c in conflicts:
        bare = re.split(r"[<>=]", c)[0].strip()
        if bare == pkg or bare not in name_set:
            continue
        if re.search(r"[<>=]", c):
            continue                       # conflito versionado: histórico
        clashes.append((pkg, bare))
if clashes:
    for a, b in clashes:
        print(f"  \033[31m✗\033[0m conflito declarado: {a} não pode coexistir com {b}")
else:
    print(f"  \033[32m✓\033[0m sem conflitos declarados entre os pacotes da lista")

if missing or orphans or clashes:
    if missing:
        print(f"  \033[31m✗\033[0m {len(missing)} pacote(s) sem correspondência: {' '.join(missing)}")
    sys.exit(1)
print(f"  \033[32m✓\033[0m {len(names) - len(flaky)} pacotes resolvidos "
      f"({len(from_aur)} do AUR, todos declarados em aur.list)")
PY
    (( $? )) && ((fails++))
fi

printf '\n'
if (( fails )); then
    printf '%s✗ %d problema(s)%s\n' "$RED" "$fails" "$RST"; exit 1
fi
printf '%s✓ perfil válido%s\n' "$GRN" "$RST"
