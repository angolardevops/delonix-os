# Command reference

Every `delonix-*` command, what it is for, and the reasoning behind the defaults.
All commands and their options are in English; the code comments stay in
Portuguese, which is where the reasoning was written.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/comandos.md)

| Command | One line |
|---|---|
| [`delonix-doctor`](#delonix-doctor) | is this machine actually ready? |
| [`delonix-toolbox`](delonix-toolbox.md) | install extras, start databases, run labs |
| [`delonix update`](delonix-toolbox.md#update--system-and-engine-in-one-command) | update the system and the Delonix Runtime |
| [`delonix-load`](#delonix-load) | run heavy work without losing the machine |
| [`delonix-kernel`](kernel.md) | build, boot and install a Linux kernel |
| [`delonix-video`](#delonix-video) | bridge OBS recordings into DaVinci Resolve |
| [`delonixos`](cli.md) | build the ISO, or your own distro |

---

## `delonix-doctor`

```bash
delonix-doctor          # exits 0 if everything passed, 1 if anything failed
```

It answers one question — can this machine run rootless containers, local
clusters and platform tooling? — and it answers it in checks you can act on,
not in a wall of information.

It checks: cgroup v2 and which controllers are **delegated** (without `memory`
and `pids`, rootless containers silently ignore resource limits), subuid/subgid
ranges, inotify and file descriptor limits, `/dev/kvm` and whether nested
virtualization is on, GPU/NPU and OpenCL, the I/O scheduler per disk, BBR with
`fq`, memory accounting (without it every limit is decoration), the clipboard,
running labs and databases, filesystem and snapshots, and the locale.

Because it exits non-zero on failure, it works as a gate in image CI — not just
as something a person reads.

## `delonix-load`

```bash
delonix-load cargo build --release
delonix-load --cpu 30 --mem 50% podman build .
delonix-load --status
```

`ananicy-cpp` already lowers compiler priority automatically. This is the next
step: it puts the command in its own cgroup with reduced CPU and I/O weight and
a memory ceiling.

The practical difference: with `nice` alone, a 32-thread build can still fill
memory and the disk queue, and the desktop stutters anyway. With a cgroup it
cannot. The build gets a few percent slower and you keep working — which is the
trade you actually wanted.

## `delonix-video`

```bash
delonix-video info lesson.mkv          # warns if the file will not import
delonix-video to-davinci lesson.mkv    # convert to DNxHR
delonix-video publish edited.mov       # compress for publishing
```

It exists because the **free** version of DaVinci Resolve for Linux does not
decode H.264/H.265. An OBS recording simply does not appear on the timeline and
the error explains nothing — the trap that costs everyone their first afternoon.

DNxHR rather than ProRes: faster to decode on x86 and read natively by Resolve
on Linux. The original is never deleted.

## Conventions shared by all of them

- **Exit codes mean something.** 0 is success, non-zero is failure. Every one of
  these can be used in a script.
- **Nothing destructive without saying so.** `delonix-kernel install` adds a boot
  entry rather than replacing one; `delonix-video` never deletes the source;
  `delonix-toolbox install zfs` explains the risk and asks.
- **A failure explains the next step.** `delonix-doctor` reporting a missing
  delegated controller tells you which file to look at.
- **`--help` on all of them**, and the first lines of every script are its
  documentation — `head -20 $(which delonix-load)` is a valid way to read it.
