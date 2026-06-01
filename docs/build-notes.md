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
  (`/usr/bin/cc`).
- **ash `!` negation is positional.** `if ! cmd; then` works, but `!` as the right
  operand of `||`/`&&` is a **parse error** (`expr || ! grep …` → "! unexpected").
  Because ash parses an `if … fi` block before running it, one bad `|| !` anywhere
  in a not-even-taken branch crashes the **whole script** at load (symptom: a cron
  job that silently never runs, no log). Use an explicit flag (`grep -q … && f=no`)
  instead of `|| ! grep`. `[ ! -f x ]` (test's own negation) is fine — that's
  `test`, not the shell. Lint guest scripts: `grep -nE '\|\| *!|&& *!'`. Host **py3.13 dropped `crypt`** → make `$1$` MD5 password hashes
  with `openssl passwd -1` on the host.
- **root's login shell is `/bin/csh`** (FreeBSD default), not sh. A sentinel helper
  built on `echo X_$?_X` silently breaks after `su` to root — csh has no `$?` (it's
  `$status`), so the marker never matches and the driver times out *after* a
  confirmed uid=0 (a plain `echo MARKER` still works, which is why the uid check
  passes but the next command hangs). After `su`/`su root`, send `/bin/sh` to drop
  into sh before using `$?`-based sentinels. (ops/brian shells were set to /bin/sh,
  so only the root level bit.)
- Drivers must **`stty -echo` + use unique markers** (`echo XDONE_$?_X`) — otherwise
  the echoed command text is mistaken for command output (false success). When
  setting a prompt, the **PS1 string must not appear in an echoed command** (split
  `stty -echo` and `PS1='…'` into separate sends).
- Network knobs belong in **`/etc/rc.conf.local`** (sourced last by `/etc/rc.conf`),
  not `/etc/rc.conf` (defaults there are set earlier and win).
- **A persistent background loop does NOT survive `/etc/rc.local`.** `rc` SIGHUPs
  its backgrounded children when it exits, so `( while :; do …; sleep N; done ) &`
  from rc.local dies immediately (symptom: the watcher never runs, no log, the
  pre-seeded decoy persists forever). A **one-shot** (Box 1's `gen-flag.sh`)
  survives because it finishes before `rc` exits. For a periodic task use **cron**
  (a standard daemon): `* * * * * root /usr/local/sbin/watcher.sh args` in
  `/etc/crontab`. Cron runs with a **minimal PATH** — set `PATH=/bin:/usr/bin:/sbin:
  /usr/sbin` at the top of the script, or its `last`/`who`/`mount_mfs` calls fail
  silently.
- Upstream archive TLS SAN is broken → fetch over **plain http://** from
  `ftp-archive.freebsd.org`; verify against per-set `CHECKSUM.MD5`.
- **No live packet sniffing — the 2.2.8 GENERIC kernel has no BPF.** `tcpdump` ships
  (`/usr/sbin/tcpdump`) and `/dev/bpf0` exists, but opening it returns `Device not
  configured` (ENXIO): the Minimal-install GENERIC kernel was built without
  `pseudo-device bpfilter`. There is no runtime fix (no loadable bpf module in
  2.2.8); enabling it needs a full kernel recompile (src dist + hours under TCG).
  Also note: under QEMU host-only user-net there's only one NAT'd interface and no
  shared segment, and self-traffic to the box's own IP routes via lo0 — so even
  with BPF you'd only see loopback. **Lesson:** a sniffer-themed box must use a
  *found capture log* (faithful — the case evidence was "modified-tcpdump logs"),
  not live capture. (`tcpdump -s 0` is also invalid on this old tcpdump — use a
  real snaplen like `-s 1514`; it likely lacks `-A`, so read pcaps with `strings`.)
- `mount_mfs` against the **active swap** device can transiently report "mfs
  filesystem not available" early in boot → **retry** the mount (gen-flag /
  tripwire both do). The console warning is harmless once the retry takes.

## Box 1 — proven recipes (what actually worked)

The exact, working solutions, so they survive outside any one person's head. The
canonical form is the committed scripts; these are the bits that took the most
tries to get right.

**Install QEMU invocation** (`build/drive_install.py`) — SCSI CD for the ISO, serial
console, durable writes:
```
qemu-system-i386 -machine pc,graphics=off -cpu pentium -m 128 \
  -drive file=box1-gaia.qcow2,format=qcow2,if=ide,index=0,media=disk,cache=writethrough \
  -drive file=boot.flp,format=raw,if=floppy,unit=0,readonly=on \
  -device lsi53c810,id=scsi0 \
  -drive id=cd0,file=install.iso,format=raw,if=none,media=cdrom,readonly=on \
  -device scsi-cd,bus=scsi0.0,drive=cd0 \
  -boot a -nographic -serial stdio
```
Run `INSTALL_CACHE=writethrough` (durable across the post-extract SIGKILL).

**sysinstall sequence over serial** (numeric tags, not name letters):
boot floppy → `boot:` send `-h` (char-by-char) → UserConfig `config>` send `quit`
→ terminal type `2` (VT100) → main menu `6` (Express) → FDISK `A` (whole disk) →
"true partition entry?" CR (Yes) → `Q` → Boot Manager radiolist: `s` (Standard) +
SPACE + CR → Disklabel `A` (auto) → `Q` → Distributions checklist *(let settle ~3 s)*
→ `6` (Minimal) + SPACE + CR → Media `1` (CDROM) → "Last Chance" CR (Yes) → extract.

**Finalize to a serial-login box** (`drive_install.py` finalize_phase): boot wd0
single-user (`boot:` `-h -s`) → `fsck -y` → `mount -u -o rw /` → `mount -a` →
interactive `passwd` root → sed `/etc/ttys` `ttyd0` → `"on secure" vt100 std.9600`
→ `echo -h > /boot.config` → clean halt.

**Durable guest writes** (every driver): `cache=writethrough` on the qcow2 drive +
clean unmount before halt (`cd /; sync; umount -a; mount -u -o ro /; sync; halt`).
This was THE root cause of most "mystery" failures (lost `spwd.db` → inetd "No such
user root" → ports closed; lost `/kernel` → boot2 "Invalid format!" loop).

**Boot the finished box / distributable** (`run.sh`, `drive_solve.py`): IDE disk,
`-machine pc,graphics=off`, host-only user-net with `restrict=on` +
`hostfwd=tcp:127.0.0.1:2323-:23` (telnet) etc. For the LUKS image add
`-object secret,id=sec0,file=<key>` and `,encrypt.key-secret=sec0` on the drive.

**Off-disk flag** (`build/payloads/gen-flag.sh`, hooked from `/etc/rc.local`): bake
only the DECOY into the on-disk loot; store the real flag REVERSED in root-only
`/etc/.fb` (no literal `BU{` to grep); at boot `mount_mfs -s 4096 /dev/wd0s1b` over
the loot dir and write the real flag there (RAM only). Powered-off disk → decoy.

**LUKS at rest** (`build/70-luks.sh`): `qemu-img convert -O qcow2 -o
encrypt.format=luks,encrypt.key-secret=sec0 plain.qcow2 enc.qcow2` with `-object
secret,id=sec0,file=<key>`. Verify it's opaque offline: `qemu-img convert -O raw
enc.qcow2 /dev/null` WITHOUT the key must fail.

**Solve gate** (`build/drive_solve.py`): walk the chain over telnet; the flag
materialises a beat after telnetd (gen-flag runs at boot) so **retry the flag read
until it differs from the decoy**. `BOX_NO_BOOT=1` drives an already-running box
(used by the ship test).

**Ship test** (`build/98-shiptest.sh`): extract the release tarball to a clean dir
OUTSIDE the repo, `sha256sum -c`, boot via the bundled `play.sh`, solve it — proves
the *shipped* artifact works, not just the build tree.

**Iteration tip:** the solve SIGKILLs and dirties the working qcow2 — keep a clean
snapshot (`dist/box1-gaia.built.qcow2`) and restore it before each guest run.

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
  - **Gotcha hit:** telnetd execs `login -h <host> -p`. A naive "first argv not
    starting with `-` is the username" loop grabs the `-h` **value** (the hostname)
    as the username and breaks every telnet login (symptom: telnet shows a banner
    then `Password:` for a bogus user; serial getty still works because getty
    passes no `-h`). Fix: skip `-h`/`-f` **and the argument that follows them**.
    Always solve-test the foothold *through telnet*, not just the serial console.
- **Log-condition gating — don't verify lastlog with `lastlogin`.** `lastlogin
  <user>` prints the username in its output *even for a zeroed/never record*, so a
  `lastlogin user | grep -q user` "is the trace gone?" check is **always true** and
  the gate never opens (symptom: solve scrubs everything — last/who/acct all 0 —
  but the watcher keeps serving the decoy). Gate on `last`/`who`/the accounting log
  (username-based, reliable). Make the gating script **log its `why`** so a stuck
  gate is one `cat /root/.tripwire.log` away.
