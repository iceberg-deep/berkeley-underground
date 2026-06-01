# Historicity — what's real, what's a costume, and why

Box 1 ("gaia") is a teaching reconstruction of a mid-1990s BSD intrusion. Every
weakness it ships is a *real* weakness of that era's Unix; the 1995-specific
details are modelled on a documented case. This file says exactly which parts are
historical, which are reproductions, and which are theatre — so nobody mistakes
the costume for the kernel.

## On historical fidelity — what this box is, and what it isn't

This box teaches techniques that are genuinely present in the captured 1995
sessions — `.rhosts`/r-services trust abuse and trojaned-`newgrp` privilege
escalation are the real mechanisms documented in `TIMELINE.md` (see sessions
4003, 4007, 4023). What has been *simplified* is the path, not the techniques. The
real intrusion was not a single host solved in one sitting: it chained across
dozens of systems over days (Netcom → the WELL → Internex → escape.com → Motorola
→ fish.com → CSN and beyond), with constant log-wiping, timestamp forgery, and
administrator-watching between every step. Here, those techniques are distilled
onto one host with a linear, signposted path so the mechanics can be learned in
isolation. Two things in particular are deliberately absent. First, the foothold:
this box hands you a starting point, whereas the real initial access came from
stolen accounts and groundwork that predate the captured sessions entirely.
Second, and more importantly, the human layer: Mitnick's defining method was
social engineering — pretexting and manipulating people out of credentials and
access — and the captured sessions are only the *technical residue* of an attack
built on that foundation. No boot2root can teach the part that made him Mitnick.
So treat this box as an authentic introduction to the *trust-model tradecraft* of
the era, not a reenactment of the attack. The full scope is documented in
`TIMELINE.md`, and later boxes in this series restore the layers stripped here —
multi-host pivoting, persistence and anti-forensics — one rung at a time.

## Source

The scenario is grounded in the session-by-session playback in
`~/takedown/TIMELINE.md` (read-only in this project; we cite it, we never edit
it). Citations below are to that file's session IDs (`evidence_sessions/40xx`).

## Element-by-element provenance

| CTF element on the box | Modelled on (TIMELINE session) | Real / Reproduction / Costume |
|---|---|---|
| Host named **gaia.internex.net**, contractor **brian** (uid 104) | 4006, 4007 — attacker operating on `gaia.internex.net` as `brian` uid 104 | Costume (names/identity); the account itself is real and unprivileged |
| Departed sysadmin **pei**, account-handover breadcrumb | 4006/4007 staging on gaia | Reproduction (the breadcrumb is written for the lab) |
| **`.rhosts "+ +"`** trust on `dono` → password-free rlogin/rsh | 4001 `dono` foothold; 4003 planted `.rhosts`; 4023 backdooring an account with `+ +` | **Real** vulnerability — BSD r-services honour the file exactly as 1995 did |
| **setuid-root trojaned `newgrp -hack root`** → root shell | 4001 root via `newgrp`; 4007 backdated/`chmod 4755` trojan | **Real** escalation (genuine setuid-root binary); the *specific* `-hack` trojan is a from-scratch reproduction, not a recovered binary |
| Planted **"stolen firewall source"** loot tarball = the objective | 4014 theft of the **MANIAC** firewall source from Motorola (`spsgate.sps.mot.com`); 4017 exfil | Reproduction (the source is invented; the *act* — steal-and-exfil — is the modelled objective) |
| Win = **possession after transfer** (FTP the tarball off-box) | 4014/4017 exfil to escape.com / Netcom | Faithful to the case: proof was possession, not any box-side "detection" |
| Inert **`in.pmd`** artifact, port-5553-style backdoor lore | 4007 port-5553 backdoor; 4023 probing it | Reproduction, deliberately **inert** (red herring; not wired to inetd) |
| Banners announcing **"SunOS Release 4.1.4"** | The era's Internex/Sun-4 environment | **Costume** — see "banners lie" below |

Elements from the timeline we intentionally did **not** reproduce (out of scope
for Box 1, may appear later in the series): the SATAN theft (4019), the NIT
sniffer / traced-call mechanics (4016), and the mail-forgery against journalists
(4003/4011). They are real history; they're just not this box's lesson.

## "Banners lie" — the SunOS costume over a FreeBSD kernel

The box greets you as **SunOS 4.1.4 on a Sun-4/SPARC**. It is not. It is
**FreeBSD 2.2.8 on emulated i386**. The SunOS identity is purely cosmetic
(`/etc/motd`, `/etc/issue`, hostname, a `/vmunix → /kernel` symlink) and is
disclosed on purpose, because *reading a banner is not fingerprinting a host* —
a lesson worth teaching directly. `uname`, the kernel, the r-tools and telnetd
all behave as FreeBSD/4.4BSD-lineage, and the intended attack path depends only
on behaviours common to that whole BSD family.

## OS-version decision — why FreeBSD 2.2.8 stands in for SunOS 4.1.4

We cannot redistribute SunOS 4.1.4: it is proprietary Sun/Oracle software with no
redistribution licence. We need a *freely redistributable* operating system from
the same 4.3/4.4BSD lineage whose r-services, setuid semantics, and inetd-driven
network services match the period. **FreeBSD 2.2.8 (1998)** is the closest such
cousin that still installs and boots under a current QEMU:

* It is a direct 4.4BSD-Lite descendant — same `rlogind`/`rshd`/`.rhosts` trust
  model, same setuid-root escalation surface, same `inetd.conf` service set.
* It is openly redistributable (BSD licence; mirrored on the FreeBSD archive).
* The era is right (telnet/r-services-first, pre-SSH, MD5-or-DES `master.passwd`).

The build is parameterised (`config/box.env: BOX_OS_VERSION`) and can target
FreeBSD **4.11** instead if a 2.2.8 install proves too fragile under TCG; the
pipeline handles both media layouts. The choice does not change any lesson —
both are BSD cousins wearing the same SunOS costume.

## Safety / ethics

* **Throwaway lab credentials only.** Every password in `config/box.env`
  (`newriver`, `changeme`, `toor1995`, …) is invented for this lab. None is a
  real credential from the case or anywhere else.
* **Host-only by construction.** `run.sh` boots the guest with QEMU user-mode
  networking and `restrict=on` — the guest has *no route or DNS to the
  internet*. The only ingress is host-forwarded period-service ports on
  `127.0.0.1`. A deliberately-vulnerable 1990s box never touches a real network.
* **No working offensive tooling is shipped against third parties.** The
  weaknesses live entirely inside this disposable VM; the "loot" is invented
  source whose only payload is the flag.
* **The history is cited, not sensationalised.** This is a defensive teaching
  artifact: it shows *why* trust-based r-services + setuid trojans owned boxes in
  1995, so the same mistakes are recognisable today.
