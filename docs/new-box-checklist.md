# New-box checklist

How to spin up a new box on the proven pipeline.  Box 1 built the OS from scratch;
**every box after it clones Box 1's installed+costumed base image** (no reinstall)
and applies its own inject.  Box 2 is the reference implementation — copy its shape.

Companion: `docs/build-notes.md` (gotchas + proven recipes), `docs/box2-design.md`
(a worked design), `templates/` (skeletons), `build/new-box.sh` (scaffolder).

## 0. Design first

Write a one-page blueprint (see `docs/box2-design.md`): the skill it teaches, the
kill chain, the flag-gating mechanic, and which Box-1 artifacts the inject must
**neutralise** so your intended path is the only way.  Ground every beat in a
`~/takedown/TIMELINE.md` session id.

## 1. Scaffold

```sh
build/new-box.sh <N> <hostname> <domain>     # e.g.  build/new-box.sh 3 ariel sdsc.edu
```
This creates from `templates/`:
- `config/box<N>.env`     — params (fill in the TODOs)
- `build/payloads<N>/`    — `inject<N>-guest.sh` skeleton + a `files/` dir
- `build/40-inject<N>.sh` — clone-base + drive-guest stage

## 2. Fill in the config (`config/box<N>.env`)

- `BOX_HOSTNAME` / `BOX_DOMAIN` — pick a host grounded in the TIMELINE.
- `BOX2_BASE_IMAGE` style `BOX<N>_BASE_IMAGE` → usually `dist/box1-gaia.built.qcow2`.
- `BOX_FLAG_INSTANCE` (public, unique per box) + `BOX_FLAG_SUFFIX` (cosmetic) +
  `BOX_FLAG_DECOY` (must match whatever your gating script serves).
- Any vuln-specific knobs (magic words, watch intervals, paths).
- **Define every `$BOX_*` your stage/guest scripts read** — `set -eu` aborts on a
  missing one (we hit `BOX_TRUST_USER` this way).

## 3. Write the inject (`build/payloads<N>/inject<N>-guest.sh`)

Runs as root in the guest. Standard order (the skeleton has the helpers):
1. **Neutralise** Box 1's chain you don't want (drop `newgrp` setuid, `dono`
   `.rhosts`, `gen-flag` + its rc.local hook, the maniac loot, breadcrumbs).
2. **Re-identify** the host (`set_rc hostname`, `/etc/motd`).
3. **Plant your vector** (compile any C with `/usr/bin/cc`; setuid as needed).
4. **Plant breadcrumbs / toolkit** the player needs.
5. **Off-disk flag**: real flag reversed into root-only `/etc/.fb`; a boot/condition
   script materialises it into a `mount_mfs` overlay (copy `gen-flag.sh` /
   `tripwire.sh` and adjust the release condition).

## 4. Build, solve, package

```sh
build/40-inject<N>.sh                 # clone base + plant   (SLOW: TCG)
cp dist/box<N>-<host>.qcow2 dist/box<N>-<host>.built.qcow2   # clean snapshot
# write build/drive_solve<N>.py (copy drive_solve2.py; adjust the chain), then:
#   solve it; iterate until it passes (restore the .built snapshot between runs)
make luks   BOX_ENV_FILE=box<N>.env   # if shipping encrypted (reuses 70-luks.sh)
make package BOX_ENV_FILE=box<N>.env  # reuses 99-package.sh / mk-player-readme.sh
make shiptest BOX_ENV_FILE=box<N>.env # prove the SHIPPED bundle solves
```

## 5. Verify + commit + ship

- 3 clean solves (plaintext / shipped bundle / LUKS) like Box 1.
- Confirm the real flag never hits the persistent disk (decoy only) and isn't in
  git history; secrets stay git-ignored.
- Hold spoiler docs (walkthrough/cheat-sheet) out of any public repo.
- Append anything new you learned to `docs/build-notes.md`.

## Pitfalls (see build-notes for detail)

- Background Bash wrappers with `until…sleep` loops orphan + misreport under proot —
  run finite steps separately; verify reality after any "failed exit 1" on a long job.
- `cache=writethrough` + clean unmount-before-halt or you lose late writes.
- Solve-test the foothold **through telnet**, not just the serial console (the
  trojan-login `-h` bug only showed over telnet).
