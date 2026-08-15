#!/usr/bin/env python3
"""
Comenta nas listas de pacotes do perfil os pacotes do AUR que não compilaram.

Sem isto, um pacote do AUR que falhe a compilação faz o `buildiso` abortar a
meio (o pacman não encontra o nome) — 20 minutos deitados fora. Assim, a ISO
sai na mesma, sem essa ferramenta, e com um aviso bem visível.

    filter-missing-aur.py <dir-do-perfil> <dir-do-repo-aur>
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def available(repo: Path) -> set[str]:
    """Nomes de pacote presentes no repositório local (pelos ficheiros .pkg)."""
    names = set()
    for f in repo.glob("*.pkg.tar.*"):
        # <nome>-<versão>-<rel>-<arch>.pkg.tar.zst
        m = re.match(r"^(.+?)-[^-]+-[^-]+-[^-]+\.pkg\.tar\..+$", f.name)
        if m:
            names.add(m.group(1))
    return names


def main() -> int:
    profile = Path(sys.argv[1])
    repo = Path(sys.argv[2])

    # Quando isto corre de uma cópia (build no contentor), o caminho do próprio
    # ficheiro já não aponta para o repositório — daí o override por ambiente.
    repo_dir = Path(os.environ.get("DELONIX_REPO_DIR", Path(__file__).resolve().parent.parent))
    wanted_file = repo_dir / "packages/aur.list"
    wanted = [
        line.split("#")[0].strip()
        for line in wanted_file.read_text().splitlines()
        if line.split("#")[0].strip()
    ]

    have = available(repo)
    missing = [p for p in wanted if p not in have]
    if not missing:
        print(f"✓ todos os {len(wanted)} pacotes do AUR estão no repositório local")
        return 0

    print(f"! {len(missing)} pacote(s) do AUR em falta: {' '.join(missing)}")
    changed = 0
    for pkgfile in profile.glob("Packages-*"):
        lines = pkgfile.read_text().splitlines()
        out = []
        for line in lines:
            name = line.split("#")[0].strip().split()
            if name and name[-1] in missing:
                out.append(f"# REMOVIDO-NO-BUILD (AUR falhou): {line}")
                changed += 1
            else:
                out.append(line)
        pkgfile.write_text("\n".join(out) + "\n")

    print(f"! {changed} entrada(s) comentada(s) — a ISO sai sem essas ferramentas")
    print("! instala-as depois com: delonix-toolbox install <perfil>  ou  yay -S <pacote>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
