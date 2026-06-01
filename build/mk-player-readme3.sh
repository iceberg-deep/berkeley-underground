#!/bin/sh
# Emit the player-facing README for Box 3 "the pivot".  Stdout -> README.md.
set -eu
. "$(dirname "$0")/lib.sh"

cat <<MD
# Berkeley Underground — Box 3: "the pivot" ($BOX_HOSTNAME)

> **In memory of Kevin Mitnick (1963–2023).**  A hands-on lab teaching authentic
> mid-1990s UNIX intrusion tradecraft, modelled on the February 1995 sessions.

|              |                                                            |
|--------------|------------------------------------------------------------|
| **Category** | boot2root · classic UNIX · **credential harvest + reuse** |
| **Difficulty** | Intermediate |
| **Networking** | Host-only — the VM has **no** route to the internet |
| **Win**      | Harvest the sysadmin's cleartext password and **reuse** it to reach root |
| **Flag format** | \`BU{...}\` (per-instance; recover it by solving the box) |

## ⚠️ Honest framing (read this)

This machine **presents as SunOS 4.1.4** but is actually **FreeBSD 2.2.8** in a
SunOS costume.  \`uname -a\` tells the truth, the banner doesn't.  **Every weakness
is real, not staged** — the harvested credential is a valid login, and the password
reuse is a genuine misconfiguration.  A note on realism: 1990s sniffing needed a
shared-Ethernet segment, which a single emulated host can't reproduce — so the box
gives you the *prior intruder's capture log* (exactly the form the real case
evidence took) rather than a live tap.  Reading it and reusing what's inside is the
real skill.

## Run it

You need **QEMU** (\`$BOX_QEMU\`).  Then, from this folder:
\`\`\`sh
./play.sh
\`\`\`
The VM boots on this terminal (emulated i386 — **first boot is slow**).  Wait for
the login banner, then attack from your host on **127.0.0.1**.  A period toolkit:
\`sudo apt-get install telnet ftp rsh-client\`.

## Objective

You have a foothold.  Above you sits **root**, but you don't have the password.

Someone was here before you and left their tools — including what their **sniffer**
pulled off the wire back when this segment was wide open.  1990s admin protocols
(telnet, FTP, POP) send passwords in the clear, and the operator who runs the
nightly backups was careless.  **Harvest what the sniffer caught, and remember that
admins reuse passwords.**  Enumerate; the prior intruder wasn't tidy.

> Want the history rather than the solution?  The episodes this distils — the NIT
> sniffer kernel (4015) and the credential-harvest pivot (4019) — are **lore, not a
> walkthrough**; ask the organiser for the primer.

## Files

- \`${BOX_BASENAME}.enc.qcow2\` — the VM disk (LUKS-encrypted)
- \`${BOX_BASENAME}.key\` — the decryption key (kept next to \`play.sh\`)
- \`play.sh\` — the launcher
- \`SHA256SUMS\` — integrity checksums

*The disk is encrypted at rest and the live flag is materialised in memory once you
are root — there's no plaintext flag to grep offline.*
MD
