# Berkeley Underground — a mid-90s BSD intrusion CTF series

> A hands-on lab series teaching **authentic mid-1990s UNIX intrusion tradecraft**:
> the r-services trust model, `.rhosts` abuse, setuid privilege escalation, and
> source-theft exfiltration — the techniques actually used against The WELL,
> Internex, Colorado SuperNet, Motorola, and others during the Feb 1995
> Kevin Mitnick intrusion sessions.
>
> Every vulnerability here is **real and unmodified**. You are not solving a
> puzzle box; you are using the same techniques an intruder used in 1995, on an
> operating system close enough to the originals that they transfer verbatim.

**Honest framing (read before you boot).** The *techniques* here are real and drawn
from the 1995 sessions, but the *path* is distilled — a single signposted host, not
the dozens-of-systems, days-long, social-engineering-driven intrusion the originals
were. Treat this as an authentic introduction to the era's trust-model tradecraft,
not a reenactment; what's stripped here — multi-host pivoting, anti-forensics, and
the human layer that made Mitnick *Mitnick* — is documented in
[`docs/historicity.md`](docs/historicity.md) and restored by later boxes one rung at
a time.

> 📜 **Read before you boot:** [`docs/primer.md`](docs/primer.md) — *Ghosts in the
> Wires*, a historical primer on the February 1995 sessions this box distills, the
> human layer the evidence can't show, and the still-contested story of the man at
> the centre of it. *In memory of Kevin Mitnick (1963–2023).*

This repository is the **build pipeline** for the series. It downloads a
legally-redistributable BSD, installs it under QEMU, injects period-authentic
weaknesses offline, applies a (clearly disclosed) cosmetic SunOS theme, and
emits a runnable, **host-only** virtual machine plus a launch script.

---

## The series — a 4-box spine

Four boxes, each teaching **one** distinct technique from the Feb 1995 sessions,
each a self-contained **host-only boot2root VM**. Boxes 1–3 are built and
**ship-tested end-to-end**; Box 4 is in progress.

| # | Box | Teaches | Grounded in | Status |
|---|-----|---------|-------------|--------|
| **1** | `gaia` — the break-in | r-services trust (`.rhosts "+ +"`) + setuid `newgrp` → source exfil | 4003 / 4007 / 4014 | ✅ built + ship-tested |
| **2** | `teal` — *The Traced Call* | **anti-forensics**: scrub `wtmp`/`utmp`/`lastlog` + accounting logs to release the flag | 4005 / 4016 | ✅ built + ship-tested |
| **3** | `escape` — the pivot | **credential harvest + reuse**: read the intruder's sniffer log, reuse the admin's password → root | 4015 / 4019 | ✅ built + ship-tested |
| **4** | `well` — the backdoor | **persistence**: find the intruder's `in.pmd` inetd backdoor and knock → root | 4007 / 4008 | 🔨 building |

Every box after the first **clones the proven Box 1 base image** (no reinstall) and
is built / solved / packaged through the same parameterised pipeline. Per-box flags
are derived from a secret seed and **materialised in RAM** (no plaintext flag on
disk); each distributable is **LUKS-encrypted at rest**. Design docs:
[`docs/box2-design.md`](docs/box2-design.md),
[`box3-design.md`](docs/box3-design.md), [`box4-design.md`](docs/box4-design.md);
build them with `make box2-dist` / `box3-dist` / `box4-dist`, and prove a shipped
bundle solves on a clean host with `make box2-shiptest` (etc.).

---

## Box 1 — "gaia": the break-in  ✅ built + ship-tested

| | |
|---|---|
| **Base OS** | FreeBSD 2.2.8-RELEASE (i386) under QEMU — *4.x fallback documented* |
| **Theme** | SunOS 4.1.4 costume (cosmetic, fully disclosed — see below) |
| **Difficulty** | Authentic environment, beginner-accessible via in-box breadcrumbs |
| **Networking** | **Host-only / internal — REQUIRED. No internet needed to solve.** |
| **Win condition** | Exfiltrate the planted "stolen source" tarball off the box; the flag is *inside* the tarball (possession-after-transfer proves exfil) |

### The intended path

Each stage reproduces a technique observed in the sealed Mitnick session
evidence (citations are to the session IDs reconstructed in
[`~/takedown/TIMELINE.md`](../takedown/TIMELINE.md), referenced read-only):

1. **Foothold** — log in to a low-privilege era account (clue is findable in-box).
2. **Discover the `.rhosts` "+ +" trust** — an admin's shell history shows an
   `rsh` to a "trusted" host. The `+ +` wildcard genuinely grants anyone access.
   *(cf. sessions 4003, 4023 — planted `.rhosts` `+ +` on jlittman/markoff)*
3. **r-services lateral move** — `rlogin`/`rsh` across that trust to a more
   privileged account. *(cf. 4016 `rsh teal`, 4019 `rsh wet`)*
4. **setuid privilege escalation** — a planted setuid-root `newgrp` trojan
   escalates to root, exactly as `newgrp -hack root` did in the sessions.
   *(cf. 4001, 4007)*
5. **root → exfiltrate** — locate the planted stolen-source tarball and **FTP it
   off the box to your own attacking host**, mirroring the theft of the Motorola
   MANIAC firewall source. The flag is inside the tarball.
   *(cf. 4014, 4017)*

The hints **point at the technique**; you still execute it. Nothing is
auto-solved.

---

## Honest framing: FreeBSD wearing a SunOS costume

**This box runs a FreeBSD kernel. It is not, and never claims to be, SunOS.**

- **What is real (not costume):** the BSD **trust surface** is genuinely shared
  heritage. SunOS 4.1.x descends from Berkeley's 4.2/4.3BSD; FreeBSD 2.2.x
  descends from 4.4BSD-Lite — siblings off the same CSRG family tree. The
  r-services (`rlogin`/`rsh`/`rcmd`), the `.rhosts`/`hosts.equiv` trust model,
  the setuid security model, and the BSD networking stack behave the **same way**
  here as they did on a 1995 SunOS host. The techniques in this box are not
  simulated — they are the actual mechanisms.

- **What is costume (cosmetic, disclosed):** the login banner, `/etc/motd`,
  `/etc/issue`, the hostname, era account names, some SunOS-flavored paths, and a
  `/vmunix` prop are dressed to *evoke* a 1995 Sun/Motorola environment. They are
  set dressing, not the kernel.

**"Banners lie."** If you run `uname -m`, read the boot messages, or otherwise
fingerprint the real operating system, you will discover FreeBSD underneath.
That is **correct enumeration**, not a broken box — distrusting a banner is a
core security lesson, and this box rewards it. See
[`docs/field-manual.md`](docs/field-manual.md) and
[`docs/historicity.md`](docs/historicity.md) for the full disclosure of what is
real vs. what is theater.

---

## Quick start (player)

```sh
# 1. Build the box (slow on non-x86 hosts — see note below)
make build

# 2. Launch it (host-only networking, no internet)
./run.sh

# 3. From your attacking host (e.g. Kali) on the same host-only network,
#    follow your nose. The field manual covers period r-tools on modern Linux.
```

> **Performance note.** This pipeline was developed on an **ARM host emulating
> x86 with no hardware acceleration** (pure TCG). Boots and the install take
> *minutes*, not seconds. That is expected and documented. On an x86 host with
> KVM it is fast.

See [`docs/field-manual.md`](docs/field-manual.md) for the operator's guide
(period `rsh`/`rlogin`/`ftp` clients on modern Kali, the boot quirks, the
"banners lie" note) and [`docs/walkthrough.md`](docs/walkthrough.md) for the
**spoiler-gated** full solution.

---

## Series purpose

Modern security training drills modern bugs. This series fills a gap: the
*foundational* UNIX attack techniques — trust relationships, setuid, plaintext
r-services, **credential sniffing + reuse, log tampering / anti-forensics, and
persistence backdoors** — that defined an era and still underpin how we reason
about lateral movement and privilege escalation today. The 4-box spine teaches them
one technique at a time, on hardware-honest period software, grounded in real
forensic evidence rather than invented lore.

## Safety & ethics

This is a **vulnerable-by-design lab, never hostile-by-design.** Every box runs
**host-only** (no route to the internet — `run.sh`/`play.sh` enforce it), ships only
**throwaway lab passwords** (never real credentials or keys), and is reachable only
from `127.0.0.1` on the machine you launch it on. The weaknesses are **real** — by
Box 4 that includes a genuine live backdoor service — but they are *real and
contained*: a vulnerable VM you own and control, exactly like any boot2root lab.
Full safety model: [`docs/historicity.md`](docs/historicity.md) § Safety.
Provenance & licensing: [`PROVENANCE.md`](PROVENANCE.md).

## Repository layout

```
build/         the reproducible pipeline (fetch → install → inject → theme → emit)
  payloads/    Box 1 planted files (vulns, breadcrumbs, loot, theme)
  payloads2..4/ per-box planted files (each box's inject + solver payloads)
  new-box.sh   scaffold a new box from templates/ (config + inject + stage)
config/        box parameters — box.env (Box 1) + box2/box3/box4.env
templates/     skeletons new-box.sh fills in for the next box
docs/          historicity, primer, field-manual, build-notes (troubleshooting),
               per-box design docs, spoiler-gated walkthrough
run.sh         launch the built box, host-only
media/         downloaded BSD install media          (gitignored)
dist/          emitted images + release/ bundles + tarballs (gitignored)
```
