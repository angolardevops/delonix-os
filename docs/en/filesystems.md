# Filesystem and disk layout

The installer suggests **Btrfs** with a subvolume layout designed for people who
run VMs, local clusters and builds. This page explains the choice — and when to
pick something else.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/sistemas-de-ficheiros.md)

## The recommendation, in one line

| Profile | Recommendation |
|---|---|
| Workstation (the normal case) | **Btrfs** with the subvolumes below |
| A machine that must just boot and never surprise you | **ext4** |
| A separate disk holding only VM images | **XFS** |
| Storage server with disks to spare | **ZFS**, and not as root |

## Why Btrfs by default

Three concrete reasons, not ideological ones:

**Snapshots before every upgrade.** The distro ships `snapper` + `snap-pac`:
each `pacman -Syu` takes a snapshot before touching the system. On a rolling
distro that is the difference between a two-minute scare and a weekend
reinstalling. Without Btrfs (or ZFS) that safety net does not exist.

**Compression that makes the disk faster.** `compress=zstd:1` is not there to
save space — it is there to **read fewer bytes**. On an NVMe, decompressing costs
less than reading the extra bytes, so the system ends up both faster and smaller.
Level 1 is the point where that is still true; higher levels save more space and
start costing CPU.

**Subvolumes instead of partitions.** On a machine running VMs and local
clusters, space is never where you predicted. With fixed partitions, `/var` fills
up while `/home` has 200 GB free. Subvolumes share the space and can still have
different policies.

## The layout, and the reason for each piece

```
/boot/efi   1 GiB    FAT32     (DELONIX_EFI)
/           Btrfs
├── @              →  /
├── @home          →  /home
├── @cache         →  /var/cache
├── @log           →  /var/log
├── @libvirt       →  /var/lib/libvirt
├── @delonix       →  /var/lib/delonix
└── @snapshots     →  /.snapshots
swap        small, only for hibernation
```

| Subvolume | Reason |
|---|---|
| `@home` outside `@` | a system rollback must not take your work with it |
| `@cache` and `@log` | restoring old logs and caches is worse than losing them; they stay out of snapshots |
| `@libvirt` | a VM image is tens of GB. Inside snapshots, every upgrade would "keep" those GB — and snapshots would become impractical |
| `@delonix` | the same reasoning for Delonix Runtime container images |
| `@snapshots` | where `snapper` keeps what it takes |

**Small swap, on purpose.** Paging happens in RAM through `zram` (half the RAM,
zstd-compressed), which is orders of magnitude faster than disk. The swap
partition exists only to **hibernate** — that is the one case where it needs to
fit all of RAM.

## When not to use Btrfs

**ext4** — when the criterion is "must always boot and be repairable anywhere".
No snapshots, no compression, but every live CD in the world can fix it and
nobody ever needed a manual to do so. If the machine is critical and not yours,
that is a defensible choice.

**XFS** — for a separate disk holding VM images or large data. It handles
parallel writes to huge files better and does not fragment like Btrfs does with
random-access files. As a root filesystem you lose what matters (snapshots)
without gaining enough. Mounted at `/var/lib/libvirt`, it makes sense.

> If you keep VM images on Btrfs — which is the default — the `@libvirt`
> subvolume is already created, but it is worth disabling copy-on-write there:
> `chattr +C /var/lib/libvirt/images` (on an empty directory). Without it, a
> random-access disk image fragments over time.

**ZFS** — the best filesystem on this list at almost everything: end-to-end
checksums, compression, snapshots, send/receive for backup. And it still does
**not** ship by default, for a practical reason: the module lives outside the
kernel (incompatible licence), so every kernel upgrade can leave the machine
unbootable until it is rebuilt. On a rolling distro that happens often.

It makes sense on a storage server with a pinned kernel, or as a data pool
separate from root — not as the root of a workstation that updates weekly.

## Checking after installation

```bash
findmnt -t btrfs -o TARGET,SOURCE,OPTIONS      # subvolumes and options
btrfs filesystem usage /                        # real space (≠ df)
compsize /                                      # how much compression is saving
snapper -c root list                            # do the snapshots exist?
sudo btrfs filesystem defragment -r -czstd /var/log   # if logs bloat
```

One detail that confuses everyone: `df` **lies** on Btrfs. A system with
compression and subvolumes reports numbers that do not add up.
`btrfs filesystem usage` is the source of truth.
