# `delonix-toolbox` — the control panel of DelonixOS

The distro ships complete, but not with everything switched on.
`delonix-toolbox` is the single command for the decisions deliberately left
open: which extras to install, which databases to start, which labs to bring
up, and when to update.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/delonix-toolbox.md)

```bash
delonix-toolbox                 # help + what is installed
delonix-toolbox list
```

---

## `install` / `remove` — extras on demand

The ISO ships what 90% of people use. The rest lives here, grouped by use case
rather than by package:

```bash
delonix-toolbox install lang-java k8s-extra
delonix-toolbox remove lang-java
```

| Profile | Contents |
|---|---|
| `lang-java` | OpenJDK 21, Maven, Gradle |
| `lang-rust-multi` | rustup, for per-project toolchains |
| `lang-node-extra` | yarn, deno, bun |
| `lang-python-data` | numpy, pandas, matplotlib, ipython |
| `k8s-extra` | flux, kubeseal, velero, popeye, kubent |
| `cloud-azure` | Azure CLI (AWS and GCP already ship) |
| `gpu-amd` / `gpu-nvidia` | ROCm / CUDA (~2–3 GB) |
| `virt-extra` | firecracker, vagrant, virtctl |
| `ai` | Claude Code + Antigravity (reinstall/update) |
| `ai-local` | Ollama — local models on the GPU/NPU already enabled |
| `ide-extra` | VS Code, DBeaver, Postman |
| `observability` | k6, vector, prometheus (binaries, not the lab) |
| `delonix` | Delonix Runtime + delonixctl |
| `printing` | CUPS and drivers |
| `office` | LibreOffice, Thunderbird |

`list` marks with `✓` what is already installed.

---

## `db` — databases, started only when needed

PostgreSQL, Redis (valkey) and MongoDB **ship installed and stopped**. Three
sleeping servers cost ~600 MB of RAM nobody asked for.

```bash
delonix-toolbox db status                      # what is running
delonix-toolbox db start postgres              # start now (initdb handled for you)
delonix-toolbox db enable postgres redis       # start now AND at boot
delonix-toolbox db stop postgres               # give the memory back
delonix-toolbox db disable mongo
```

With no database argument, the command applies to all three.

`start` handles the Postgres `initdb` the first time. Without it the service
fails with an error that tells nobody what to do — the kind of detail that
costs half an hour to the first person who hits it.

---

## `lab` — local stacks that do not live installed

A lab is a stack you want running a few hours a week. It runs in containers,
keeps its data between sessions, and costs nothing while it is down.

```bash
delonix-toolbox lab list
delonix-toolbox lab up observability
delonix-toolbox lab status
delonix-toolbox lab logs observability
delonix-toolbox lab down observability
```

**Engine**: the **Delonix Runtime** by default — it is the house engine, and a
lab is exactly the workload it was built for. To compare behaviour, or while
the runtime is not installed yet:

```bash
delonix-toolbox lab up observability --target podman
delonix-toolbox lab up observability --target docker
```

The manifest is `kind: Pod` — the same format `delonix pod create -f` and
`podman kube play` consume. For docker, which has no equivalent, the toolbox
translates it into `docker run`: the first container publishes the ports and
the others share its network, which is the docker equivalent of a pod.

### `observability`

Prometheus + Grafana + Loki + node-exporter:

```
Grafana:    http://localhost:3000   (no login — it is local)
Prometheus: http://localhost:9090   (already scraping this machine)
Loki:       http://localhost:3100
```

`node-exporter` ships with **PSI** metrics, the ones that actually explain "it
feels slow" — CPU, memory and I/O saturation, rather than percentages that say
nothing.

**The configuration is yours.** On first use it is copied to
`~/.local/share/delonix/labs/observability/config/` and **never overwritten
again**. To have Prometheus scrape what you are building, add your target to
`prometheus.yml` and bring the lab up again.

Data (time series, dashboards, logs) lives in `.../labs/<name>/dados/` and
survives `lab down`.

---

## `update` — system and engine, in one command

```bash
delonix update                  # or: delonix-toolbox update
delonix update --check          # what would change, without installing
delonix update --delonix-only   # only the Delonix Runtime
```

It handles the three sources this distro is made of, which would otherwise need
three different commands:

1. the repositories (Manjaro + `[delonix]`) and the AUR — via `yay`/`pacman`;
2. the **Delonix Runtime**, which comes from published artifacts, not from any
   repository;
3. it warns when the kernel changed and a reboot is needed to use it.

It prints every version at the end.

> **A note on `delonix update`**: `delonix` is the runtime binary and has no
> `update` subcommand. The distro's `.zshrc` intercepts that form and delegates
> to the toolbox — and the function **disables itself** the day the runtime
> gains its own `update`, so nothing is ever hidden from you. Outside zsh, use
> `delonix-update` or `delonix-toolbox update`.

---

## `eyecandy` — desktop animations

By default KDE ships with no animations, no blur and no file indexing: that is
GPU, memory and latency spent on decoration.

```bash
delonix-toolbox eyecandy on     # restore animations, blur, transitions
delonix-toolbox eyecandy off    # back to the DelonixOS default
```

---

## `unprivileged-ports` — publishing :80 without root

```bash
delonix-toolbox unprivileged-ports on
delonix-toolbox unprivileged-ports off
```

Lowers `net.ipv4.ip_unprivileged_port_start` to 80, which lets a rootless
container publish ports 80/443. It is convenient **and** it is a trade-off: any
process of your user can then impersonate a system service. That is why it does
not ship enabled.

---

## See also

- [`delonix-doctor`](tools-by-profile.md) — machine diagnosis (rootless,
  cgroups, KVM/NPU, I/O, network, running labs)
- [`delonixos`](cli.md) — build the ISO, or your own distro

## `add kernel` — another kernel, drivers included

```bash
delonix-toolbox add kernel --list              # what exists
delonix-toolbox add kernel --version 7.2       # install, extramodules included
delonix-toolbox add kernel --version 7.3 --compile
```

One command: installs the requested version, brings along the modules your
current kernel has — NVIDIA included — and adds a new boot entry. It **does not
replace the running kernel**; if the new one misbehaves, reboot and pick the old
one from the GRUB menu.

### Why this does not always compile

Compiling a kernel for the machine's hardware sounds better than it is. The
repositories carry 6.6, 6.12, 6.18, 7.1 and 7.2 already built, signed, with
automatic security updates and — the part that is hardest to reproduce — with
the **extramodules** alongside: `nvidia`, `nvidia-open`, `r8168`, `vhba`,
`virtualbox-host-modules`, one set per kernel version.

A hand-built kernel loses all of that. Proprietary modules fall to DKMS, which
rebuilds them on every update and fails when the vendor does not support the
version yet. On a working machine that means no graphical session on a Monday
morning.

So the order is: **if a package exists, install the package.** Compile when one
does not — a newer upstream version, or a patched kernel — and then
`delonix-kernel` does the work with `localmodconfig`, which generates a config
containing only the modules *this* machine has loaded. That is the optimisation
that matters: it cuts build time to a fraction and yields a much smaller
initramfs.

`--compile` forces compilation even when a package exists, for those who know
why — and it says what you are trading before it starts.

### NVIDIA, on both paths

| Path | How the module is built |
|---|---|
| Package (`--version 7.2`) | `linux72-nvidia`, prebuilt and tested against that kernel |
| Compiled (`--compile`) | `nvidia-dkms`, rebuilt on every update |

Either way, the command checks there is an actual NVIDIA GPU before installing
anything.
