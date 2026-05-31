# SunOS 4.1.4 costume — what these files do (and don't)

These assets dress the FreeBSD box to *evoke* a 1995 SunOS 4.1.4 host. They are
**cosmetic** and are applied by `build/50-theme.sh` via the guest theme hook.
Disclosed in full in `docs/historicity.md`.

| Asset | Installed to | Effect | Real or costume? |
|-------|--------------|--------|------------------|
| `motd` | `/etc/motd` | SunOS banner shown after login | costume |
| `issue` | `/etc/issue` | SunOS pre-login line | costume |
| hostname `gaia` | `/etc/rc.conf`,`/etc/hostname` | prompt + `hostname` say gaia | costume |
| `/vmunix` symlink | `/vmunix -> /kernel` | SunOS-style kernel path/prop | costume (it's the FreeBSD kernel) |

**What stays truthful on purpose:** `uname -s`/`uname -m`, `dmesg`, and the boot
messages still say FreeBSD / i386. We do **not** patch the kernel to lie about
itself. Fingerprinting the real OS is intended, rewarded enumeration — see the
field manual's "banners lie" lesson.
