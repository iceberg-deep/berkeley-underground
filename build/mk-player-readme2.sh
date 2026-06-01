#!/bin/sh
# Emit the player-facing README for Box 2 "The Traced Call".  Stdout -> README.md.
set -eu
. "$(dirname "$0")/lib.sh"

cat <<MD
# Berkeley Underground — Box 2: "The Traced Call" ($BOX_HOSTNAME)

> **In memory of Kevin Mitnick (1963–2023).**  A hands-on lab teaching authentic
> mid-1990s UNIX intrusion tradecraft, modelled on the February 1995 sessions.

|              |                                                            |
|--------------|------------------------------------------------------------|
| **Category** | boot2root · classic UNIX · **anti-forensics** |
| **Difficulty** | Intermediate (root is the easy part) |
| **Networking** | Host-only — the VM has **no** route to the internet |
| **Win**      | Get root, then make sure your intrusion left **no trace** — the trophy is only released once you're clean |
| **Flag format** | \`BU{...}\` (per-instance; recover it by solving the box) |

## ⚠️ Honest framing (read this)

This machine **presents as SunOS 4.1.4** but is actually **FreeBSD 2.2.8** in a
SunOS costume (genuine SunOS isn't redistributable; a 4.3BSD-lineage cousin keeps
the 1995-era lessons authentic).  \`uname -a\` tells the truth, the banner doesn't.
**Every weakness is real, not staged.**

## Run it

You need **QEMU** (\`$BOX_QEMU\`).  Then, from this folder:
\`\`\`sh
./play.sh
\`\`\`
The VM boots on this terminal (emulated i386 — **first boot is slow**).  Wait for
the login banner, then attack from your host on **127.0.0.1** (1990s box → 1990s
services).  A period toolkit: \`sudo apt-get install telnet ftp rsh-client\`.

## Objective

Getting **root** here is the warm-up.  The real lesson is what the best intruders
of the era spent *most* of their time on: **not getting caught.**

This host is **watched** — the operator reviews the login records and the
connect-time billing on a timer (the banner says so).  While your session shows up
in them, you're burned: the trophy you're after reads *"the call was traced."*
Your job is to root the box **and then erase every trace that you were ever here**
— the genuine article is released only once your intrusion has vanished from the
logs.  A previous visitor left tools and notes behind; find them.

> Want the history rather than the solution?  The episode this box distils — the
> February 1995 night a scrubbed-but-not-quite session got a phone call traced —
> is **lore, not a walkthrough**; ask the organiser for the primer.

## Files

- \`${BOX_BASENAME}.enc.qcow2\` — the VM disk (LUKS-encrypted)
- \`${BOX_BASENAME}.key\` — the decryption key (kept next to \`play.sh\`)
- \`play.sh\` — the launcher
- \`SHA256SUMS\` — integrity checksums

*The disk is encrypted at rest and the live flag is materialised in memory only
once you've covered your tracks — there's no plaintext flag to grep offline.*
MD
