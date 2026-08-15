# Tools by profile

DelonixOS ships one image, not three. But the three roles it serves — **DevOps**,
**SRE** and **Platform Engineering** — reach for different tools on a normal day.
This page groups everything by the role that uses it most, so you can tell at a
glance whether the distro covers your work.

Every tool listed here is **already installed and configured**. Nothing on this
page requires an extra step, unless it says so.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/ferramentas-por-perfil.md)

---

## Shared foundation — everyone, every day

The layer nobody thinks about until it's missing.

| Tool | Why it's here |
|---|---|
| `zsh` + `starship` + `tmux` | Every terminal opens inside a tmux session (`delonix`). A dropped SSH or a closed window stops killing long-running work. The prompt shows the Kubernetes context and warns in red on production. |
| `kitty` | GPU-accelerated terminal, ligatures, splits, and a scrollback you can pipe into `fzf`. |
| `fzf` `ripgrep` `fd` `bat` `eza` `zoxide` `atuin` | Fuzzy find, fast grep, readable listings, searchable shell history across machines. |
| `git` `lazygit` `git-delta` `gh` `glab` `difftastic` `pre-commit` | Git that is actually pleasant to read and review. |
| `neovim` | Pre-configured: 2-space indent for YAML/HCL, Kubernetes manifests detected by path, no plugin manager to fight. |
| `jq` `yq` `jless` | JSON and YAML surgery. |
| `just` | Per-project task runner — a Makefile without the tab traps. |
| `wl-clipboard` / `xclip` | `command \| wl-copy`. Without it there is no pipe to the clipboard on Wayland, which is the default session. |
| `gdb` `lldb` `valgrind` `heaptrack` `hyperfine` | Debug it, find the leak, and prove it got faster with statistics instead of a feeling. |
| `protobuf` + `buf` | Define gRPC contracts, not just call them (`grpcurl` was already here). |
| `Claude Code` · `Antigravity` | AI assistant in the terminal and an AI-first IDE. |

---

## DevOps profile

The build-and-ship half of the job: pipelines, images, environments.

### Containers — rootless and daemonless

| Tool | Note |
|---|---|
| **Delonix Runtime** (`delonix`) | The house engine: no daemon, no root socket. Storage defaults to `~/.local/share/delonix`. |
| `podman` `buildah` `skopeo` `crun` | Rootless fallback for third-party OCI images. |
| **`docker` CLI** | Installed, but `dockerd` is **disabled**. `DOCKER_HOST` points at the rootless Podman socket, already enabled in `/etc/skel`, so `docker ps`, `docker run` and `docker compose` work without root and without a daemon. |
| `dive` `lazydocker` `ctop` `crane` `umoci` | Inspect layers, browse containers, operate on registries without pulling whole images. |

### CI/CD and delivery

`argocd` · `gh` · `glab` · `pre-commit` · `yamllint` · `shellcheck` · `shfmt` ·
`hurl` (versionable HTTP tests) · `syft` (SBOM) · `gitleaks` (secrets in commits)
· `trivy` (images, filesystems, IaC) · `cosign` (signing and verification).

### Languages — configured, not just installed

Installing a compiler is half the job. The other half is the configuration each
person otherwise rediscovers alone:

| Language | What ships | Configuration you don't have to do |
|---|---|---|
| **Rust** | `rust` `rust-analyzer` `clang` `mold` `sccache` `cargo-nextest` `cargo-audit` `cargo-deny` `cargo-watch` `cargo-edit` | `~/.cargo/config.toml` already uses the **mold** linker and **sccache**. On a large project, linking stops taking longer than compiling. Sparse registry index enabled. |
| **Go** | `go` `gopls` `delve` `go-tools` `golangci-lint` `goreleaser` | `GOPATH`/`GOBIN` on `PATH`, `GOTOOLCHAIN=auto` so a project that pins another Go version just fetches it. |
| **Python** | `python` `uv` `ruff` `mypy` `ipython` `pipx` `poetry` | `uv` manages interpreters and environments; `PIP_REQUIRE_VIRTUALENV` blocks accidental global installs. |
| **Node** | `nvm` `nodejs` `npm` `pnpm` `typescript` | `nvm` is what you use day to day — lazily loaded and honouring `.nvmrc` when you enter a project. The system `nodejs` is the floor, so a machine with no network still has a Node on first boot. |

The `rust` package ships instead of `rustup` on purpose: it works **offline**, on
first boot. Multiple toolchains are one command away —
`delonix-toolbox install lang-rust-multi`.

### Databases — installed, stopped

PostgreSQL, Redis (`valkey`) and MongoDB are installed but **do not start on
boot**. Three sleeping servers cost roughly 600 MB of RAM nobody asked for.

```bash
delonix-toolbox db start postgres redis mongo   # runs the Postgres initdb for you
delonix-toolbox db status
```

Clients: `psql` `pgcli` `valkey-cli` `mongosh` `mariadb` `sqlite3`.

---

## SRE profile

The keep-it-running half: incidents, latency, capacity, recovery.

### Incident network toolkit

| Tool | What it answers |
|---|---|
| `mtr` `gping` | Where is the latency, and is it getting worse right now? |
| `tcpdump` `termshark` | What is actually on the wire? |
| `bandwhich` `iftop` `nethogs` `bmon` | Which process is eating the link? |
| `dog` `bind` (dig) | Is this a DNS problem? (It usually is.) |
| `socat` `websocat` `grpcurl` `xh` `hurl` | Reach the endpoint the way the client does. |
| `iperf3` `oha` | Is the path slow, or is the service slow? |
| `conntrack-tools` `nmap` `ethtool` `nftables` | Connection tracking, exposure, NIC state, firewall. |

### Performance and diagnosis

`perf` · `bpftrace` · `sysstat` (sar, iostat, pidstat) · `btop` · `iotop` ·
`numactl` · `procs` · `dust` · `duf` · `ncdu` · `smartmontools` · `nvme-cli` ·
`lm_sensors` · `nvtop` (GPU) · `intel-gpu-tools`.

### Logs and data — the daily grind

| Tool | Why it beats the obvious alternative |
|---|---|
| `duckdb` | SQL directly over CSV/JSON/Parquet. Analyse a log export without standing up a pipeline. |
| `miller` (`mlr`) | `awk`/`cut`/`sed` that understands CSV, TSV and JSON records. |
| `visidata` | Explore a large data file in the terminal, interactively. |
| `jless` | Navigate a huge JSON without loading it into an editor. |
| `glow` | Read runbooks and ADRs in the terminal. |

### Local labs — observability without a cloud bill

An SRE workstation with no local observability is a strange thing. But
Prometheus, Grafana and Loki running as system services 24/7 would cost ~800 MB
of RAM for something you use a few hours a week. So they ship as a **lab**:

```bash
delonix-toolbox lab up observability
#   Grafana:    http://localhost:3000   (already wired to Prometheus and Loki)
#   Prometheus: http://localhost:9090   (already scraping this machine)
delonix-toolbox lab down observability  # gives the memory back; data is kept
```

It runs on **rootless Podman** via `podman kube play` — no daemon, no
docker-compose. `node-exporter` is configured with **PSI pressure metrics**, the
ones that actually explain "the machine feels slow". Point a job at your own
`/metrics` endpoint and your service appears in the same dashboards.

### Recording and editing — OBS Studio and DaVinci Resolve

Two tools, chosen deliberately. The setup people usually spend an afternoon
discovering already ships:

| | What is already configured |
|---|---|
| **OBS Studio** *(in the ISO)* | a profile and **four scenes** — *Full screen*, *Screen + camera* (bottom right, 25%), *Camera only*, *Break*. 1080p60 with **no rescaling** (unreadable terminal text in a recording is always rescaling), **mkv** output so an interrupted recording is not lost, and `Ctrl+F9/F10/F11` to start, stop and pause. |
| **Microphone** | OBS ships **RNNoise**, a noise gate and a compressor on the audio source. It is what separates an audible lesson from one with a fan and a keyboard in it — and it needs nothing else installed. |
| **DaVinci Resolve** *(on request)* | `delonix-toolbox install davinci` |

**Why Resolve is not in the ISO**: it is proprietary and the installer sits
behind a Blackmagic registration form — it cannot be downloaded by a script.
`delonix-toolbox install davinci` looks for the `.zip` in `~/Downloads`, opens
the page if it cannot find it, and does **everything** else: dependencies,
building the package, installing.

**The trap that costs everyone their first afternoon**: the free version of
Resolve for Linux **does not decode H.264/H.265**. An OBS recording simply does
not appear on the timeline, and the error explains nothing. That is what
`delonix-video` is for:

```bash
delonix-video info aula.mkv               # warns if the file will not import
delonix-video para-davinci aula.mkv       # converts to DNxHR — imports cleanly
delonix-video publicar aula-editada.mov   # compresses for publishing
```

The original is never deleted. DNxHR is bigger (~2 GB per 10 min at 1080p), and
that is the price of free Resolve not reading H.264 — not a choice of ours.

Resolve also needs a GPU with OpenCL/CUDA. On Intel that is already there
(`intel-compute-runtime`); with NVIDIA, `delonix-toolbox install gpu-nvidia`.

### Backup and recovery

| Tool | Role |
|---|---|
| `restic` | Incremental, encrypted, deduplicated backups. |
| `rclone` | Move data between S3/GCS/Azure/local with one syntax. |
| `snapper` + `snap-pac` | **A snapshot is taken before every `pacman -Syu`.** On a rolling distro this is the difference between a scare and a lost weekend. Requires a Btrfs root. |
| `btrfs-assistant` | Browse and restore those snapshots with a UI. |

### Secrets and supply chain

`age` · `sops` · `step-cli` · `cosign` · `trivy` · `syft` · `gitleaks` ·
`keepassxc` · `openssl` · `gnupg` · `lynis`.

---

## Platform Engineering profile

The build-the-substrate half: clusters, infrastructure, golden paths.

### Kubernetes

| Tool | Role |
|---|---|
| `kubectl` `kubectx` `kubens` | The basics, with `k`, `kx`, `kn` aliases and helper functions (`ksecret` decodes a whole Secret, `kclean` strips server-managed fields). |
| `k9s` | Cluster TUI. |
| `helm` `kustomize` `kubeconform` | Template, overlay, and **validate manifests against the schema before applying**. |
| `stern` | Multi-pod log tailing. |
| `argocd` | GitOps CLI. |
| `kind` | Local cluster on **rootless Podman** (`KIND_EXPERIMENTAL_PROVIDER=podman` is already exported). |
| `krew` | kubectl plugin manager. |
| `cilium-cli` `etcd` (etcdctl) `cfssl` | CNI operations, control-plane diagnosis, certificates. |
| `eksctl` | EKS cluster lifecycle. |

More (`flux`, `kubeseal`, `velero`, `popeye`, `kubent`) via
`delonix-toolbox install k8s-extra`.

### Infrastructure as Code

`opentofu` (the default, not Terraform — licensing) · `ansible` + `ansible-lint`
· `packer` · `cue` · `yamllint`.

### Virtualization — real labs, not toys

| Tool | Note |
|---|---|
| `KVM` + `libvirt` + `virt-manager` | **Nested virtualization is on** (`kvm_intel/kvm_amd nested=1`), so a hypervisor runs inside a VM. The `default` network is autostarted and your user is in the `kvm` and `libvirt` groups on first boot. |
| `qemu-full` `edk2-ovmf` `swtpm` `virtiofsd` | UEFI firmware, virtual TPM, host↔guest file sharing. |
| `cloud-hypervisor` | Lightweight VMM for microVMs. |
| `libguestfs` `cloud-image-utils` | Inspect disk images; build cloud-init seed ISOs. |

### Cloud

`aws-cli-v2` + `aws-vault` (credentials not sitting in plaintext) · `gcloud` +
GKE auth plugin. Azure on request: `delonix-toolbox install cloud-azure`.

---

## Hardware acceleration — enabled, not left on the table

Without this layer, a modern workstation runs with half its hardware idle:
video decoded on the CPU, no OpenCL, an invisible NPU.

`intel-compute-runtime` (OpenCL + Level Zero) · `intel-media-driver` (VA-API) ·
**`intel-npu-driver`** (Core Ultra NPU) · `level-zero-loader` ·
`vulkan-icd-loader` · `clinfo` · `nvtop` · `radeontop`.

AMD ROCm and NVIDIA CUDA depend on the detected hardware:
`delonix-toolbox install gpu-amd` / `gpu-nvidia`.

Local models that use it: `delonix-toolbox install ai-local` (Ollama).

---

## Optional profiles

Everything else is one command away. `delonix-toolbox list` shows what is
installed:

| Profile | Contents |
|---|---|
| `lang-java` | OpenJDK 21, Maven, Gradle |
| `lang-rust-multi` | rustup, for per-project toolchains |
| `lang-node-extra` | yarn, deno, bun |
| `lang-python-data` | numpy, pandas, matplotlib, ipython |
| `k8s-extra` | flux, kubeseal, velero, popeye, kubent |
| `cloud-azure` | Azure CLI |
| `gpu-amd` / `gpu-nvidia` | ROCm / CUDA |
| `virt-extra` | firecracker, vagrant, virtctl |
| `ai-local` | Ollama |
| `ide-extra` | VS Code, DBeaver, Postman |
| `observability` | k6, vector, prometheus |
| `printing` | CUPS and drivers (kept off the image on purpose) |
| `office` | LibreOffice, Thunderbird — for those who really need them |

---

## What is deliberately absent

| Not included | Reason |
|---|---|
| LibreOffice, Thunderbird, KDE PIM | This is not an office desktop. KMail/Akonadi alone runs a database in the background. |
| `baloo` file indexing | The number one cause of phantom I/O on a machine with large repositories. |
| KDE games, media players, k3b, scanners | No function on an engineering workstation. |
| Printing stack | Installed on request; it is a large dependency tree for a rare need. |
| `dockerd` | Contradicts the rootless, daemonless rule. The CLI is there; the daemon is a conscious `systemctl enable` away. |
| Desktop animations | GPU, memory and latency spent on decoration. `delonix-toolbox eyecandy on` restores them. |

The full list, with the reason for each removal, lives in
[`packages/blocklist.txt`](../../packages/blocklist.txt) — and the build **fails**
if any of them comes back.
