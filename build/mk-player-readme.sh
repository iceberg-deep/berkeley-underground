#!/bin/sh
# Emit the player-facing README (challenge description) for the release bundle,
# with the box's parameters interpolated.  Stdout -> dist/release/.../README.md.
set -eu
. "$(dirname "$0")/lib.sh"

cat <<MD
# Berkeley Underground — Box 1: "$BOX_HOSTNAME"

> **In memory of Kevin Mitnick (1963–2023).**  A hands-on lab teaching authentic
> mid-1990s UNIX intrusion tradecraft, modelled on the February 1995 sessions.

|              |                                                            |
|--------------|------------------------------------------------------------|
| **Category** | boot2root · classic UNIX · trust-model / privilege-escalation |
| **Difficulty** | Beginner-friendly (the box leaves breadcrumbs)           |
| **Networking** | Host-only — the VM has **no** route to the internet      |
| **Win**      | Get root, find the planted "stolen source", exfiltrate it off-box; the flag is *inside* the tarball |
| **Flag format** | \`BU{...}\` (per-instance; recover it by solving the box)|

## ⚠️ Honest framing (read this)

This machine **presents as SunOS 4.1.4** but is actually **FreeBSD 2.2.8** in a
SunOS costume — genuine SunOS isn't redistributable, and a 4.3BSD-lineage cousin
keeps the 1995-era r-services + setuid lessons authentic.  \`uname -a\` tells the
truth, the banner doesn't.  **Every weakness is real, not staged.**  The *techniques*
are drawn from the captured sessions; the *path* is distilled onto one host (the
real attack was dozens of systems over days, and began with social engineering no
box can teach).

## Run it

You need **QEMU** (\`$BOX_QEMU\`).  Then, from this folder:
\`\`\`sh
./play.sh
\`\`\`
\`play.sh\` uses **KVM acceleration when available** (on an x86 host it boots in
seconds) and falls back to pure emulation otherwise (a few minutes for the first
boot — normal, not a hang).  The VM boots on this terminal; wait for the SunOS
login banner.  Stop the VM with **Ctrl-A** then **X**.  Attack it from
**127.0.0.1**.

### Running on Windows

\`play.sh\` is a shell script, so run it under **WSL2** (recommended — it's a Linux
environment with KVM acceleration on Intel/AMD):
\`\`\`powershell
wsl --install        # admin PowerShell; reboot when prompted
\`\`\`
then inside the Linux shell: \`sudo apt-get install -y qemu-system-x86 telnet ftp\`,
extract the bundle, and \`./play.sh\` as above.  (Native Windows works too if you run
the \`qemu-system-i386\` command from \`play.sh\` by hand in \`cmd\`/PowerShell.)

Start with what's listening on **127.0.0.1** (it's a 1990s box — expect 1990s
services).  A period-appropriate toolkit on a modern attacker box:
\`sudo apt-get install telnet ftp rsh-client\`.

## Objective

Get a foothold, work your way up to **root**, then **exfiltrate** the planted
"stolen source" tarball off the box — the flag is inside it.

The box is beginner-friendly: a careless administrator left traces that point the
way, so **enumerate carefully**.  The techniques you'll need are real tradecraft
from the era — *which* ones is for you to discover.  No memory-corruption exploit
is required; this is about how 1990s UNIX trusted things it shouldn't have.

> Want the history rather than the solution?  The story this box distils — the
> February 1995 sessions, and the human layer no box can teach — is **lore, not a
> walkthrough**; ask the organiser for the primer if it isn't bundled.

## Files

- \`box1-$BOX_HOSTNAME.enc.qcow2\` — the VM disk (LUKS-encrypted)
- \`box1-$BOX_HOSTNAME.key\` — the decryption key (kept next to \`play.sh\`)
- \`play.sh\` — the launcher
- \`SHA256SUMS\` — integrity checksums

*The disk is encrypted at rest (offline mounting yields ciphertext) and the live
flag is materialised in memory, not stored as plaintext on disk — so the fun way
in is the only easy way in.  Have at it.*
MD
