# SunOS 4.1.4 costume — what these files do (and don't)

These assets dress the FreeBSD box to *evoke* a 1995 SunOS 4.1.4 host. They are
**cosmetic** and are applied by `build/50-theme.sh` via the guest theme hook.
Disclosed in full in `docs/historicity.md`.

| Asset | Installed to | Effect | Real or costume? |
|-------|--------------|--------|------------------|
| `motd` | `/etc/motd` | SunOS 4.1.4 banner + honest CTF disclosure, shown after login | costume + disclosure |
| `issue` | `/etc/issue` | SunOS pre-login line (serial getty / telnetd) | costume |
| hostname `gaia` | `/etc/rc.conf`,`/etc/hostname` | prompt + `hostname` say gaia | costume |
| `/vmunix` symlink | `/vmunix -> /kernel` | SunOS-style kernel path | costume (it's the FreeBSD kernel) |

**The disclosure is intentional and player-visible.** The `motd` states, out of
character, that the box is FreeBSD 2.2.8 retrofitted to present as SunOS 4.1.4
(genuine SunOS isn't redistributable; a 4.3BSD-lineage cousin keeps the 1995
r-services + setuid lessons authentic). The owner cheat-sheet and challenge
description repeat this. The goal isn't to fool players into thinking it's real
SunOS — it's period-authentic dressing over a redistributable cousin.

**What stays truthful on purpose:** `uname -s`/`uname -m`, `dmesg`, the telnet
pre-login banner, and the boot messages still say FreeBSD / i386. We do **not**
patch the kernel or `login`/`telnetd` to lie about the OS. The costume is the
banners and hostname; the kernel tells the truth and the vulnerabilities are
real. (See the field manual's "banners lie" lesson and `docs/historicity.md`.)
