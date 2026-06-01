# Box 4 — "the backdoor" (design blueprint)

Status: BUILDING. The final rung of the 4-box spine. Clones the Box 1 base like
Box 2/3. Grounded in `~/takedown/TIMELINE.md` 4007/4008 (cite session IDs).

## One-line

The prior intruder left **persistence** — the `in.pmd` trojan daemon wired into
inetd on a high port; knock with the magic word and it drops a root shell. Faithful
to **4007** (`sportd` renamed `in.pmd`, launched from inetd on **port 5553**,
trigger word **`wank`**) and the broader backdoor tradecraft of 4008/4023/4027.

## What it teaches (the last rung)

Box 1 = break-in, Box 2 = cover-up, Box 3 = pivot, **Box 4 = persistence**: how a
1995 intruder guaranteed re-entry — a trojan service in `inetd.conf` + `/etc/services`
that survives reboots, runs as root, and yields a shell on a secret knock. Teaches
defenders to **enumerate listeners + audit `inetd.conf`**.

## Topology / host

Single host `well.sf.ca.us` — the host Mitnick backdoored over and over. Cloned
from the Box 1 base.

## Kill chain

1. **Foothold** — telnet `brian`/`newriver`.
2. **Enumerate** — `netstat -a` shows port 5553 listening; `grep pmd
   /etc/inetd.conf /etc/services` shows the trojan wiring; the intruder's notes
   (cache) name the trigger; `strings /usr/libexec/in.pmd` leaks it.
3. **Knock** — connect to the backdoor (`telnet localhost 5553`) and send the magic
   word → `in.pmd` execs a root shell on the socket (inetd runs it as root).
4. **Flag** — read the off-disk flag as root.

## The mechanic (real, not staged)

- **The backdoor:** `in.pmd.c` compiled with `-DMAGIC`, installed at
  `/usr/libexec/in.pmd`, and wired via `/etc/services` (`pmd 5553/tcp`) +
  `/etc/inetd.conf` (`pmd stream tcp nowait root /usr/libexec/in.pmd in.pmd`).
  inetd launches it **as root**; the first line matching the magic word →
  `execl("/bin/sh","sh","-i")` on the socket. A real, re-entrant root backdoor.
- **Persistence:** it's in `inetd.conf`, so it returns on every reboot — the point.
- **Flag:** reuse the off-disk machinery (`/etc/.fb` reversed → `gen-flag.sh` MFS
  overlay at boot). Decoy on disk; LUKS at rest.

## Build / reuse

Clone `dist/box1-gaia.built.qcow2`; `inject4-guest.sh` neutralises Box 1's chain
and plants the backdoor + notes + off-disk flag. LUKS/package/ship-test reuse the
parameterised pipeline (`BOX_ENV_FILE=box4.env`, `BOX_README=mk-player-readme4.sh`,
`BOX_SOLVE_DRIVER=drive_solve4.py`). The solver knocks from the foothold
(`echo wank | telnet localhost 5553`) — no extra port forward needed.

## Risks to watch

- Does inetd pick up the new `pmd` service at boot? (offline edit to inetd.conf +
  /etc/services; inetd reads them at multiuser start.)
- `in.pmd` via inetd `nowait root`: the socket is on stdin/stdout/stderr; `sh -i`
  must read the piped knock + commands and write back over the socket.
