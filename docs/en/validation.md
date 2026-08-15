# Validating a build

An ISO that boots is not an ISO that works. This list is the difference between
the two, ordered to fail early and fail cheap.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/validacao.md)

## Before the build

```bash
make verify        # files, blocklist, syntax, theme coherence
make check         # + every package exists and no declared conflicts (network)
```

## At boot (QEMU: `make test`)

| # | Check | How you know it failed |
|---|---|---|
| 1 | GRUB menu with the Delonix theme | black background with white text = `theme.txt` did not load |
| 2 | **Animated** Plymouth splash (rings propagating) | still logo = frames missing; scrolling boot text = theme never reached the initramfs |
| 3 | No kernel messages visible | `quiet splash` missing from `GRUB_CMDLINE_LINUX_DEFAULT` |
| 4 | SDDM with the Delonix theme | Breeze screen = QML error; check `journalctl -u sddm` |
| 5 | Login `delonix`/`delonix` works | — |
| 6 | KSplash with the logo | Plasma starting with no splash = `ksplashrc` not applied |
| 7 | Dark desktop, red accent, Delonix wallpaper | global theme not applied to `/etc/skel` |
| 8 | Single bottom panel with the right launchers | look-and-feel `layouts/*.js` ignored |

Easy to miss: Plymouth only shows up if the theme is **inside the initramfs**. If
it fails, on the installed system run:

```bash
sudo plymouth-set-default-theme -R delonix
```

## In the live session

```bash
delonix-doctor          # must exit 0 (KVM warnings are normal inside a VM)
delonix-toolbox list
```

Then, by hand:

```bash
podman run --rm docker.io/library/alpine echo rootless-ok   # no sudo
docker ps                                                   # CLI talking to Podman, no dockerd
kubectl version --client && helm version && tofu version
aws --version && gcloud version
claude --version && antigravity --version
cargo --version && go version && python -V && uv --version
ulimit -n                                                   # >= 1048576
sysctl fs.inotify.max_user_watches                          # 1048576
zramctl                                                     # zram0 active
tmux ls                                                     # the "delonix" session exists
```

Virtualization — the easiest part to ship broken:

```bash
cat /sys/module/kvm_intel/parameters/nested   # Y  (or kvm_amd)
virsh --connect qemu:///system net-list       # "default" active
virt-install --version && cloud-hypervisor --version
tuned-adm active                              # delonix-lab
```

## After installing to disk

| # | Check | Why it matters |
|---|---|---|
| 1 | `systemctl status delonix-firstboot` = `exited (0)` | it is what creates subuid/subgid |
| 2 | `grep $USER /etc/subuid /etc/subgid` returns lines | without them there are no rootless containers |
| 3 | `cgroup.controllers` for your user includes `memory pids` | resource limits under rootless |
| 4 | `delonix-doctor` green | summary of everything above |
| 5 | `podman run --memory 256m ...` respects the limit | proves delegation actually works |
| 6 | Reboot twice | catches services that only fail on the second boot |
| 7 | `pacman -Syu` runs clean | proves the base was not broken by the overlays |
| 8 | `systemctl is-enabled docker` = `disabled` | the daemon must stay off |
| 9 | Create and start a VM in `virt-manager` | proves KVM + libvirt + default network + permissions |
| 10 | Inside that VM: `lscpu \| grep -i hypervisor` and `ls /dev/kvm` | proves nested virtualization really works |
| 11 | `pacman -Qo /usr/share/plymouth/themes/delonix/delonix.script` says `delonix-os-branding` | the theme is package-managed, which is what makes it updatable |
| 12 | `pacman -Qo /etc/sysctl.d/99-delonix.conf` says `delonix-os-settings` | same for the tuning |
| 13 | `pacman -Q delonix-os` returns a version | the meta-package is installed |

### Proving updates actually arrive

Having the package installed is not the point — v1.0.1 replacing v1.0.0 without
breaking anything is. On an installed VM:

```bash
# in the repository: bump the version, rebuild, publish locally
echo 1.0.1 > VERSION && make packages

# on the VM (with the repo mounted or copied)
sudo pacman -Syu delonix-os
pacman -Q delonix-os-branding          # must say 1.0.1
ls /etc/*.pacnew /etc/**/*.pacnew      # only what YOU edited by hand should appear
```

`.pacnew` is the signal to watch: if it shows up for a file nobody edited,
something is writing over package-owned content — probably a duplicate left in
the overlay.

## Weight and tuning (the stated goals)

```bash
ls -lh out/**/*.iso                    # target: ISO < 5 GB
# on the installed system:
pacman -Q | wc -l                      # target: < 1700 packages
df -h /                                # target: < 18 GB used after install
free -m                                # target: < 1.1 GB idle on the desktop
systemd-analyze                        # target: < 15 s to SDDM (NVMe)
```

The targets went up on purpose when the distro started shipping languages,
databases and three browsers. What must **not** go up is idle memory: past ~1.1
GB, something started on its own that should not have — most likely a database.

```bash
delonix-toolbox db status              # all "inactive" on a clean boot
systemctl list-units --state=running | wc -l
```

And the tuning nobody should have to do by hand:

```bash
cat /sys/block/nvme0n1/queue/scheduler     # [none]
sysctl net.core.default_qdisc              # fq   (BBR needs it)
clinfo -l                                  # OpenCL sees the GPU
ls /dev/accel/accel0                       # NPU (Core Ultra), if present
systemctl is-active ananicy-cpp psd        # priorities and RAM-backed profiles
kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor  # 0
```

If any of the weight numbers runs away, the culprit is usually a meta-package in
`Packages-Desktop` that dragged in half of KDE. `pacman -Qi <pkg>` and
`pactree -r <pkg>` will name it.
