# Roadmap

Ordered as a foundation: each item unblocks the next. Do not skip.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/roteiro.md)

## Done

- [x] Complete `manjaro-tools` profile (`delonix/devops`) with a minimal Plasma
- [x] Package curation: −3.5 GB of bloat, + the platform kit, with a blocklist
      enforced at build time
- [x] Branding generated from code, based on the official mark (globe + signal
      rings + antennas): GRUB, **animated** Plymouth (24 frames, with the LUKS
      dialog), SDDM, KSplash in QML, global theme, colour scheme, wallpapers up
      to 4K
- [x] Virtualization ready to use: KVM with nesting, libvirt + default network,
      virt-manager, qemu-full, cloud-hypervisor, `tuned` delonix-lab profile
- [x] Docker CLI without a daemon (talks to rootless Podman), tmux as the default
      console, AWS + GCP, Claude Code and Antigravity
- [x] Languages configured, not just installed (Rust with mold/sccache, Go,
      Python with uv, Node) and PostgreSQL/Redis/MongoDB installed but stopped
- [x] Factory tuning: cgroup delegation, subuid, inotify, zram, BBR + fq, I/O
      scheduler per disk type, OpenCL/NPU, ananicy-cpp
- [x] Light KDE: no animations, no blur, no indexing — reversible with
      `delonix-toolbox eyecandy on`
- [x] Local `[delonix-aur]` repository compiled during the build, with controlled
      degradation when an AUR package fails
- [x] Branding, settings and tools shipped as `delonix-os-*` packages instead of
      files copied into the image — this is what makes them updatable after
      installation
- [x] Pacman hooks that re-apply the splash and the GRUB theme when `plymouth` or
      `grub` are upgraded
- [x] Container build pipeline + pre-flight validation (`make verify` / `check`),
      including declared-conflict detection

## Next — in order

### 1. First real ISO
Run `make iso` on a machine with `sudo`, boot it in QEMU (`make test`) and walk
the [validation](validation.md) list. Until that is done, everything else is
theory.

### 2. Calamares branding
The installer is still Manjaro's. Missing: the QML slideshow, the logo,
Portuguese copy, and a suggested partitioning scheme (Btrfs with subvolumes and
snapshots, which is what makes sense for people who experiment a lot — and what
`snap-pac` needs to protect upgrades).

### 3. Publish the `[delonix]` repository
The packages **already exist** (`packaging/`), built during the build into a local
repository the ISO consumes. What is missing is infrastructure: publishing
(`rsync` to a server), signing, and pointing `Server =` at a public URL. Only
then does `pacman -Syu` bring new branding and tuning to people who already
installed.

Still to package: `delonix-runtime` and `delonixctl` (today fetched as release
binaries by `fetch-delonix-bins.sh`).

### 4. Signing and reproducibility
Sign the ISO, publish `SHA256SUMS` plus signature, and pin a repository snapshot
per release so the same commit produces the same image.

### 5. Updates for the installed system
Decide the model: follow Manjaro stable (simple) or freeze our own snapshots
(predictable, but needs infrastructure). Recommendation: follow stable and
publish only `delonix-os-*` in our repository.

### 6. Editions
- `delonix-os-server` — no Plasma, for bastions and CI runners
- `delonix-os-workstation` — this one, the reference

### 7. N'GolaCloud integration
`delonixctl` pre-configured, access profiles for the PaaS, and a first-run
shortcut that connects the workstation to a tenant.

## Deliberately out of scope

- **Docker daemon** — root daemon; contradicts the house rule (rootless,
  daemonless). Whoever needs it installs and owns that decision.
- **Our own graphical installer** — Calamares is enough and is maintained by
  others.
- **Our own desktop environment** — Plasma does the job; we only dress it.
