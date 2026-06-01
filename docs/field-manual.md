# Field manual — playing Box 1 "gaia"

Operator-facing notes: how to attack the box with period tools, the quirks of a
1990s BSD target, and a few build-internals worth knowing. **No spoilers here** —
the step-by-step solution lives in `docs/walkthrough.md` (spoiler-gated).

## Booting the box

```sh
make build      # one-time: deps → fetch → iso → install → inject → theme (SLOW)
./run.sh         # boot the finished box, host-only
```

`run.sh` boots the guest with QEMU user-mode networking and `restrict=on`: the
guest cannot reach the internet at all. Your only way in is the loopback ports it
forwards (defaults from `config/box.env`):

| You connect to (on the attacker host) | Reaches on the box | Service |
|---|---|---|
| `127.0.0.1:2323` | `:23`  | telnet (login) |
| `127.0.0.1:2121` | `:21`  | ftp (incl. anonymous) |
| `127.0.0.1:5514` | `:513` | rlogin / rsh |

The box's serial console + QEMU monitor are muxed onto the terminal that ran
`run.sh`; players don't need it (it's for the maintainer). `Ctrl-A C` reaches the
monitor, `quit` stops the VM.

## Period tools on a modern attacker box (Kali/Debian)

This box predates SSH. You attack it with the same clients a 1995 operator used.
On Kali/Debian:

```sh
sudo apt-get install telnet ftp rsh-client    # rsh-client provides rsh + rlogin
```

* **telnet** — `telnet 127.0.0.1 2323`
* **ftp** — `ftp 127.0.0.1 2121` (anonymous login works; watch the welcome banner)
* **rlogin** — `rlogin -l <user> <host>`; **rsh** — `rsh -l <user> <host> <cmd>`

  Note: r-tools traditionally call the privileged ports 512–514 and want to bind
  a reserved *source* port (hence setuid root on the client). With the forward on
  a high port (5514) the simplest path is to run the r-tools **from inside the
  box** once you have any shell there — exactly how a real operator pivoted. The
  walkthrough uses that route.

## "Banners lie" — don't trust the greeting

The box announces **SunOS 4.1.4 / Sun-4/SPARC**. It is FreeBSD 2.2.8 on i386 in a
SunOS costume (see `docs/historicity.md`). Treat the banner as untrusted: probe
behaviour, not labels. `uname -a` once you're on it tells the real story — which
is itself a worthwhile lesson about host fingerprinting.

## Quirks of a 1990s BSD target

* **Slow.** The guest is emulated i386 via QEMU TCG (no KVM on this aarch64
  host), so cold boots and the install take **minutes**. That is normal.
* **DES/MD5 passwords, short usernames, `.rhosts` trust** — all real for the era.
* **inetd-driven services.** telnet/ftp/rlogin/rsh/finger are launched by
  `inetd` from `/etc/inetd.conf`; if a service seems dead, that's where it lives.
* **r-services trust is a file, not a daemon setting.** A user's `~/.rhosts`
  (mode-restricted, owned by that user) decides who may log in *as them* with no
  password. This is the box's pivot; finding *whose* `.rhosts` trusts the world
  is the puzzle.

## Build internals (maintainer notes)

### Why the install is driven over serial
The installer (`build/drive_install.py`) automates FreeBSD's `sysinstall` over a
serial console with `pexpect`. The 2.2.8 boot blocks do console I/O through BIOS
int10h/int16h, so we launch QEMU with `-machine pc,graphics=off` — that makes
SeaBIOS mirror the console and keyboard to COM1 (the modern stand-in for the
removed `sgabios`), which carries the `boot:` prompt onto serial. We type `-h`
there so the kernel and sysinstall also use the serial line. Every byte is tee'd
to `work/install-serial.log` for debugging, because each boot cycle is slow.

### Why injection runs inside the guest
This build host is an unprivileged proot and **cannot mount the guest's UFS**
(no `/dev/nbd`, no `mount_ufs`, no FUSE). So payloads are not injected from the
host. Instead `build/40-inject.sh` stages everything into a **tar**, attaches
that tar to the guest as a **raw second disk** (guest `wd1`), and
`build/drive_guest.py` logs in as root over serial and runs `tar xpf /dev/rwd1`
— the raw disk *is* the archive. `inject-guest.sh` then does the real planting
from inside, where it has a working FreeBSD `cc`, `pwd_mkdb`, etc. The theme
stage (`50-theme.sh`) uses the same channel.

### One knob file
Everything tunable — accounts, passwords, flag, ports, OS version — lives in
`config/box.env`. No other script hard-codes them; retarget the build there.

### Archive over plain HTTP
`build/10-fetch-media.sh` fetches from `ftp-archive.freebsd.org` over **http://**
because the archive's TLS certificate SAN does not match its hostname. Integrity
does not depend on the transport: every byte is verified against the release's
own `CHECKSUM.MD5`.
