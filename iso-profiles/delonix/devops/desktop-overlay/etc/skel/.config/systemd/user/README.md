# Serviços do utilizador pré-activados

`sockets.target.wants/podman.socket` é o equivalente a teres corrido
`systemctl --user enable podman.socket` — é assim que o **CLI do docker**
encontra um backend nesta distro (o `DOCKER_HOST` do `.zshrc` aponta para este
socket) sem existir nenhum daemon a correr como root.

Para desligar: `systemctl --user disable --now podman.socket`.
