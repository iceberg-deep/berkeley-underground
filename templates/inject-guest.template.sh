#!/bin/sh
# Runs as root INSIDE a CLONE of the Box 1 base image (FreeBSD 2.2.8, SunOS-costumed),
# delivered via the tar-on-raw-disk channel (build/drive_guest.py).  Turn the gaia
# base into Box @@N@@.  POSIX/ash only (2.2.8 /bin/sh).  Config from box-guest.env
# (written by build/40-inject@@N@@.sh).
set -u
HERE=$(dirname "$0")
. "$HERE/box-guest.env"

note() { echo ">> $*"; }
fail() { echo "!! FATAL: $*" >&2; exit 1; }

CC=/usr/bin/cc
[ -x "$CC" ] || CC=/usr/bin/gcc
[ -x "$CC" ] || fail "no C compiler at /usr/bin/cc or /usr/bin/gcc"

RCLOCAL=/etc/rc.conf.local
set_rc() {  # key value  (idempotent)
  if [ -f "$RCLOCAL" ]; then
    grep -v "^$1=" "$RCLOCAL" > "$RCLOCAL.new" 2>/dev/null
    cp "$RCLOCAL.new" "$RCLOCAL"; rm -f "$RCLOCAL.new"
  fi
  echo "$1=\"$2\"" >> "$RCLOCAL"
}

# ── 1. neutralise the Box 1 vuln chain you don't want for this box ─────────────
note "removing unwanted Box 1 artifacts"
[ -f /usr/bin/newgrp ] && chmod u-s /usr/bin/newgrp 2>/dev/null   # kill setuid privesc
rm -f /home/dono/.rhosts                                          # kill rsh/rlogin trust
rm -f /usr/local/sbin/gen-flag.sh                                 # Box 1 flag generator
if [ -f /etc/rc.local ]; then
  grep -v 'gen-flag.sh' /etc/rc.local > /tmp/rl.$$ 2>/dev/null
  cp /tmp/rl.$$ /etc/rc.local; rm -f /tmp/rl.$$
fi
rm -rf /usr/src/sys/maniac                                        # Box 1 loot
rm -f /etc/.fb 2>/dev/null                                        # Box 1 flag blob (rewritten below)
rm -f /home/pei/.bash_history /home/$FOOTHOLD_USER/handover.txt 2>/dev/null
# (keep: accounts incl. $FOOTHOLD_USER, inetd services, network, the SunOS costume)

# ── 2. re-identify the host ────────────────────────────────────────────────────
note "retheming host identity -> $HOSTNAME_FQDN"
set_rc hostname "$HOSTNAME_FQDN"
# TODO: cp your motd/banner into /etc/motd if desired

# ── 3. plant THIS box's root vector ────────────────────────────────────────────
# TODO: compile + install your privesc (e.g. setuid binary).  Example:
#   "$CC" -o /tmp/x "$HERE/your.c" || fail "compile failed"
#   cp /tmp/x /usr/local/bin/x; chown root:wheel /usr/local/bin/x; chmod 4755 /usr/local/bin/x

# ── 4. breadcrumbs + toolkit the player needs ──────────────────────────────────
# TODO: plant notes/tools the intended path requires.

# ── 5. off-disk flag (decoy on disk, real flag only in RAM) ────────────────────
[ -n "${FLAG_REAL:-}" ] || fail "FLAG_REAL not provided"
note "installing off-disk flag"
echo "$FLAG_REAL" | rev > /etc/.fb                    # obfuscated (reversed), root-only
test "`rev /etc/.fb`" = "$FLAG_REAL" || fail "flag rev round-trip failed"
chown root:wheel /etc/.fb; chmod 600 /etc/.fb
# TODO: install your materialiser (copy build/payloads/gen-flag.sh for boot-gated,
# or build/payloads2/tripwire.sh for condition-gated) to /usr/local/sbin and hook
# it from /etc/rc.local.  Seed the on-disk DECOY trophy at $LOOT_DIR.

note "inject@@N@@-guest complete"
exit 0
