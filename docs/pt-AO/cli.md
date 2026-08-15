# `delonixos` — construir a partir da tua distro

Não precisas de correr Manjaro para construir o DelonixOS. A ISO é sempre
produzida pelo `buildiso`, que precisa de um ambiente Arch/Manjaro — mas esse
ambiente vive num contentor, e o `delonixos` trata disso por ti.

> 🇬🇧 [This page in English](../en/cli.md)

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/angolardevops/delonix-os/main/install.sh | sh
```

Instala em `~/.local/bin` (sem sudo). Para instalar no sistema:
`curl … | sudo PREFIX=/usr/local sh`.

O único requisito rígido é **Python 3.8+**. O PyYAML é usado quando existe;
quando não existe, um leitor interno trata do formato do inventário.

## As três coisas que faz

### 1. Dizer-te se esta máquina consegue construir

```bash
delonixos doctor
```

Detecta a tua distro pelo `/etc/os-release` e dá-te o **comando exacto** do teu
gestor de pacotes, em vez de um genérico "instala o podman":

| Host | O que precisa | Constrói nativamente? |
|---|---|---|
| Ubuntu · Debian · Mint · Zorin · Pop | `sudo apt-get install -y podman uidmap slirp4netns python3` | não — contentor |
| Fedora · RHEL · Rocky · Alma | `sudo dnf install -y podman python3` | não — contentor |
| openSUSE | `sudo zypper install -y podman python3` | não — contentor |
| Arch · Manjaro · EndeavourOS | `sudo pacman -S --needed manjaro-tools-iso git rsync python python-pillow` | **sim** |

Verifica também disco (35 GB), RAM, número de CPUs e se tens root a sério — o
`buildiso` precisa dele para montar loop devices, e descobrir isso ao minuto 40
sai caro.

### 2. Construir a ISO oficial

```bash
delonixos build --from ubuntu       # ou fedora, debian, arch, manjaro…
```

Sem `--from`, o host é detectado. O `--from` existe para quando sabes melhor do
que a detecção, ou quando queres que o comando num script seja explícito.

### 3. Construir a *tua* distro a partir de um inventário

```bash
delonixos init a-minha-distro --distro ubuntu
cd a-minha-distro
$EDITOR delonixos.yaml
delonixos validate
delonixos build -f delonixos.yaml
```

O `init` cria um projecto:

```
a-minha-distro/
├── delonixos.yaml       o teu inventário — a fonte de verdade
├── overlays/            ficheiros copiados para a imagem (overlays/etc → /etc)
└── binaries/            binários locais a incluir
```

## O inventário

```yaml
apiVersion: delonixos/v1
kind: Distro

metadata:
  name: a-minha-distro
  version: 1.0.0
  codename: Acacia

spec:
  extends: delonix/devops      # ou `scratch` para partir do mínimo
  host:
    distro: ubuntu             # onde TU constróis; não muda a ISO

  base:
    kernel: linux612
    branch: stable             # stable | testing | unstable
    compression: zstd

  packages:
    desktop:                   # acrescentados ao perfil base
      - jq
      - kubectl=1.31.4-1       # fixar versão — lê o aviso abaixo
    root: []
    aur:                       # compilados durante o build (mais lento)
      - lazygit-git
    remove:                    # pacotes do perfil base que não queres
      - firefox

  binaries:
    - name: aminhaferramenta
      url: https://exemplo.com/aminhaferramenta
      dest: /usr/local/bin/aminhaferramenta
      mode: "0755"
      sha256: ""               # opcional, recomendado
    # - path: binaries/x       # ou um ficheiro local em vez de um URL

  overlays:
    - src: overlays            # relativo a este ficheiro
      dest: /

  services:
    enable: [o-meu-agente.service]
    disable: [bluetooth]

  users:
    live:
      name: a-minha-distro
      password: a-minha-distro
      groups: [wheel, video, audio, network, kvm, libvirt]
```

### Sobre fixar versões

`packages.desktop: [kubectl=1.31.4-1]` funciona, mas com um limite que vale a
pena perceber: **o pacman só instala uma versão que exista no repositório
configurado**. O Arch e a Manjaro não guardam um arquivo de todas as versões
passadas como é costume nos repositórios apt. Ou seja, fixar uma versão é na
prática "falha se não for esta a versão actual" — útil como guarda, mas não é uma
máquina do tempo.

Para builds verdadeiramente reprodutíveis, fixa o *repositório* e não o pacote:
usa um snapshot do Arch Linux Archive como mirror. Está no roteiro como suporte
de primeira classe; hoje faz-se editando o mirror dentro do contentor de build.

### `extends`

| Valor | Significado |
|---|---|
| `delonix/devops` | o perfil oficial — tudo o que está em [ferramentas por perfil](ferramentas-por-perfil.md), mais as tuas entradas |
| `scratch` | o mínimo que arranca; a lista é toda tua |

## O que acontece num build

```
delonixos build -f delonixos.yaml
        │
        ├── valida o inventário                     (segundos)
        ├── traduz para um perfil manjaro-tools     (build/profile/)
        │     └── perfil base + os teus pacotes − removidos + os teus overlays
        ├── levanta um contentor Manjaro privilegiado
        │     ├── compila os pacotes do AUR para um repositório local
        │     ├── compila os pacotes delonix-os-*
        │     └── buildiso
        └── imprime o comando de QEMU para a ISO gerada
```

O perfil traduzido fica em disco (`build/profile/`) de propósito — é legível,
dá para fazer `diff`, e é exactamente o que o `buildiso` consumiu. Quando algo
corre mal, é aí que se olha.

## Comandos

| Comando | O que faz |
|---|---|
| `delonixos doctor` | pré-requisitos deste host |
| `delonixos init [caminho]` | cria um projecto com inventário |
| `delonixos validate -f f.yaml` | valida o inventário sem construir |
| `delonixos render -f f.yaml` | inventário → perfil manjaro-tools, sem construir |
| `delonixos build [--from d] [-f f.yaml]` | constrói a ISO |

Opções úteis: `--kernel linux612`, `--engine podman\|docker`, `--dry-run`,
`-o <dir>` para o perfil traduzido.

## Variáveis de ambiente

| Variável | Para quê |
|---|---|
| `DELONIXOS_HOME` | caminho do repositório delonix-os (senão é clonado para `~/.local/share/delonixos`) |
| `DELONIX_SKIP_AUR=1` | saltar a compilação do AUR — muito mais rápido, ISO sem essas ferramentas |
| `DELONIX_CACHE` | onde ficam os pacotes e chroots em cache entre builds |
