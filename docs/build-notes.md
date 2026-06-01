# Build troubleshooting log

A running record of every non-obvious failure hit while building these boxes and
the fix, so each new box (and each rebuild) goes faster.  Append as you learn;
newest lessons at the bottom of each section.  Companion to `docs/field-manual.md`
(which explains the *architecture* — this file is the *gotchas*).

## Host reality (read first)

aarch64 Termux + unprivileged proot Debian. No KVM → QEMU emulates i386 via **TCG**;
every boot/install takes **minutes** — that's expected, not a hang. uid 1000, no
real root: `fakeroot apt-get install <pkg>` is how host tools got in (qemu,
genisoimage). **Cannot mount the guest qcow2 host-side** (no nbd/FUSE/mount.ufs,
proot can't mount) → all guest planting goes through the **tar-on-raw-disk channel**
+ serial-driven `drive_guest.py`.

## Process hygiene (bites every stage)

- **Reaping QEMU:** under proot, pexpect's child pid ≠ the real qemu pid, so
  `pexpect.close()`/`terminate()` LEAK qemu (it keeps the qcow2 lock and corrupts the
  next run). Reap with `pkill -9 -f <image-basename>` (full cmdline). `pkill <name>`
  fails — `comm` is truncated to 15 chars.
- **Counting qemu:** `pgrep -f box1-gaia.qcow2` also matches your own monitor/bash
  loops containing that string → false "still up". Count qemu specifically:
  `ps aux | grep qemu-system-i386 | grep -v grep | wc -l`.
- **Durable writes:** boot the guest with `cache=writethrough`. With writeback +
  SIGKILL, late writes are lost → `spwd.db` "Inappropriate file type or format",
  dirty fsck, non-booting disk. Always **clean-unmount before halt** in drivers
  (`sync; umount -a; mount -u -o ro /; sync; halt`).
- **Background wrappers under proot are unreliable for long/looping shells.** A
  backgrounded `{ … }` block — especially one containing an `until … sleep` loop —
  can get orphaned and **misreport its exit code** (seen: wrapper "exited 1" while
  the inner `make inject` kept running to success; and a continuation wrapper that
  died after its first `echo`). Lessons:
  - Run each **finite** step as its own foreground or `run_in_background` Bash call;
    don't chain snapshot→luks→package→solve inside one looping wrapper.
  - **Never** poll with an `until …; do sleep; done` loop inside a background Bash
    job here. If you must wait, gate on a **success marker** the guest wrote
    (`XDONE_0_X`) and check process state directly (`ps | grep qemu`).
  - After any "failed exit 1" on a long job, **verify reality** (is qemu/drive_*
    still running? did the image update? is the marker present?) before assuming it
    failed.

## Serial install / boot (2.2.8)

- `-machine pc,graphics=off` makes SeaBIOS mirror console+keyboard to COM1 (the
  modern sgabios replacement). At the `boot:` prompt send `-h` so the **kernel**
  also uses serial — but `-h` is a **toggle**; sending it twice flips serial back
  off. Persist it by writing `-h` to `/boot.config`.
- boot2 **drops the first character** of the boot command → send it char-by-char
  with ~60 ms gaps.
- Boot-manager menu: the arrow keys are eaten by libdialog's app-cursor mode →
  pick Standard MBR with the letter hotkey `s` + SPACE + CR (verify via MBR bytes).
- sysinstall menus: **select by numeric tag, not the name's first letter** (the
  button hotkeys are S=Select / E=Exit-install, so 'e' reboots you). Express = `6`.
  The distribution **checklist must settle (~3 s) before keystrokes** or they're
  dropped; SPACE toggles, CR confirms.
- Install media: emulated **ATAPI/IDE CD fails** ("no disc inside", `wcd`); use a
  **SCSI CD** (`-device lsi53c810` + `scsi-cd`, the `ncr` driver) for the ISO.

## Guest scripting (ash / 2.2.8 userland)

- 2.2.8 `/bin/sh` is **ash**: no working `command -v` → check the compiler by path
  (`/usr/bin/cc`). Host **py3.13 dropped `crypt`** → make `$1$` MD5 password hashes
  with `openssl passwd -1` on the host.
- Drivers must **`stty -echo` + use unique markers** (`echo XDONE_$?_X`) — otherwise
  the echoed command text is mistaken for command output (false success). When
  setting a prompt, the **PS1 string must not appear in an echoed command** (split
  `stty -echo` and `PS1='…'` into separate sends).
- Network knobs belong in **`/etc/rc.conf.local`** (sourced last by `/etc/rc.conf`),
  not `/etc/rc.conf` (defaults there are set earlier and win).
- Upstream archive TLS SAN is broken → fetch over **plain http://** from
  `ftp-archive.freebsd.org`; verify against per-set `CHECKSUM.MD5`.
- `mount_mfs` against the **active swap** device can transiently report "mfs
  filesystem not available" early in boot → **retry** the mount (gen-flag /
  tripwire both do). The console warning is harmless once the retry takes.

## Multi-box reuse (Box 2+)

- The pipeline is parameterized: set `BOX_ENV_FILE=box2.env` and
  `BOX_PAYLOAD_SUBDIR=payloads2` before sourcing `build/lib.sh` to build a different
  box on the same library. `flag.sh`/`70-luks`/`99-package` all follow.
- **`set -eu` + a var the new box.env forgot to define aborts the stage** (hit:
  `BOX_TRUST_USER: parameter not set`). When cloning a box config, grep the
  stage + guest scripts for every `$BOX_*` they read and make sure box2.env defines
  them.
- Box 2 **clones the Box 1 base image** (no reinstall). The new inject must
  **neutralise Box 1's vuln chain** (drop the `newgrp` setuid, dono `.rhosts`,
  `gen-flag` + its rc.local hook, the maniac loot, Box 1 breadcrumbs) so the
  intended Box-2 path is the only way. Keep accounts, inetd services, network, and
  the SunOS costume.
- **Trojaned `/usr/bin/login` risk:** replacing login also gates the *foothold*.
  The trojan must pass non-magic usernames through to the saved `login.real` so
  normal auth (and the player's telnet foothold) is untouched; watch tty/echo
  handling during the username read. (Verify the foothold still works in the solve
  before trusting it.)
