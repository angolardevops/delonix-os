#!/usr/bin/env bash
# Teste de ponta a ponta do `delonixos`, sem construir ISO nenhuma.
#
# Percorre o caminho que um utilizador percorre — doctor, init, validate,
# render — e verifica o RESULTADO, não só o código de saída: os pacotes
# acrescentados aparecem mesmo no perfil? o removido ficou comentado? o overlay
# do utilizador sobrepôs-se ao do perfil base?
set -uo pipefail

REPO_DIR=${DELONIX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CLI="$REPO_DIR/cli/delonixos"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GRN=$'\e[32m'; RED=$'\e[31m'; RST=$'\e[0m'
fails=0
ok()  { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
bad() { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; ((fails++)); }

export DELONIXOS_HOME="$REPO_DIR"

echo "== sintaxe =="
python3 -m py_compile "$CLI" && ok "compila" || bad "não compila"
rm -rf "$REPO_DIR/cli/__pycache__"

echo "== doctor =="
"$CLI" doctor >/dev/null 2>&1 && ok "doctor sai 0" || bad "doctor falhou"

echo "== init =="
"$CLI" init "$TMP/proj" --distro ubuntu --name distro-teste >/dev/null 2>&1
[[ -f $TMP/proj/delonixos.yaml ]] && ok "inventário criado" || bad "sem inventário"
[[ -d $TMP/proj/overlays ]] && ok "overlays/ criado" || bad "sem overlays/"

echo "== validate =="
(cd "$TMP/proj" && "$CLI" validate >/dev/null 2>&1) &&
    ok "inventário gerado é válido" || bad "inventário gerado não valida"

# inventário partido: tem de FALHAR
sed 's|apiVersion: delonixos/v1|apiVersion: errado/v9|' "$TMP/proj/delonixos.yaml" >"$TMP/mau.yaml"
(cd "$TMP/proj" && "$CLI" validate -f "$TMP/mau.yaml" >/dev/null 2>&1) &&
    bad "aceitou uma apiVersion errada" || ok "recusa apiVersion errada"

echo "== render =="
python3 - "$TMP/proj/delonixos.yaml" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace("    desktop:\n      - jq", "    desktop:\n      - jq\n      - htop")
s = s.replace("    remove: []", "    remove: [firefox]")
p.write_text(s)
PY
printf 'teste\n' >"$TMP/proj/overlays/etc/motd"
(cd "$TMP/proj" && "$CLI" render >/dev/null 2>&1) || bad "render falhou"

PROFILE="$TMP/proj/build/profile/delonix/devops"
grep -qx 'htop' "$PROFILE/Packages-Desktop" && ok "pacote acrescentado está no perfil" ||
    bad "pacote acrescentado não aparece"
grep -q '^# removido por .*: firefox' "$PROFILE/Packages-Desktop" &&
    ok "pacote removido ficou comentado (com o motivo)" || bad "remoção não aplicada"
[[ $(cat "$PROFILE/desktop-overlay/etc/motd") == teste ]] &&
    ok "overlay do utilizador sobrepõe-se ao do perfil base" || bad "overlay não aplicado"
[[ -f $PROFILE/desktop-overlay/etc/skel/.zshrc ]] &&
    ok "perfil base foi herdado" || bad "perfil base não foi copiado"
[[ -L $PROFILE/desktop-overlay/etc/skel/.config/systemd/user/sockets.target.wants/podman.socket ]] &&
    ok "links simbólicos preservados (não seguidos)" || bad "symlink do skel partido"

echo "== leitor YAML de recurso (sem PyYAML) =="
python3 - "$TMP/proj/delonixos.yaml" "$CLI" <<'PY'
import sys, pathlib, importlib.util
from importlib.machinery import SourceFileLoader
class Bloqueio:
    def find_module(self, name, path=None): return self if name == "yaml" else None
    def load_module(self, name): raise ImportError("bloqueado")
sys.meta_path.insert(0, Bloqueio())
loader = SourceFileLoader("dx", sys.argv[2])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("dx", loader))
loader.exec_module(mod)
data = mod.load_yaml(pathlib.Path(sys.argv[1]))
assert data["apiVersion"] == "delonixos/v1", data.get("apiVersion")
assert "htop" in data["spec"]["packages"]["desktop"], data["spec"]["packages"]
assert data["spec"]["overlays"][0]["src"] == "overlays", data["spec"]["overlays"]
PY
(( $? == 0 )) && ok "lê o inventário sem PyYAML" || bad "leitor de recurso falhou"

printf '\n'
(( fails )) && { printf '%s✗ %d teste(s) falharam%s\n' "$RED" "$fails" "$RST"; exit 1; }
printf '%s✓ CLI ok%s\n' "$GRN" "$RST"
