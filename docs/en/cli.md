# `delonixos` — build it from your own distro

You do not need to run Manjaro to build DelonixOS. The ISO is always produced by
`buildiso`, which needs an Arch/Manjaro environment — but that environment lives
in a container, and `delonixos` handles it for you.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/cli.md)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/angolardevops/delonix-os/main/install.sh | sh
```

Installs to `~/.local/bin` (no sudo). For a system-wide install:
`curl … | sudo PREFIX=/usr/local sh`.

The only hard requirement is **Python 3.8+ with the standard library** —
Debian's `python3-minimal` is not enough (it does not even ship `json`). PyYAML
is used when present; when it is not, a built-in reader handles the inventory
format.

## The three things it does

### 1. Tell you if this machine can build

```bash
delonixos doctor
```

It detects your distro from `/etc/os-release` and gives you the **exact command**
for your package manager, not a generic "install podman":

| Host | What it needs | Can build natively? |
|---|---|---|
| Ubuntu · Debian · Mint · Zorin · Pop | `sudo apt-get install -y podman uidmap slirp4netns python3` | no — container |
| Fedora · RHEL · Rocky · Alma | `sudo dnf install -y podman python3` | no — container |
| openSUSE | `sudo zypper install -y podman python3` | no — container |
| Arch · Manjaro · EndeavourOS | `sudo pacman -S --needed manjaro-tools-iso git rsync python python-pillow` | **yes** |

### Versions

```bash
delonixos distros                      # what is supported, and what the default resolves to
delonixos build --from ubuntu          # latest LTS (24.04)
delonixos build --from ubuntu:22.04    # a specific LTS
delonixos build --from fedora          # the newest (43)
delonixos build --from zorin:17        # Zorin 17 = Ubuntu 22.04 base
```

Two policies, because the families do not behave the same way:

| Policy | Distros | With no version | Refuses |
|---|---|---|---|
| **`lts`** | Ubuntu, Zorin, Mint, Pop!_OS | the **latest LTS** | non-LTS versions |
| **`latest`** | Fedora, Debian, RHEL, openSUSE, Arch, Manjaro | the **newest** | — |

Ubuntu is LTS-only on purpose: interim releases live nine months, and a
workstation that builds images should not be jumping releases twice a year.

**Zorin** is Ubuntu underneath, and that base is what matters for packages —
Zorin 18 sits on Ubuntu 24.04, Zorin 17 on 22.04. `doctor` says so explicitly.

An out-of-support version is not refused, but it **is** flagged: it still
builds, and you learn you are running without security fixes.

It also checks disk (35 GB), RAM, CPU count and whether you have real root — the
`buildiso` needs it to mount loop devices, and finding that out at minute 40 is
expensive.

### 2. Build the official ISO

```bash
delonixos build --from ubuntu       # or fedora, debian, arch, manjaro…
```

Without `--from`, the host is auto-detected. `--from` exists for when you know
better than the detection, or when you want the command in a script to be
explicit.

### 3. Build *your* distro from an inventory

```bash
delonixos init my-distro --distro ubuntu
cd my-distro
$EDITOR delonixos.yaml
delonixos validate
delonixos build -f delonixos.yaml
```

`init` creates a project:

```
my-distro/
├── delonixos.yaml       your inventory — the source of truth
├── overlays/            files copied into the image (overlays/etc → /etc)
└── binaries/            local binaries to include
```

## The inventory

```yaml
apiVersion: delonixos/v1
kind: Distro

metadata:
  name: my-distro
  version: 1.0.0
  codename: Acacia

spec:
  extends: delonix/devops      # or `scratch` to start from the minimum
  host:
    distro: ubuntu             # where YOU build; does not change the ISO

  base:
    kernel: linux612
    branch: stable             # stable | testing | unstable
    compression: zstd

  packages:
    desktop:                   # added on top of the base profile
      - jq
      - kubectl=1.31.4-1       # pinning — read the warning below
    root: []
    aur:                       # compiled during the build (slower)
      - lazygit-git
    remove:                    # base-profile packages you do not want
      - firefox

  binaries:
    - name: mytool
      url: https://example.com/mytool
      dest: /usr/local/bin/mytool
      mode: "0755"
      sha256: ""               # optional, recommended
    # - path: binaries/mytool  # or a local file instead of a URL

  overlays:
    - src: overlays            # relative to this file
      dest: /

  services:
    enable: [my-agent.service]
    disable: [bluetooth]

  users:
    live:
      name: my-distro
      password: my-distro
      groups: [wheel, video, audio, network, kvm, libvirt]
```

### About pinning versions

`packages.desktop: [kubectl=1.31.4-1]` works, but with a limit worth
understanding: **pacman only installs a version that exists in the configured
repository**. Arch and Manjaro do not keep an archive of every past version the
way apt repositories often do. So a pin is really "fail if this is not the
current version", which is useful as a guard but is not a time machine.

For genuinely reproducible builds, pin the *repository*, not the package: use an
Arch Linux Archive snapshot as the mirror. That is on the roadmap as first-class
support; today you can do it by editing the mirror in the build container.

### `extends`

| Value | Meaning |
|---|---|
| `delonix/devops` | the official profile — everything documented in [tools by profile](tools-by-profile.md), and your entries on top |
| `scratch` | the minimum that boots; you build the list yourself |

## What actually happens during a build

```
delonixos build -f delonixos.yaml
        │
        ├── validates the inventory                (seconds)
        ├── renders it into a manjaro-tools profile (build/profile/)
        │     └── base profile + your packages − removals + your overlays
        ├── starts a privileged Manjaro container
        │     ├── compiles AUR packages into a local repository
        │     ├── compiles the delonix-os-* packages
        │     └── buildiso
        └── prints the QEMU command for the resulting ISO
```

The rendered profile is left on disk (`build/profile/`) on purpose — it is
readable, diffable, and it is exactly what `buildiso` consumed. When something
goes wrong, that directory is where you look.

## Is it actually tested?

Yes, and you can repeat it:

```bash
make distro-test                          # the default set
./scripts/test-distros.sh fedora:42       # or a specific one
./scripts/test-distros.sh --all
```

It runs the full path — `doctor` → `init` → `validate` → `render` — **inside a
container of each distro**, and checks the rendered profile exists at the end.
Not a claim in a README: the command actually running on a real Ubuntu 22.04.

Two things this test taught, neither of them about `delonixos`:

- Inside a rootless container the host resolver (`systemd-resolved` on
  127.0.0.53) is unreachable — without an explicit `--dns`, no distro installs
  anything.
- DNS returns AAAA records but there is no IPv6 route, so `apt` resolves and
  then hangs. It needs `ForceIPv4`.

A slow mirror is reported as **"not verified (network)"**, not as a failure:
calling it a product failure when the network is what failed would misrepresent
what was tested.

What this does **not** cover: the ISO build itself — that needs root, loop
devices and 35 GB. But that step runs in the same Manjaro container on every
host; what varies between distros is exactly what is tested here.

## Commands

| Command | What it does |
|---|---|
| `delonixos doctor` | prerequisites for this host |
| `delonixos distros` | supported distros and versions |
| `delonixos init [path]` | create a project with an inventory |
| `delonixos validate -f f.yaml` | check the inventory without building |
| `delonixos render -f f.yaml` | inventory → manjaro-tools profile, without building |
| `delonixos build [--from d] [-f f.yaml]` | build the ISO |

Useful flags: `--kernel linux612`, `--engine podman\|docker`, `--dry-run`,
`-o <dir>` for the rendered profile.

## Environment variables

| Variable | Purpose |
|---|---|
| `DELONIXOS_HOME` | path to the delonix-os repository (otherwise it is cloned to `~/.local/share/delonixos`) |
| `DELONIX_SKIP_AUR=1` | skip AUR compilation — much faster, ISO ships without those tools |
| `DELONIX_CACHE` | where packages and chroots are cached between builds |
