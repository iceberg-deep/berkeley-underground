#!/bin/sh
# Emit the player-facing README for Box 4 "the backdoor".  Stdout -> README.md.
set -eu
. "$(dirname "$0")/lib.sh"

cat <<MD
# Berkeley Underground — Box 4: "the backdoor" ($BOX_HOSTNAME)

> **In memory of Kevin Mitnick (1963–2023).**  A hands-on lab teaching authentic
> mid-1990s UNIX intrusion tradecraft, modelled on the February 1995 sessions.

|              |                                                            |
|--------------|------------------------------------------------------------|
| **Category** | boot2root · classic UNIX · **persistence / backdoors** |
| **Difficulty** | Beginner–Intermediate |
| **Networking** | Host-only — the VM has **no** route to the internet |
| **Win**      | Find the intruder's persistent backdoor and use it to reach root |
| **Flag format** | \`BU{...}\` (per-instance; recover it by solving the box) |

## ⚠️ Honest framing (read this)

This machine **presents as SunOS 4.1.4** but is actually **FreeBSD 2.2.8** in a
SunOS costume.  \`uname -a\` tells the truth, the banner doesn't.  **Every weakness
is real, not staged** — the backdoor is a genuine inetd-wired trojan that drops a
real root shell.

## Run it

You need **QEMU** (\`$BOX_QEMU\`).  Then, from this folder:
\`\`\`sh
./play.sh
\`\`\`
The VM boots on this terminal (emulated i386 — **first boot is slow**).  Wait for
the login banner, then attack from your host on **127.0.0.1**.  A period toolkit:
\`sudo apt-get install telnet ftp rsh-client\`.

## Objective

Someone owned this box before you and made sure they could always get back in.
They left a **persistent backdoor** — a trojan daemon wired into the system's
service launcher so it survives every reboot, sitting on an unusual port and
waiting for a **secret knock**.

Get a foothold, **enumerate what's listening and how it's wired up**, find the
backdoor, and knock with the word.  It drops you straight to **root** — no password.
(The word is the same one this crew always used; the binary won't keep it secret if
you ask it nicely.)

> Want the history rather than the solution?  The episode this distils — the
> \`in.pmd\` trojan daemon and its trigger word (4007/4008) — is **lore, not a
> walkthrough**; ask the organiser for the primer.

## Files

- \`${BOX_BASENAME}.enc.qcow2\` — the VM disk (LUKS-encrypted)
- \`${BOX_BASENAME}.key\` — the decryption key (kept next to \`play.sh\`)
- \`play.sh\` — the launcher
- \`SHA256SUMS\` — integrity checksums

*The disk is encrypted at rest and the live flag is materialised in memory once you
are root — there's no plaintext flag to grep offline.*
MD
