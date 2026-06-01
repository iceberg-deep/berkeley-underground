# Box 2 — "The Traced Call" (design blueprint)

Status: DESIGN. Box 1 (`gaia`) is done/publish-ready; Box 2 builds on its proven
pipeline. Grounded in `~/takedown/TIMELINE.md` (read-only; cite session IDs).

## One-line

Root the box, then **don't get caught**: a watchful sysadmin reviews the login and
billing logs on a timer — the flag is released only once you've scrubbed every
trace of your intrusion. Faithful to sessions **4001 / 4005 / 4016** (zap the
records, `grep -v` the accounting logs, *"scrub reboot logs — the traced call"*).

## What it teaches (the next rung after Box 1)

Box 1 taught the break-in (trust + setuid). Box 2 teaches the **cover-up** — the
skill the captured sessions spend the most keystrokes on and almost no CTF rewards:
- `wtmp` / `utmp` / `lastlog` are append-only binary logs you must *edit*, not
  delete (deleting them is itself a red flag).
- wiping your **own active** session while still logged in.
- host-specific **accounting / billing** logs (`awtmp`, `awtmp.sessions`) scrubbed
  with `grep -v <user>` + `mv` (4005/4007 verbatim).
- doing it before the admin's next review sweep.

## Topology

Single SunOS-costumed host (default). Anti-forensics is local to the rooted host,
so one guest suffices; the upstream pivot stays backstory ("you came in from
`gaia`"). Promotable later to a true 2-host host-only QEMU vlan if we want the
pivot enacted.

## Kill chain

1. **Foothold** — same era as Box 1 (telnet/r-services). The foothold login is the
   trace the player must later erase, so it is deliberately *recorded everywhere*.
2. **Escalate to root** — a fresh period vector (candidates: trojaned `/bin/login`
   blank-login → root, cf 4015/4016; or a port-3111 backdoor shell, cf 4011). Pick
   one distinct from Box 1's `newgrp` so the series doesn't repeat itself.
3. **Discover the watcher** — breadcrumbs: a sysadmin `~/.plan` / motd / a cron
   comment warning that `last` + the billing logs are reviewed; the decoy flag text
   spells out the condition.
4. **Find the toolkit** — a cached attacker kit (cf 4001's `dono` cache):
   `zap.c` / `cloak.c` (utmp/wtmp/lastlog wipers) the player compiles & runs.
5. **Cover tracks** — remove the foothold user's entries from `wtmp`, `utmp`,
   `lastlog`, and scrub the accounting logs.
6. **Flag releases** — once the next watcher sweep finds the logs clean, the real
   flag materialises (off-disk, RAM/MFS); until then a decoy.

## The gating mechanic (the novel core)

Reuse Box 1's off-disk flag machinery, but **condition-gate** it instead of
boot-gate it.

- The real flag is stored obfuscated + root-only at `/etc/.fb` (reversed; no
  literal `BU{` to grep), exactly as Box 1.
- A root **trip-wire** runs on a timer (cron every minute, or a small daemon). Each
  sweep it scans `wtmp` / `utmp` / `lastlog` / the accounting logs for the
  **intruder signature** (the foothold username, and/or the planted source host).
  - **Traces present** → ensure only the DECOY is in the loot/trophy location.
    (Decoy text: *"Your session was logged — `last` shows it. The call was traced.
    Scrub wtmp/utmp/lastlog and the accounting logs."*)
  - **Traces absent** → materialise the REAL flag into a RAM (MFS) overlay (the
    Box 1 `gen-flag.sh` mount path, retried), then stop re-arming.
- So the flag literally appears the sweep after the player goes clean. A `make
  solve` automates: foothold → root → compile+run zap → scrub accounting → poll the
  trophy until it flips from decoy to real (mirrors Box 1's flag-retry loop).

Determinism: flag = `BU{ md5(seed+instance)[:16] _ suffix }` (shared `build/flag.sh`,
new `BOX_FLAG_INSTANCE`/`BOX_FLAG_SUFFIX`). Seed stays owner-side; never in image.

### Anti-cheese

- Trip-wire keys on **specific** intruder entries, not "is wtmp smaller" — so
  truncating/deleting the whole log doesn't pass (and a *second* check can flag a
  suspiciously empty/zeroed log as "tampered → traced", rewarding surgical edits
  over `rm`, the historically correct move).
- Real flag never on the persistent disk (off-disk/MFS), so offline mount/grep of
  the decrypted image yields only the decoy — same posture as Box 1.
- LUKS-at-rest as Box 1.

## Build architecture — reuse, don't rebuild

No fresh OS install. Box 2 = **clone Box 1's installed+costumed base** and apply a
Box-2 inject:

```
dist/box1-gaia.built.qcow2  (2.2.8 installed + SunOS costume, PROVEN)
        │  cp
        ▼
dist/box2-<host>.qcow2  ──inject2──►  (foothold trace + root vector + watcher
                                        + toolkit cache + /etc/.fb + decoy trophy)
        │  luks ─► package ─► shiptest   (all reused unchanged)
```

Reused unchanged: `build/lib.sh`, `flag.sh`, `70-luks.sh`, `99-package.sh`,
`mk-player-readme.sh`, `98-shiptest.sh`, `drive_guest.py`, the `drive_solve.py`
scaffolding (new chain body).

New for Box 2:
- `config/box2.env` — params (hostname, accounts, instance/suffix, ports, the
  base-image clone source).
- `build/payloads2/` — `inject2-guest.sh` (planting), `tripwire.sh`
  (condition-gated flag), `zap.c`/`cloak.c` (player toolkit), the planted log
  traces + accounting logs, decoy trophy, watcher breadcrumbs.
- `build/40-inject2.sh` — clone base → drive guest inject (reuse `drive_guest.py`).
- a Box-2 solve chain in `drive_solve.py` (selected by an env/box flag).

## Open questions to settle before build

1. Root vector: trojaned `/bin/login` vs port-3111 backdoor (pick one; must differ
   from Box 1's `newgrp`).
2. Watcher cadence/visibility: silent cron vs a visible "admin logged in" event the
   player races.
3. Toolkit form: ship compilable `zap.c` (player compiles, Box-1 style) vs a
   pre-built `zap` binary in the cache.

## Series arc after Box 2

Box 1 break-in → Box 2 cover-up → Box 3 (sniffer cred-harvest / true multi-host
pivot) → persistence/backdoors. See `docs/primer.md`, `docs/historicity.md`.
