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
| [`delonix-tune`](#delonix-tune) | tune this machine to the hardware it is actually on |
| [`delonix tunnel`](#delonix-tunnel) | put a local service on a public URL |
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

## `delonix-tune`

```bash
delonix-tune                    # what hardware is this, and is it tuned for it
delonix-tune apply              # detect and apply (runs once at first boot)
delonix-tune profile quiet      # lab | balanced | quiet
delonix-tune thermal            # live temperature, frequency and throttling
```

One ISO boots on an AMD Ryzen laptop with hybrid graphics and on an Intel vPro
desktop. The settings that make one fast make the other hot, so nothing is
decided when the image is built — it is decided on the machine, from the CPU
vendor, the chassis and the GPUs present.

What it actually changes:

| Detected | Consequence |
|---|---|
| Battery present | `delonix-lab-mobile` profile — deep idle states kept, EPP `balance_performance` |
| No battery | `delonix-lab` profile — deep idle disabled, EPP `performance` |
| Intel CPU | `thermald` enabled (it is Intel-only code) |
| AMD CPU | `thermald` disabled, `k10temp` loaded so temperature is readable at all |
| Two or more GPUs | `switcheroo-control` enabled; `prime-run` available |

### Why the laptop profile is not the slow one

On a laptop, `governor=performance` is not faster — it is hotter. With
`amd_pstate=active` or `intel_pstate=active` the frequency decision belongs to
the processor itself (CPPC/HWP), which reaches full clock in microseconds when
work arrives. The `performance` governor does not raise that ceiling; it only
stops the CPU coming down when there is nothing to do.

The cost is real: a processor kept warm at idle starts every build already
against its thermal limit and throttles sooner. Keeping cores in deep idle
frees thermal budget the active cores spend on boost. Under sustained load —
which is what a build is — the mobile profile is the faster of the two.

If you disagree for your machine, `delonix-tune profile lab` forces the desktop
profile and it stays until you change it.

## `delonix tunnel`

```bash
delonix tunnel 8080                        # default provider (pinggy)
delonix tunnel --provider cloudflare 3000
delonix tunnel --provider ngrok 8080
delonix tunnel --list                      # what is currently exposed
delonix tunnel --stop                      # close them
```

A webhook from Stripe or GitHub has to reach a service running on this laptop,
or a colleague needs to see a demo before it is deployed. The job is always the
same; only the provider differs, and each has its own flags and its own way of
printing the URL.

| Provider | Account | Installed as | Best for |
|---|---|---|---|
| **pinggy** *(default)* | none | nothing — it is plain SSH | a machine you just installed; expires after 60 min |
| **cloudflare** | none for `try-cloudflare` | `cloudflared` (repos) | a demo that has to survive the afternoon |
| **ngrok** | required, even free | `ngrok` (AUR) | when you need to *see* the request body, at `localhost:4040` |

Pinggy is the default because it is the only one that needs nothing: it is SSH
remote port forwarding (`ssh -p 443 -R0:localhost:8080 a.pinggy.io`) and
`openssh` is already here. There is no pinggy binary in the ISO because there is
no pinggy binary to install.

### It refuses some ports on purpose

Exposing a local service means anyone with the URL can reach it — that is the
point, and also the risk. Development services usually assume only you can get
to them, so ports that are almost never meant to be public (PostgreSQL, Redis,
MongoDB, etcd, the Kubernetes API, …) are refused unless you add `--force`.

It also checks that something is actually listening first. A tunnel to a port
with nothing behind it returns 502, and that costs ten minutes to work out.

> `delonix` is the runtime binary and has no `tunnel` subcommand. The `.zshrc`
> intercepts the form and delegates — and stops doing so the day the runtime
> gains its own. Outside zsh, use `delonix-tunnel`.

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
