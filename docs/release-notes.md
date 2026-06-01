# Release notes — Box 1 "gaia" (Berkeley Underground)

Owner/maintainer release reference. Player-facing materials live in the release
bundle (`dist/release/box1-gaia/README.md`); this file is the ship procedure.

## What this release is

A self-contained, host-only boot2root VM: **FreeBSD 2.2.8** disclosed-as-**SunOS
4.1.4**, teaching the 1995 trust-model + setuid kill chain. Verified solvable
end-to-end (telnet `brian` → `.rhosts "+ +"` trust → setuid `newgrp` → root →
exfil the planted MANIAC loot; flag inside).

## Build it / package it

```sh
make build        # deps → fetch → iso → install → inject → theme  (SLOW: TCG)
make luks         # wrap the disk in LUKS  → dist/box1-gaia.enc.qcow2
make package      # assemble the player bundle → dist/release/ + tarball
# or, all at once:
make dist-image
make solve        # gate: automated end-to-end solve must pass before you ship
```

## Release artifacts (`dist/`, git-ignored)

| Artifact | Purpose |
|----------|---------|
| `box1-gaia.enc.qcow2` | LUKS-encrypted VM disk (the distributable) |
| `release/box1-gaia/` | the player bundle: image + `play.sh` + `README.md` + `*.key` + `SHA256SUMS` |
| `box1-gaia-release.tar.gz` | the bundle, tarred for distribution |
| `box1-gaia.built.qcow2` | clean reset snapshot (maintainer; **do not ship**) |
| `secret/flag.seed`, `secret/luks.key` | **owner secrets — never ship the seed; the key ships with the bundle** |

## Flag — know it, rotate it

The flag is derived per-instance and never stored as static text:
```
flag = BU{ md5(seed + instance)[:16] _ suffix }
```
```sh
build/flag.sh                         # the value players must submit, for the current seed
# rotate / mint per-player:
echo 'new-long-random-secret' > secret/flag.seed
make inject && make luks && make package && make solve
build/flag.sh                         # the new value
```

## Ship procedure

1. `make dist-image && make solve` — confirm the **solve gate passes** on the
   encrypted image.
2. Distribute `dist/box1-gaia-release.tar.gz` (contains the image, launcher,
   player README, and the LUKS key — players need the key to boot).
3. Publish the player README as the challenge description, and record the flag
   from `build/flag.sh` in your scoring system.
4. Players verify integrity with the bundled `SHA256SUMS`.

## Security posture (state it plainly)

VulnHub-style distributed box, hardened so **casual** cheating fails:
- **LUKS at rest** — offline `qemu-nbd`/`virt-filesystems`/libguestfs on the loose
  qcow2 hit ciphertext; a raw loop mount gets nothing.
- **Off-disk flag** — the powered-off disk carries only a decoy; the real flag is
  materialised into a RAM (MFS) filesystem at boot by `gen-flag.sh` (swap-backed
  `mount_mfs` overlaid on the loot dir; retries to absorb early-boot transients;
  leaves a root-only trace at `/root/.genflag.log` for owner inspection).
- It is **not DRM**: a distributed VM the player boots and roots can recover the
  value (the key ships with it, and they control the hypervisor). The target is
  "can't *trivially* grep/mount the flag", which is met.
- **No LVM** — the guest is FreeBSD/UFS, not Linux; LUKS-on-qcow2 provides the
  offline-ciphertext property.

## Spoiler control (confirmed)

The **player bundle ships only**: the encrypted image, its key, `play.sh`,
`README.md` (spoiler-free challenge description), and `SHA256SUMS`. It does **not**
contain the walkthrough or the owner cheat-sheet — `99-package.sh` copies nothing
else.

Held back from players (keep these OUT of any public repo until after a play
window): `docs/walkthrough.md` (full solution) and `docs/owner-cheatsheet.md`
(exact commands + knobs). `docs/primer.md` is **lore, not a walkthrough** — safe to
share as flavour, and the player README points to it. If you publish this build
repo, move the two spoiler files out (or to a private branch) first.

## Hygiene (done; re-check before each public push)

- Static flag **purged from git history** (`git log -S 'BU{' --all` is clean).
- `secret/` + `*.seed`/`*.key` are git-ignored and never entered history.
- `dist/` (images, keys, bundle) is git-ignored.

## Known characteristics (not bugs)

- Everything is slow — i386 is emulated via QEMU TCG (no KVM on the build host).
  2.2.8 itself is light (happy in 32 MB); the box runs in 128 MB.
- First multiuser boot takes a few minutes; the flag generator (`gen-flag.sh`)
  runs at boot — a fast automated solver may briefly see the decoy before the real
  flag materialises (`build/95-solve.sh` retries; a human is slow enough not to).
- You may see `mount_mfs: mfs filesystem not available` once on the console early
  in boot — harmless. `gen-flag.sh` retries its swap-backed MFS mount until it
  takes; the ship test (`make shiptest`) confirms the real flag materialises, and
  the solver records the resulting MFS overlay in its log.

## Series roadmap

Box 1 distils the chain onto one host. Later boxes restore what the primer says is
stripped here: multi-host pivoting, persistence, and anti-forensics (see
`docs/primer.md` and `docs/historicity.md`).
