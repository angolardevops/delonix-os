# Serviços do utilizador

O `podman.socket` (que dá backend ao CLI do `docker`) e o `psd.service` (perfis
dos browsers em RAM) são activados no **primeiro arranque**, pelo
`delonix-firstboot`, e não por links guardados aqui.

Porquê: o `buildiso` copia os overlays com `cp -LR`, que **segue** os links
simbólicos. Um link para `/usr/lib/systemd/user/podman.socket` não resolve na
máquina onde a ISO é construída, e o build morre com um `cannot stat` — depois
de 40 minutos de trabalho.

Para ver ou mexer:

```bash
systemctl --user status podman.socket psd.service
systemctl --user disable --now psd.service     # se não quiseres os perfis em RAM
```
