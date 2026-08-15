# Ferramentas por perfil

O DelonixOS é uma imagem só, não três. Mas os três papéis que serve — **DevOps**,
**SRE** e **Platform Engineering** — pegam em ferramentas diferentes num dia
normal. Esta página agrupa tudo pelo papel que mais a usa, para veres num relance
se a distro cobre o teu trabalho.

Tudo o que está aqui **já vem instalado e configurado**. Nada nesta página exige
um passo extra, a não ser onde estiver dito.

> 🇬🇧 [This page in English](../en/tools-by-profile.md)

---

## Base comum — toda a gente, todos os dias

A camada em que ninguém pensa até faltar.

| Ferramenta | Porque está cá |
|---|---|
| `zsh` + `starship` + `tmux` | Qualquer terminal abre dentro de uma sessão tmux (`delonix`). Um SSH que cai ou uma janela fechada por engano deixam de matar trabalho longo. O prompt mostra o contexto de Kubernetes e avisa a vermelho quando é produção. |
| `kitty` | Terminal com aceleração por GPU, ligaduras, divisões, e um histórico que se manda directamente para o `fzf`. |
| `fzf` `ripgrep` `fd` `bat` `eza` `zoxide` `atuin` | Procura difusa, grep rápido, listagens legíveis, histórico de shell pesquisável entre máquinas. |
| `git` `lazygit` `git-delta` `gh` `glab` `pre-commit` | Git que dá gosto ler e rever. |
| `neovim` | Já configurado: 2 espaços em YAML/HCL, manifestos de Kubernetes detectados pelo caminho, sem gestor de plugins para combater. |
| `jq` `yq` `jless` | Cirurgia em JSON e YAML. |
| `just` | Runner de tarefas por projecto — o Makefile sem as armadilhas dos tabs. |
| `wl-clipboard` / `xclip` | `comando \| wl-copy`. Sem isto não há pipe para a área de transferência no Wayland, que é a sessão por omissão. |
| `gdb` `lldb` `valgrind` `heaptrack` `hyperfine` | Depurar, encontrar a fuga, e provar que ficou mais rápido com estatística em vez de sensação. |
| `protobuf` + `buf` | Definir contratos gRPC, não apenas chamá-los (o `grpcurl` já cá estava). |
| `Claude Code` · `Antigravity` | Assistente de IA no terminal e um IDE pensado para IA. |

---

## Perfil DevOps

A metade de construir e entregar: pipelines, imagens, ambientes.

### Containers — rootless e sem daemon

| Ferramenta | Nota |
|---|---|
| **Delonix Runtime** (`delonix`) | O motor da casa: sem daemon, sem socket de root. O armazenamento fica em `~/.local/share/delonix` por omissão. |
| `podman` `buildah` `skopeo` `crun` | Rede de segurança rootless para imagens OCI de terceiros. |
| **CLI do `docker`** | Instalado, mas o `dockerd` está **desactivado**. O `DOCKER_HOST` aponta ao socket rootless do Podman, já activo no `/etc/skel`, por isso `docker ps`, `docker run` e `docker compose` funcionam sem root e sem daemon. |
| `dive` `lazydocker` `ctop` `crane` `umoci` | Inspeccionar camadas, navegar containers, operar em registos sem descarregar a imagem toda. |

### CI/CD e entrega

`argocd` · `gh` · `glab` · `pre-commit` · `yamllint` · `shellcheck` · `shfmt` ·
`hurl` (testes HTTP versionáveis) · `syft` (SBOM) · `gitleaks` (segredos em
commits) · `trivy` (imagens, ficheiros, IaC) · `cosign` (assinar e verificar).

### Linguagens — configuradas, não só instaladas

Instalar o compilador é metade do trabalho. A outra metade é a configuração que
cada pessoa, de outra forma, redescobre sozinha:

| Linguagem | O que vem | Configuração que já não tens de fazer |
|---|---|---|
| **Rust** | `rust` `rust-analyzer` `clang` `mold` `sccache` `cargo-nextest` `cargo-audit` `cargo-deny` `cargo-watch` `cargo-edit` | O `~/.cargo/config.toml` já usa o linker **mold** e a cache **sccache**. Num projecto grande, ligar deixa de demorar mais do que compilar. Índice esparso ligado. |
| **Go** | `go` `gopls` `delve` `go-tools` `golangci-lint` `goreleaser` | `GOPATH`/`GOBIN` no `PATH` e `GOTOOLCHAIN=auto`, para um projecto que fixa outra versão de Go a ir buscá-la sozinho. |
| **Python** | `python` `uv` `ruff` `mypy` `ipython` `pipx` `poetry` | O `uv` gere interpretadores e ambientes; o `PIP_REQUIRE_VIRTUALENV` trava instalações globais por acidente. |
| **Node** | `nvm` `nodejs` `npm` `pnpm` `typescript` | O `nvm` é o que se usa no dia a dia — carregado de forma preguiçosa e a respeitar o `.nvmrc` ao entrar num projecto. O `nodejs` do sistema é o chão, para uma máquina sem rede ter um Node no primeiro arranque. |

Vem o pacote `rust` e não o `rustup`, de propósito: funciona **sem rede**, no
primeiro arranque. Várias toolchains ficam a um comando —
`delonix-toolbox install lang-rust-multi`.

### Contribuir para o kernel Linux

O conjunto que o `base-devel` não traz e que se descobre um erro obscuro de cada
vez: `bc`, `cpio`, `flex`, `bison`, `elfutils`, `pahole` (BTF), `sparse`,
`cscope`, `b4`, `patchutils`, e os três módulos Perl sem os quais o
`git send-email` falha na autenticação.

E o comando que remove a cerimónia:

```bash
delonix-kernel setup && delonix-kernel config && delonix-kernel build --install
delonix-kernel boot     # arranca o kernel compilado numa VM — sem instalar nada
```

O `install` acrescenta uma entrada **separada** no GRUB: o teu kernel de
trabalho fica intacto, e se o novo não arrancar escolhes o antigo no mesmo menu.
Detalhes em [Contribuir para o kernel](kernel.md).

### Bases de dados — instaladas, paradas

PostgreSQL, Redis (`valkey`) e MongoDB vêm instaladas mas **não arrancam com o
sistema**. Três servidores a dormir custam cerca de 600 MB de RAM que ninguém
pediu.

```bash
delonix-toolbox db start postgres redis mongo   # faz o initdb do Postgres por ti
delonix-toolbox db status
```

Clientes: `psql` `pgcli` `valkey-cli` `mongosh` `mariadb` `sqlite3`.

---

## Perfil SRE

A metade de manter de pé: incidentes, latência, capacidade, recuperação.

### Kit de rede para incidentes

| Ferramenta | A que pergunta responde |
|---|---|
| `mtr` `gping` | Onde está a latência, e está a piorar agora? |
| `tcpdump` `termshark` | O que anda mesmo no fio? |
| `bandwhich` `iftop` `nethogs` `bmon` | Que processo está a comer a ligação? |
| `dog` `bind` (dig) | É problema de DNS? (Costuma ser.) |
| `socat` `websocat` `grpcurl` `xh` `hurl` | Chegar ao endpoint da mesma forma que o cliente chega. |
| `iperf3` `oha` | O caminho é lento, ou o serviço é lento? |
| `conntrack-tools` `nmap` `ethtool` `nftables` | Rastreio de ligações, exposição, estado da placa, firewall. |

### Desempenho e diagnóstico

`perf` · `bpftrace` · `sysstat` (sar, iostat, pidstat) · `btop` · `iotop` ·
`numactl` · `procs` · `dust` · `duf` · `ncdu` · `smartmontools` · `nvme-cli` ·
`lm_sensors` · `nvtop` (GPU) · `intel-gpu-tools`.

### Logs e dados — o trabalho do dia a dia

| Ferramenta | Porque ganha à alternativa óbvia |
|---|---|
| `duckdb` | SQL directamente sobre CSV/JSON/Parquet. Analisas uma exportação de logs sem montar pipeline nenhum. |
| `miller` (`mlr`) | `awk`/`cut`/`sed` que percebe registos CSV, TSV e JSON. |
| `visidata` | Explorar um ficheiro de dados grande no terminal, de forma interactiva. |
| `jless` | Navegar um JSON enorme sem o carregar num editor. |
| `glow` | Ler runbooks e ADRs no terminal. |

### Laboratórios locais — observabilidade sem factura de cloud

Uma workstation de SRE sem observabilidade local é uma coisa estranha. Mas ter o
Prometheus, o Grafana e o Loki como serviços do sistema 24/7 custaria ~800 MB de
RAM para algo que se usa poucas horas por semana. Por isso vêm como
**laboratório**:

```bash
delonix-toolbox lab up observability
#   Grafana:    http://localhost:3000   (já ligado ao Prometheus e ao Loki)
#   Prometheus: http://localhost:9090   (já a recolher métricas desta máquina)
delonix-toolbox lab down observability  # devolve a memória; os dados ficam
```

Corre em **Podman rootless** com `podman kube play` — sem daemon e sem
docker-compose. O `node-exporter` vem com as **métricas de pressão (PSI)**, que
são as que explicam de facto o "está lento". Aponta um job para o teu próprio
`/metrics` e o teu serviço aparece nas mesmas dashboards.

### Gravar e editar — OBS Studio e DaVinci Resolve

Duas ferramentas, escolhidas de propósito. A configuração que se costuma perder
uma tarde a descobrir já vem feita:

| | O que já vem configurado |
|---|---|
| **OBS Studio** *(na ISO)* | perfil e **quatro cenas** — *Ecrã completo*, *Ecrã + câmara* (canto inferior direito, 25%), *Só câmara*, *Pausa*. Gravação 1080p60 **sem reescalar** (texto de terminal ilegível numa gravação é sempre reescalamento), saída em **mkv** para uma gravação interrompida não se perder, e `Ctrl+F9/F10/F11` para iniciar, parar e pausar. |
| **Microfone** | o OBS já traz **RNNoise**, portão de ruído e compressor na fonte de áudio. É o que separa uma aula audível de uma com ventoinha e teclado — e não exige instalar mais nada. |
| **DaVinci Resolve** *(a pedido)* | `delonix-toolbox install davinci` |

**Porque é que o Resolve não vem na ISO**: é proprietário e o instalador está
atrás de um formulário de registo da Blackmagic — não pode ser descarregado por
script. O `delonix-toolbox install davinci` procura o `.zip` em `~/Downloads`,
abre a página se não o encontrar, e faz **todo** o resto: dependências,
compilação do pacote e instalação.

**A armadilha que custa a primeira tarde a toda a gente**: a versão gratuita do
Resolve para Linux **não descodifica H.264/H.265**. Uma gravação do OBS não
aparece na timeline, e o erro não explica porquê. Para isso existe o
`delonix-video`:

```bash
delonix-video info aula.mkv               # avisa se o ficheiro não vai importar
delonix-video para-davinci aula.mkv       # converte para DNxHR — importa direito
delonix-video publicar aula-editada.mov   # comprime para publicar
```

O original nunca é apagado. O DNxHR é maior (~2 GB por 10 min a 1080p), e é esse
o preço de o Resolve gratuito não ler H.264 — não uma escolha nossa.

O Resolve também precisa de GPU com OpenCL/CUDA. Em Intel já está
(`intel-compute-runtime`); com NVIDIA, `delonix-toolbox install gpu-nvidia`.

### Backup e recuperação

| Ferramenta | Papel |
|---|---|
| `restic` | Backups incrementais, cifrados e deduplicados. |
| `rclone` | Mover dados entre S3/GCS/Azure/local com a mesma sintaxe. |
| `snapper` + `snap-pac` | **É tirado um instantâneo antes de cada `pacman -Syu`.** Numa distro rolling, é a diferença entre um susto e um fim-de-semana perdido. Exige raiz em Btrfs. |
| `btrfs-assistant` | Ver e restaurar esses instantâneos com interface. |

### Segredos e cadeia de fornecimento

`age` · `sops` · `step-cli` · `cosign` · `trivy` · `syft` · `gitleaks` ·
`keepassxc` · `openssl` · `gnupg` · `lynis`.

---

## Perfil Platform Engineering

A metade de construir o substrato: clusters, infraestrutura, caminhos dourados.

### Kubernetes

| Ferramenta | Papel |
|---|---|
| `kubectl` `kubectx` `kubens` | O básico, com aliases `k`, `kx`, `kn` e funções de apoio (`ksecret` descodifica um Secret inteiro, `kclean` tira os campos geridos pelo servidor). |
| `k9s` | Interface de terminal para o cluster. |
| `helm` `kustomize` `kubeconform` | Templates, sobreposições, e **validação de manifestos contra o schema antes do apply**. |
| `stern` | Seguir logs de vários pods ao mesmo tempo. |
| `argocd` | CLI de GitOps. |
| `kind` | Cluster local sobre **Podman rootless** (o `KIND_EXPERIMENTAL_PROVIDER=podman` já está exportado). |
| `krew` | Gestor de plugins do kubectl. |
| `cilium-cli` `etcd` (etcdctl) `cfssl` | Operações de CNI, diagnóstico do plano de controlo, certificados. |
| `eksctl` | Ciclo de vida de clusters EKS. |

Mais (`flux`, `kubeseal`, `velero`, `popeye`, `kubent`) com
`delonix-toolbox install k8s-extra`.

### Infraestrutura como código

`opentofu` (o default, não o Terraform — por causa da licença) · `ansible` +
`ansible-lint` · `packer` · `cue` · `yamllint`.

### Virtualização — labs a sério, não brinquedos

| Ferramenta | Nota |
|---|---|
| `KVM` + `libvirt` + `virt-manager` | **A virtualização aninhada está ligada** (`kvm_intel/kvm_amd nested=1`), por isso corre um hipervisor dentro de uma VM. A rede `default` arranca sozinha e o teu utilizador entra nos grupos `kvm` e `libvirt` no primeiro arranque. |
| `qemu-full` `edk2-ovmf` `swtpm` `virtiofsd` | Firmware UEFI, TPM virtual, partilha de ficheiros host↔convidado. |
| `cloud-hypervisor` | VMM leve para microVMs. |
| `libguestfs` `cloud-image-utils` | Inspeccionar imagens de disco; construir ISOs de seed para cloud-init. |

### Cloud

`aws-cli-v2` + `aws-vault` (credenciais fora do disco em claro) · `gcloud` +
plugin de autenticação do GKE. Azure a pedido:
`delonix-toolbox install cloud-azure`.

---

## Aceleração de hardware — ligada, não deixada para trás

Sem esta camada, uma workstation moderna corre com metade do hardware parado:
vídeo descodificado na CPU, sem OpenCL, NPU invisível.

`intel-compute-runtime` (OpenCL + Level Zero) · `intel-media-driver` (VA-API) ·
**`intel-npu-driver`** (NPU dos Core Ultra) · `level-zero-loader` ·
`vulkan-icd-loader` · `clinfo` · `nvtop` · `radeontop`.

O ROCm da AMD e o CUDA da NVIDIA dependem do hardware detectado:
`delonix-toolbox install gpu-amd` / `gpu-nvidia`.

Modelos locais que aproveitam isso: `delonix-toolbox install ai-local` (Ollama).

---

## Perfis opcionais

Tudo o resto está a um comando. O `delonix-toolbox list` mostra o que já está
instalado:

| Perfil | Conteúdo |
|---|---|
| `lang-java` | OpenJDK 21, Maven, Gradle |
| `lang-rust-multi` | rustup, para toolchains por projecto |
| `lang-node-extra` | yarn, deno, bun |
| `lang-python-data` | numpy, pandas, matplotlib, ipython |
| `k8s-extra` | flux, kubeseal, velero, popeye, kubent |
| `cloud-azure` | Azure CLI |
| `gpu-amd` / `gpu-nvidia` | ROCm / CUDA |
| `virt-extra` | firecracker, vagrant, virtctl |
| `ai-local` | Ollama |
| `ide-extra` | VS Code, DBeaver, Postman |
| `observability` | k6, vector, prometheus |
| `printing` | CUPS e drivers (fora da imagem de propósito) |
| `office` | LibreOffice, Thunderbird — para quem precisa mesmo |

---

## O que está deliberadamente fora

| Não incluído | Motivo |
|---|---|
| LibreOffice, Thunderbird, KDE PIM | Isto não é um desktop de escritório. Só o KMail/Akonadi já corre uma base de dados em segundo plano. |
| Indexação `baloo` | A causa número um de I/O fantasma numa máquina com repositórios grandes. |
| Jogos do KDE, leitores de multimédia, k3b, scanners | Sem função numa workstation de engenharia. |
| Stack de impressão | Instala-se a pedido; é uma árvore de dependências grande para uma necessidade rara. |
| `dockerd` | Contraria a regra rootless e sem daemon. O CLI está lá; o daemon fica a um `systemctl enable` consciente. |
| Animações do desktop | GPU, memória e latência gastas em decoração. O `delonix-toolbox eyecandy on` repõe-nas. |

A lista completa, com o motivo de cada remoção, está em
[`packages/blocklist.txt`](../../packages/blocklist.txt) — e o build **falha** se
algum deles voltar.
