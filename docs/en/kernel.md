# Contributing to the Linux kernel

DelonixOS ships the toolchain and a command that removes the parts of kernel
work that are pure ceremony: finding out which packages are missing (one cryptic
error at a time), writing the same install steps by hand, and rebooting your
machine to test a change.

> 🇦🇴 [Esta página em português de Angola](../pt-AO/kernel.md)

## The short version

```bash
delonix-kernel setup                  # clone mainline, check the patch workflow
delonix-kernel config                 # start from the config of the kernel you are running
delonix-kernel build --install        # build it and add it as a separate boot entry
```

Then reboot and pick it in GRUB. If it does not boot, pick your distro kernel in
the same menu — **nothing was replaced**.

## Why a separate boot entry

Every step of `delonix-kernel install` is additive: a new `vmlinuz-<version>`, a
new initramfs, a new GRUB entry. Your working kernel is untouched.

This is not caution for its own sake. A kernel you built is, by definition,
under test — and a kernel under test that has replaced the only working one is
how people end up with a laptop, a USB stick and a bad evening. The version
string carries a `-delonix` suffix so it is obvious in the menu and in
`uname -r`.

## The loop that makes kernel work bearable

The slow way is: build, install, reboot, see the oops, reboot back, fix, repeat.
Twenty minutes per iteration, and every mistake costs you your session.

```bash
delonix-kernel build && delonix-kernel boot
```

`boot` starts the kernel you just built **in a VM**, using `virtme-ng`: no
install, no initramfs, no reboot. Your `/home` is mounted read-only inside, so
your test scripts are already there. You get a shell in a few seconds, you see
the oops in the same terminal, you exit with Ctrl-D and rebuild.

That is the difference between iterating four times an hour and forty.

## The commands

| Command | What it does |
|---|---|
| `delonix-kernel setup [url]` | clones mainline (or a URL you pass) into `~/src/linux`, checks `b4`, `sparse`, `pahole`, `virtme-ng`, and tells you what is missing from your `git send-email` setup |
| `delonix-kernel config [--local]` | starts from the running kernel's config (`/proc/config.gz`), answers new options with their defaults, and enables debug symbols, BTF, kprobes and ftrace. `--local` trims to the modules loaded *right now* |
| `delonix-kernel build [--install] [--boot] [--llvm]` | builds with `nproc-2` jobs, inside a weight-limited cgroup so the desktop stays usable |
| `delonix-kernel boot` | boots the built kernel in a VM (virtme-ng) |
| `delonix-kernel install` | installs it as a separate boot entry: modules, kernel, initramfs preset, GRUB |
| `delonix-kernel remove <version>` | removes one you installed (refuses to remove the running one) |
| `delonix-kernel check` | runs `sparse` over what is being rebuilt (`C=1`) |
| `delonix-kernel patches …` | `get` a series from lore, `prep` your own, `send` it |
| `delonix-kernel status` | what is running, what is cloned, what you have installed |

Environment: `DELONIX_KERNEL_SRC` (default `~/src/linux`),
`DELONIX_KERNEL_JOBS`, `DELONIX_KERNEL_SUFFIX`, `DELONIX_KERNEL_LLVM=1`.

## What `config` decides for you, and why

**Start from the running config.** A `defconfig` kernel usually will not boot
your laptop — no driver for your NVMe, no driver for your wifi. `/proc/config.gz`
is the configuration that is demonstrably working on this hardware right now.

**`olddefconfig`, not `oldconfig`.** Between two kernel versions there are
hundreds of new symbols. `oldconfig` asks you about every one; `olddefconfig`
takes the default. A five-second step instead of an hour of pressing Enter.

**Debug symbols and BTF on.** `DEBUG_INFO_DWARF5` is what turns a stack trace
into line numbers; `DEBUG_INFO_BTF` is what makes `bpftrace` and CO-RE work at
all. Both cost build time and disk, and both are the reason you are building a
kernel instead of using the distro one.

**`--local` when you want speed.** `make localmodconfig` keeps only the modules
loaded at that moment, which typically turns a 90-minute build into 8. The catch
is real and the command warns about it: plug in everything you use first —
dock, webcam, USB adapters — because what is not loaded will not be built.

## The patch workflow

The kernel runs on email, and that is not going to change. `b4` is what makes it
sane:

```bash
delonix-kernel patches get https://lore.kernel.org/all/<message-id>/
#   fetches the whole series, in order, and applies it

delonix-kernel patches prep -n my-topic
#   starts your own series

delonix-kernel patches send *.patch
#   sends it for review
```

`git send-email` needs three Perl modules that nobody remembers
(`perl-authen-sasl`, `perl-net-smtp-ssl`, `perl-mime-tools`) — without them it
fails at authentication with an error that helps no one. They ship installed.

Before your first patch, read
`Documentation/process/submitting-patches.rst` in the tree. It is not long, and
it answers most of what a reviewer would otherwise have to tell you.

## Tools that ship for this

| Tool | Why |
|---|---|
| `b4` | fetch, apply and reply to series from lore.kernel.org |
| `virtme-ng` | boot the kernel you just built, in seconds, without installing |
| `sparse` | the kernel's own semantic checker (`make C=1`) |
| `pahole` | generates BTF — without it there is no CO-RE and no useful bpftrace |
| `crash` | analyse a vmcore |
| `trace-cmd`, `bcc`, `bpftrace` | ftrace and eBPF with a human interface |
| `cscope`, `global` | navigate 30 million lines without an IDE |
| `patchutils`, `quilt` | compare two versions of a patch, manage a stack |
| `python-sphinx` | build `Documentation/` locally |

## If the build fails

```bash
delonix-kernel status              # what is cloned, configured, installed
cd ~/src/linux && make -j1 2>&1 | tail -40   # serial build: readable errors
```

A build failing at `-j32` with a garbled error is usually one real error buried
in parallel output. Rebuilding the failing part with `-j1` costs a minute and
gives you the actual message.
