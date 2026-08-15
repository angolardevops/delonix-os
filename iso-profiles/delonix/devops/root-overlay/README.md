# root-overlay

Sobreposição aplicada ao **rootfs base** (live + instalado). Está vazia de
propósito: tudo o que é nosso vive em `desktop-overlay/`, que é o que segue para
o sistema instalado.

O `check_profile()` do manjaro-tools **exige** que esta directoria exista — se a
apagares, o `buildiso` recusa o perfil com "sanity check failed".
