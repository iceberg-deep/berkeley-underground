# Box 3 — "the pivot" (design blueprint)

Status: DESIGN. Box 3 reuses the proven pipeline; clones the Box 1 base image like
Box 2. Grounded in `~/takedown/TIMELINE.md` (cite session IDs; do NOT modify it).

## One-line

Foothold on a busy shell host, **sniff** the sysadmin's cleartext password off the
wire with `tcpdump`, then **reuse** it to reach root. Faithful to **4015** (the NIT
packet-sniffer kernel on CSN), **4019** (harvest creds), **4001** (the sniffer
toolkit cache), and the fact the case evidence itself was *modified-tcpdump logs*.

## What it teaches (the rung after Box 2)

Box 1 = the break-in, Box 2 = the cover-up, **Box 3 = credential interception +
reuse**:
- 1990s admin protocols (telnet/FTP/rlogin) send passwords in **cleartext**.
- a packet sniffer (`tcpdump`/BPF — the modern FreeBSD stand-in for SunOS NIT)
  reads them straight off the wire.
- **password reuse** — the sysadmin's account password is also the root password.

## Topology

Single SunOS-costumed host (`escape.com`), cloned from the Box 1 base. The "other
users" whose traffic you sniff are simulated by a cron job; no second guest.

## Kill chain

1. **Foothold** — telnet `brian`/`newriver` (carried over).
2. **Enumerate** — a prior intruder's cache (notes + sniffer) shows `/dev/bpf0` was
   left world-readable, and that the operator `ops` runs an automated FTP job.
3. **Sniff** — `tcpdump -i lo0 -A port 21` captures the `ops` FTP login
   (`USER ops` / `PASS …`) in cleartext as the cron job runs (≤1 min).
4. **Reuse** — `su ops` (its password), then `su root` (**same** password; `ops` is
   in `wheel`) → uid 0.
5. **Flag** — read the off-disk flag (root-only, materialised in RAM at boot).

## ⚠️ Mechanic decision: found capture log, not live capture (verified)

An early feasibility probe (`build/drive_bpftest.py`) proved **live sniffing is
infeasible** here: the 2.2.8 GENERIC kernel has **no BPF** (`/dev/bpf0` →
`Device not configured`), and QEMU host-only net has no shared segment anyway (see
`docs/build-notes.md`). Recompiling a BPF kernel isn't worth it. So Box 3 uses the
**found-log** mechanic — faithful, since the actual takedown evidence was the
intruder's *modified-tcpdump logs*, and Shimomura's break in the case came from
finding those capture logs.

## The mechanic (found capture log + real reuse)

- **The capture log:** the inject plants the prior intruder's `sunsniffer` output
  — a realistic capture log (first ~128 bytes of telnet/ftp/rlogin sessions, the
  classic sunsniffer format) in the toolkit cache, **world-readable**. Among the
  captured sessions is the operator `ops` logging in with `PASS <ops-pw>` in
  cleartext. The capture is presented honestly as the intruder's past sniffing on
  the period shared-Ethernet (not replicable on one NAT'd host).
- **Real weaknesses (not staged):** the harvested credential is a *valid* login,
  and **`ops` (uid 106, group `wheel`) and `root` share the password** — real,
  exploitable misconfigurations. The player must enumerate to find the log, read
  the sunsniffer format, and realise the reuse.
- **Escalation:** `su ops` (the captured password) → `su root` (same password;
  `ops` is in `wheel`) → uid 0.
- **Flag:** reuse Box 1's off-disk machinery (`/etc/.fb` reversed → `gen-flag.sh`
  MFS overlay at boot, boot-gated). Decoy on the persistent disk; LUKS at rest.
- The real `sunsniffer.c` source ships in the cache as period flavour (cf 4001),
  with a note that the live sniffer needed the era's shared Ethernet.

### Anti-cheese / hardening

- The `ops` password is only ever on the wire + in the cron script (root-only,
  600) — never in a world-readable file, so it must be sniffed (or you root the
  box another way first, which is the point).
- Real flag off-disk (MFS), decoy on disk, LUKS at rest — same posture as Box 1/2.

## Build architecture — reuse

Clone `dist/box1-gaia.built.qcow2` → `dist/box3-escape.qcow2`; `inject3-guest.sh`
neutralises Box 1's chain (newgrp setuid, dono `.rhosts`, maniac loot) and plants:
`ops` (wheel, uid 0-share-pw), the cron FTP job + `ops-login.sh`, the loosened
`/dev/bpf0`, the toolkit-cache breadcrumb, `/etc/.fb` + `gen-flag.sh`. Everything
else (LUKS, package, ship-test) reuses the Box 2 parameterised pipeline
(`BOX_ENV_FILE=box3.env`, `BOX_README=mk-player-readme3.sh`,
`BOX_SOLVE_DRIVER=drive_solve3.py`).

## Risks to verify early (per build-notes)

- Does `tcpdump -i lo0` capture localhost FTP on 2.2.8? (loopback BPF.)
- Does `chmod 0666 /dev/bpf0` persist (static /dev) and let the foothold sniff?
- Does the cron `ftp -n localhost` reliably generate the cleartext PASS?
- `su ops` (non-root, no wheel needed) then `su root` (wheel + reuse) both work?

## Open questions

1. Capture in the solver: background `tcpdump -w` + sleep + kill, vs `tcpdump -c N`.
2. Whether to also expose a readable `master.passwd` backup (4019 hash-harvest) as
   an alternate path — keep Box 3 focused on sniffing for now.
