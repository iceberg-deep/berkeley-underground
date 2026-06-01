#!/bin/sh
# Runs as root INSIDE a CLONE of the Box 1 base image (FreeBSD 2.2.8, SunOS-costumed),
# delivered via the tar-on-raw-disk channel (build/drive_guest.py).  Box 4 "the
# backdoor": neutralise Box 1's chain, then plant the prior intruder's persistent
# in.pmd backdoor (inetd, port $BACKDOOR_PORT, trigger $BACKDOOR_MAGIC -> root).
# POSIX/ash only (2.2.8 /bin/sh).  Config from box-guest.env (build/40-inject4.sh).
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

# ── 1. neutralise the Box 1 vuln chain (we cloned the gaia base) ────────────────
note "removing Box 1 artifacts (newgrp setuid, dono trust, gen-flag, loot)"
[ -f /usr/bin/newgrp ] && chmod u-s /usr/bin/newgrp 2>/dev/null
rm -f /home/dono/.rhosts
rm -f /usr/local/sbin/gen-flag.sh
if [ -f /etc/rc.local ]; then
  grep -v 'gen-flag.sh' /etc/rc.local > /tmp/rl.$$ 2>/dev/null
  cp /tmp/rl.$$ /etc/rc.local; rm -f /tmp/rl.$$
fi
rm -rf /usr/src/sys/maniac
rm -f /etc/.fb 2>/dev/null
rm -f /home/pei/.bash_history /home/$FOOTHOLD_USER/handover.txt 2>/dev/null

# ── 2. re-identify the host as well.sf.ca.us ───────────────────────────────────
note "retheming host identity -> $HOSTNAME_FQDN"
set_rc hostname "$HOSTNAME_FQDN"

# ── 3. the persistent backdoor: in.pmd wired to inetd as root ──────────────────
note "compiling + wiring in.pmd backdoor (inetd port $BACKDOOR_PORT, trigger '$BACKDOOR_MAGIC')"
"$CC" -DMAGIC="\"$BACKDOOR_MAGIC\"" -o /tmp/in.pmd.$$ "$HERE/files/in.pmd.c" || fail "in.pmd compile failed"
cp /tmp/in.pmd.$$ /usr/libexec/in.pmd; rm -f /tmp/in.pmd.$$
chown root:wheel /usr/libexec/in.pmd; chmod 755 /usr/libexec/in.pmd
# register the port as a named service, then wire it to in.pmd in inetd.conf
grep -q "^pmd[ 	]" /etc/services || echo "pmd		$BACKDOOR_PORT/tcp	# port monitor" >> /etc/services
grep -q "in.pmd" /etc/inetd.conf || \
  echo "pmd	stream	tcp	nowait	root	/usr/libexec/in.pmd	in.pmd" >> /etc/inetd.conf
grep -q "in.pmd" /etc/inetd.conf || fail "inetd.conf backdoor entry missing"

# ── 4. toolkit cache breadcrumb (cf 4001) ──────────────────────────────────────
note "planting backdoor breadcrumb in /home/$TRUST_USER"
CACHE="/home/$TRUST_USER"; mkdir -p "$CACHE"
cp "$HERE/files/backdoor-notes.txt" "$CACHE/notes"
chmod 644 "$CACHE/notes"; chmod 755 "$CACHE"

# ── 5. off-disk flag (decoy on disk, real flag only in RAM at boot) ────────────
[ -n "${FLAG_REAL:-}" ] || fail "FLAG_REAL not provided"
note "installing off-disk flag"
echo "$FLAG_REAL" | rev > /etc/.fb
test "`rev /etc/.fb`" = "$FLAG_REAL" || fail "flag rev round-trip failed"
chown root:wheel /etc/.fb; chmod 600 /etc/.fb
cp "$HERE/gen-flag.sh" /usr/local/sbin/gen-flag.sh
chown root:wheel /usr/local/sbin/gen-flag.sh; chmod 700 /usr/local/sbin/gen-flag.sh
mkdir -p "$LOOT_DIR"; chmod 700 "$LOOT_DIR"
printf '%s\n\nThis box has no plaintext flag on disk.  Find the backdoor and knock.\n' "$FLAG_DECOY" > "$LOOT_DIR/$LOOT_NAME"
chmod 600 "$LOOT_DIR/$LOOT_NAME"
[ -f /etc/rc.local ] || { echo '#!/bin/sh' > /etc/rc.local; chmod 755 /etc/rc.local; }
grep -q 'gen-flag.sh' /etc/rc.local || echo '/usr/local/sbin/gen-flag.sh' >> /etc/rc.local

note "inject4-guest complete"
exit 0
