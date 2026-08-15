# DelonixOS — o que verificar na primeira ISO


> 🇬🇧 [This page in English](../en/validation.md)

Uma ISO que arranca não é uma ISO que funciona. Esta lista é a diferença entre
as duas. Ordem: falha cedo, falha barato.

## Antes do build

```bash
make verify        # ficheiros, blocklist, sintaxe, coerência do tema
make check         # + todos os pacotes existem nos repos (rede)
```

## No arranque (QEMU: `make test`)

| # | Verificação | Como saber que falhou |
|---|---|---|
| 1 | Menu do GRUB com tema Delonix | fundo preto com texto branco = `theme.txt` não carregou |
| 2 | Splash do Plymouth **animado** (anéis a propagar-se) | logótipo parado = frames em falta; texto de arranque a correr = tema não foi para o initramfs |
| 3 | Nenhuma mensagem de kernel visível | falta `quiet splash` no `GRUB_CMDLINE_LINUX_DEFAULT` |
| 4 | SDDM com o tema Delonix | ecrã do Breeze = erro de QML; ver `journalctl -u sddm` |
| 5 | Login `delonix`/`delonix` entra | — |
| 6 | KSplash com o logótipo | Plasma a arrancar sem splash = `ksplashrc` não aplicado |
| 7 | Desktop escuro, acento vermelho, wallpaper Delonix | tema global não aplicado ao `/etc/skel` |
| 8 | Painel único em baixo com os lançadores certos | `layouts/*.js` do look-and-feel ignorado |

Um detalhe fácil de perder: o Plymouth só aparece se o tema estiver **dentro do
initramfs**. Se falhar, dentro do sistema instalado:

```bash
sudo plymouth-set-default-theme -R delonix
```

## Na sessão live

```bash
delonix-doctor          # tem de sair com 0 (avisos de KVM são normais em VM)
delonix-toolbox list
```

Depois, à mão:

```bash
podman run --rm docker.io/library/alpine echo rootless-ok   # sem sudo
docker ps                                                   # CLI a falar com o podman, sem dockerd
kubectl version --client && helm version && tofu version
aws --version && gcloud version                             # CLIs de cloud
claude --version && antigravity --version                   # ferramentas de IA
ulimit -n                                                   # >= 1048576
sysctl fs.inotify.max_user_watches                          # 1048576
zramctl                                                     # zram0 activo
tmux ls                                                     # a sessão "delonix" existe
```

Virtualização (o ponto mais fácil de sair partido):

```bash
cat /sys/module/kvm_intel/parameters/nested   # Y  (ou kvm_amd)
virsh --connect qemu:///system net-list       # "default" activa
virt-install --version && cloud-hypervisor --version
tuned-adm active                              # delonix-lab
systemctl is-active tuned-ppd                 # seletor de energia do KDE
pacman -Qq tlp power-profiles-daemon 2>&1     # tem de dizer "não encontrado"
```

## Depois de instalar no disco

| # | Verificação | Porque importa |
|---|---|---|
| 1 | `systemctl status delonix-firstboot` = `exited (0)` | é quem cria subuid/subgid |
| 2 | `grep $USER /etc/subuid /etc/subgid` devolve linhas | sem isto não há containers rootless |
| 3 | `cat /sys/fs/cgroup/user.slice/user-$UID.slice/user@$UID.service/cgroup.controllers` inclui `memory pids` | limites de recursos em rootless |
| 4 | `delonix-doctor` verde | resumo de tudo acima |
| 5 | `podman run --memory 256m ...` respeita o limite | prova que a delegação funciona a sério |
| 6 | Reiniciar duas vezes | apanha serviços que só falham no 2.º boot |
| 7 | `pacman -Syu` corre limpo | prova que a base não foi partida pelos overlays |
| 8 | `systemctl is-enabled docker` = `disabled` | o daemon tem de continuar desligado |
| 9 | Criar e arrancar uma VM no `virt-manager` | prova KVM + libvirt + rede default + permissões |
| 10 | Dentro dessa VM: `lscpu \| grep -i hypervisor` e `ls /dev/kvm` | prova que o *nested* funciona mesmo |
| 11 | `pacman -Qo /usr/share/plymouth/themes/delonix/delonix.script` diz `delonix-os-branding` | o tema é gerido por pacote, não ficheiro solto — é isto que o torna actualizável |
| 12 | `pacman -Qo /etc/sysctl.d/99-delonix.conf` diz `delonix-os-settings` | idem para a afinação |
| 13 | `pacman -Q delonix-os` devolve a versão | o meta-pacote está instalado |

### Provar que as actualizações chegam mesmo

Não basta o pacote estar instalado — o que interessa é a v1.0.1 substituir a
v1.0.0 sem partir nada. Numa VM já instalada:

```bash
# no repositório: sobe a versão, reconstrói e publica localmente
echo 1.0.1 > VERSION && make packages

# na VM (com o repo montado ou copiado)
sudo pacman -Syu delonix-os
pacman -Q delonix-os-branding          # tem de dizer 1.0.1
ls /etc/*.pacnew /etc/**/*.pacnew      # só deve aparecer o que EDITASTE à mão
```

O `.pacnew` é o sinal a vigiar: se aparecer para um ficheiro que ninguém editou,
alguma coisa está a escrever por cima do que é do pacote — provavelmente uma
duplicação no overlay.

## Peso (o objectivo declarado)

```bash
ls -lh out/**/*.iso                    # alvo: ISO < 5 GB
# no sistema instalado:
pacman -Q | wc -l                      # alvo: < 1700 pacotes
df -h /                                # alvo: < 18 GB usados após instalar
free -m                                # alvo: < 1,1 GB em idle no desktop
systemd-analyze                        # alvo: < 15 s até ao SDDM (NVMe)
```

Os alvos subiram de propósito quando a distro passou a trazer linguagens, bases
de dados e três browsers. O que **não** pode subir é a memória em repouso: se
passar de ~1,1 GB, alguma coisa arrancou sozinha que não devia — provavelmente
uma base de dados. Confirma com:

```bash
delonix-toolbox db status              # tudo "inactive" num arranque limpo
systemctl list-units --state=running | wc -l
```

E as optimizações que ninguém deve ter de fazer à mão:

```bash
cat /sys/block/nvme0n1/queue/scheduler     # [none]
sysctl net.core.default_qdisc              # fq   (o BBR precisa dele)
clinfo -l                                  # OpenCL vê a GPU
ls /dev/accel/accel0                       # NPU (Core Ultra), se existir
systemctl is-active ananicy-cpp psd        # prioridades e perfis em RAM
kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor  # 0
```

Se algum destes números fugir, o culpado costuma estar em `Packages-Desktop` —
um meta-pacote que arrastou meio KDE. `pacman -Qi <pacote>` e
`pactree -r <pacote>` dizem quem o puxou.
