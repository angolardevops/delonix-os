# DelonixOS

**Uma distribuição Linux para quem opera plataformas.**
DevOps · SRE · Platform Engineering — construída sobre Manjaro KDE Plasma.

🇦🇴 Português de Angola · 🇬🇧 [English](README.md)

---

O objectivo não é a imagem mais pequena. É **abrir o portátil e trabalhar**: sem
instalar toolchains, sem afinar o kernel, sem passar uma tarde a descobrir porque
é que o `cargo build` demora mais a ligar do que a compilar.

```
Manjaro (Arch) ──► base rolling e estável · pacman + AUR
      +
Plasma 6 sem gordura ──► sem PIM, sem office, sem jogos, sem indexação,
                         sem animações (reversível num comando)
      +
kit de plataforma ──► k8s, IaC, rede, segredos, containers rootless,
                     KVM/libvirt/cloud-hypervisor, AWS+GCP, Claude Code
      +
ambiente de dev ──► Rust, Go, Python, Node — configurados, não só instalados
                    PostgreSQL, Redis, MongoDB · Firefox/Chrome/Edge
      +
afinação de fábrica ──► RAM (zram), CPU (tuned), GPU/NPU, I/O (udev),
                       rede (BBR+fq), cgroups, limites
      +
marca Delonix ──► GRUB, Plymouth animado, SDDM, KSplash, tema, wallpapers
```

📖 **[Lista completa de ferramentas, por perfil](docs/pt-AO/ferramentas-por-perfil.md)**
— o que um DevOps, um SRE e um Platform Engineer recebem de origem.

---

## Construir a partir da tua distro

Não precisas de Manjaro para construir o DelonixOS — nem para construir a **tua
própria** distro a partir dele:

```bash
curl -fsSL https://raw.githubusercontent.com/angolardevops/delonix-os/main/install.sh | sh

delonixos doctor                     # esta máquina consegue? comandos exactos do teu gestor de pacotes
delonixos distros                    # o que é suportado, e o que cada omissão resolve
delonixos build --from ubuntu        # última LTS
delonixos build --from ubuntu:22.04  # ou uma específica
```

| Família | Distros | Sem versão |
|---|---|---|
| Só LTS | Ubuntu, **Zorin**, Mint, Pop!_OS | última LTS (24.04) |
| Mais recente | Fedora, Debian, RHEL, Rocky, Alma, openSUSE | a última versão |
| Build nativo | Arch, Manjaro, EndeavourOS | sem contentor |

O Zorin é Ubuntu por baixo — o 18 no 24.04, o 17 no 22.04 — e o `doctor` di-lo.
Uma versão fora de suporte constrói na mesma, mas és avisado.

Ou descreve a tua imagem num inventário e constrói essa:

```bash
delonixos init a-minha-distro --distro ubuntu
cd a-minha-distro && $EDITOR delonixos.yaml   # acrescenta pacotes, fixa versões, tira o que não queres,
                                              # junta binários teus e ficheiros de overlay
delonixos build -f delonixos.yaml
```

O inventário estende o perfil oficial (ou parte do `scratch`), e a ferramenta
traduz isso num perfil manjaro-tools antes de construir — esse perfil traduzido
fica em disco, legível e comparável com `diff`, porque quando um build corre mal
é aí que se olha. Referência completa: **[documentação do CLI](docs/pt-AO/cli.md)**.

---

## Porquê mais uma distro

Toda a gente que opera infraestrutura repete a mesma preparação numa máquina
nova: instalar as toolchains, subir os limites do kernel que rebentam com o
`kubectl logs -f`, e mais tarde descobrir que os containers rootless ignoram em
silêncio os limites de recursos porque os cgroups nunca foram delegados. O
DelonixOS faz esse trabalho uma vez, à vista de todos, com o motivo de cada
decisão escrito.

Três coisas que se recusa a fazer:

- **Nenhum daemon a correr como root para containers.** O motor da casa (Delonix
  Runtime) e o Podman são rootless. O CLI do `docker` está instalado e fala com o
  socket rootless do Podman, por isso a memória muscular continua a servir — mas
  o `dockerd` fica desligado a não ser que o ligues de propósito.
- **Nenhuma decoração que se paga.** Animações do desktop, blur e indexação de
  ficheiros custam GPU, memória e latência. Vêm desligadas e voltam com
  `delonix-toolbox eyecandy on`.
- **Nenhuma afinação deixada para ti.** Escalonador de I/O por tipo de disco, BBR
  com `fq`, limites de inotify, zram, delegação de cgroups, drivers de GPU/NPU —
  tudo aplicado antes do primeiro login.

---

## Afinação que já vem feita

É isto que separa uma distro com pacotes bonitos de uma que trabalha:

- **cgroup v2 delegado** à sessão do utilizador (`Delegate=cpu cpuset io memory pids`).
  Sem isto, os containers rootless ignoram em silêncio os limites de recursos.
- **subuid/subgid** garantidos no primeiro arranque. Sem eles, o rootless morre
  com `newuidmap: uid range not allowed`.
- **inotify** subido para 1M watches. O default do kernel rebenta com três
  `kubectl logs -f` e um IDE abertos.
- **`vm.max_map_count`**, **`nofile=1M`**, **zram com zstd** e **earlyoom** — para
  um cluster local a crescer não custar a sessão.
- **Labs a sério**: KVM aninhado (um hipervisor dentro de uma VM), tabelas de
  vizinhos e de conntrack alargadas (dezenas de VMs mais centenas de containers
  na mesma bridge deixam de dar *neighbour table overflow*), `fs.aio-max-nr` para
  o I/O do QEMU, e o perfil `tuned` **delonix-lab** activo desde o primeiro
  arranque.
- **I/O por tipo de disco** (regras udev): NVMe sem escalonador (o dispositivo
  reordena melhor e gasta menos CPU), SSD em `mq-deadline`, disco rotativo em
  `bfq` — que é o que mantém o desktop utilizável enquanto se copia uma imagem de
  VM de 40 GB.
- **Rede**: BBR **com o qdisc `fq`** (sem ele o BBR perde o *pacing* que o faz
  valer) e buffers TCP subidos.
- **GPU/NPU**: OpenCL e Level Zero em Intel, VA-API para o vídeo ser descodificado
  na GPU em vez da CPU, e o **driver da NPU** dos Core Ultra.
- **Resposta ao utilizador**: o `ananicy-cpp` dá prioridade ao processo em
  primeiro plano, para um `cargo build` a 32 threads não engasgar o browser.

O `delonix-doctor` verifica tudo isto e sai com código diferente de zero se
faltar alguma coisa.

---

## Começar

```bash
delonix-doctor                                  # esta máquina está mesmo pronta?
delonix-toolbox list                            # perfis opcionais
delonix-toolbox db start postgres redis mongo   # as bases de dados vêm paradas
delonix-toolbox eyecandy on                     # queres as animações de volta?
delonix-toolbox lab up observability            # Grafana+Prometheus+Loki, no Delonix Runtime
delonix update                                  # sistema + Delonix Runtime, num comando
```

Referência completa: **[documentação do `delonix-toolbox`](docs/pt-AO/delonix-toolbox.md)**.

---

## Construir a ISO

O `buildiso` (manjaro-tools) só corre em Arch/Manjaro e precisa de root a sério
(chroot, mount, loop, mksquashfs). O `build.sh` trata disso levantando um
contentor Manjaro privilegiado — não é preciso ter Manjaro instalado.

```bash
make iso
```

Requisitos: `podman` (com `sudo`) ou `docker`, ~35 GB livres, 60–120 min.
Num host Arch/Manjaro: `sudo ./scripts/in-container-build.sh`.

Parte desse tempo é o **repositório local do AUR**: o Chrome, o Edge, o MongoDB,
o `gcloud`, o Claude Code e o Antigravity não existem nos repositórios, e o
`pacman` que o `buildiso` usa não sabe o que é o AUR. O build compila-os para um
repositório `[delonix-aur]`. Se algum falhar, a ISO **sai à mesma** sem essa
ferramenta, com aviso — nunca uma hora perdida por causa de um PKGBUILD partido
a montante.

No fim, o build imprime o comando de QEMU para a ISO que acabou de gerar:

```bash
make qemu-cmd     # voltar a imprimi-lo
make test         # ou arrancá-la directamente
```

Antes de gastar uma hora num build:

```bash
make verify       # ficheiros, blocklist, sintaxe, coerência do tema
make check        # + todos os pacotes existem, e não há conflitos declarados
```

O `make check` já apanhou o que costuma partir estes projectos: `khotkeys`
(desapareceu no Plasma 6), `p7zip` (agora `7zip`), `redis` (o Arch passou para
`valkey`), e o `tlp` a declarar conflito com o `tuned` — este último aborta o
build aos 40 minutos.

---

## Actualizações: o que é pacote e o que é imagem

Um ficheiro copiado para dentro da ISO é escrito uma vez e **nunca mais muda** —
quem instalasse a v1.0 ficava com esse tema e essa afinação para sempre. Por isso
tudo o que precisa de evoluir é distribuído como pacote pacman:

| Pacote | Contém |
|---|---|
| `delonix-os-branding` | temas Plymouth/SDDM/GRUB/Plasma, wallpapers |
| `delonix-os-settings` | sysctl, limites, cgroups, KVM, initramfs, tuned |
| `delonix-os-tools` | `delonix-doctor`, `delonix-toolbox` |
| `delonix-os` | meta-pacote — é este que a ISO instala |

No overlay da imagem fica só o que não ganha nada em ser actualizado: o
`/etc/skel` (lido apenas quando se cria um utilizador) e os dois ficheiros que
pertencem a outros pacotes, `/etc/default/grub` e
`/etc/plymouth/plymouthd.conf`. Reclamá-los faria o pacman recusar a instalação;
em vez disso, dois **ganchos do pacman** reaplicam a nossa escolha sempre que o
`grub` ou o `plymouth` são actualizados, sem passar por cima de quem os mudou de
propósito.

---

## Estrutura do repositório

```
delonix-os/
├── iso-profiles/delonix/devops/     perfil manjaro-tools
│   ├── profile.conf                 sessão, serviços, argumentos de arranque
│   ├── Packages-Root                sistema base
│   ├── Packages-Desktop             Plasma mínimo + o kit de plataforma todo
│   ├── Packages-Live                só o ambiente live (Calamares)
│   ├── Packages-Mhwd                drivers
│   ├── desktop-overlay/             /etc/skel + ficheiros de outros pacotes
│   └── live-overlay/                só a sessão live
├── packaging/                       os pacotes da casa (o que se actualiza)
│   ├── delonix-os-branding/         temas + ganchos do pacman
│   ├── delonix-os-settings/         afinação de sistema
│   ├── delonix-os-tools/            delonix-doctor, delonix-toolbox
│   └── delonix-os/                  meta-pacote
├── branding/gen-assets.py           gera todos os PNG da marca (e a animação)
├── packages/
│   ├── blocklist.txt                o que fica de fora, e porquê (aplicado no build)
│   └── aur.list                     o que é compilado durante o build
├── scripts/                         build · verify · qemu · empacotamento
└── docs/                            en/ · pt-AO/
```

---

## Documentação

| Português de Angola | English |
|---|---|
| [Ferramentas por perfil](docs/pt-AO/ferramentas-por-perfil.md) | [Tools by profile](docs/en/tools-by-profile.md) |
| [CLI `delonixos`](docs/pt-AO/cli.md) | [`delonixos` CLI](docs/en/cli.md) |
| [`delonix-toolbox`](docs/pt-AO/delonix-toolbox.md) | [`delonix-toolbox`](docs/en/delonix-toolbox.md) |
| [Decisões de desenho](docs/pt-AO/decisoes.md) | [Design decisions](docs/en/decisions.md) |
| [Validar um build](docs/pt-AO/validacao.md) | [Validating a build](docs/en/validation.md) |
| [Roteiro](docs/pt-AO/roteiro.md) | [Roadmap](docs/en/roadmap.md) |

---

## Estado

Perfil, overlays, marca, empacotamento e ferramentas de build completos e
validados: **392 pacotes** resolvidos contra os repositórios Arch/AUR, sem
conflitos declarados, verificação prévia verde. A primeira ISO está a ser
construída.

Contribuições são bem-vindas — sobretudo relatos de hardware (a NPU aparece? a
virtualização aninhada funciona no teu CPU?) e correcções de empacotamento.

---

## Autor

**Walter Angolar** — DevOps · SRE · Platform Engineering

- LinkedIn: [walter-angolar](https://www.linkedin.com/in/walter-angolar-02a96b24/)
- GitHub: [@angolardevops](https://github.com/angolardevops)

Parte do esforço da plataforma **N'GolaCloud**.

## Licença

GPL-3.0-or-later. Ver [LICENSE](LICENSE).
