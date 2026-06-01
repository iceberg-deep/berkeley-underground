#!/bin/sh
# Runs as root INSIDE a CLONE of the Box 1 base image (FreeBSD 2.2.8, SunOS-costumed),
# delivered via the tar-on-raw-disk channel (build/drive_guest.py).  Box 3 "the
# pivot": neutralise Box 1's chain, then plant the found-sniffer-log + password-reuse
# escalation.  POSIX/ash only (2.2.8 /bin/sh).  Config from box-guest.env (written
# by build/40-inject3.sh).
set -u
HERE=$(dirname "$0")
. "$HERE/box-guest.env"

note() { echo ">> $*"; }
fail() { echo "!! FATAL: $*" >&2; exit 1; }

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
# (keep: accounts incl. $FOOTHOLD_USER, inetd services + ftpd, network, costume)

# ── 2. re-identify the host as escape.com ──────────────────────────────────────
note "retheming host identity -> $HOSTNAME_FQDN"
set_rc hostname "$HOSTNAME_FQDN"

# ── 3. the operator account 'ops' (wheel) + password REUSE by root ─────────────
note "creating operator $OPS_USER (wheel) and reusing its password for root"
if ! grep -q "^$OPS_USER:" /etc/master.passwd; then
  echo "$OPS_USER:$OPS_HASH:106:106::0:0:System Operator:/home/$OPS_USER:/bin/sh" >> /etc/master.passwd
fi
grep -q "^$OPS_USER:" /etc/group || echo "$OPS_USER:*:106:" >> /etc/group
# add ops to wheel so it can su to root (base wheel line is "wheel:*:0:root").
# (avoid `&& ! grep` — 2.2.8 ash parse-bombs on `!` after &&/||; use a flag.)
inwheel=no
grep '^wheel:' /etc/group | grep -q "$OPS_USER" && inwheel=yes
if [ "$inwheel" = no ] && grep -q '^wheel:' /etc/group; then
  sed "/^wheel:/s/\$/,$OPS_USER/" /etc/group > /tmp/g.$$
  cp /tmp/g.$$ /etc/group; rm -f /tmp/g.$$
fi
mkdir -p "/home/$OPS_USER"; chown 106:106 "/home/$OPS_USER"; chmod 755 "/home/$OPS_USER"
# REUSE: set root's password hash to ops's (the captured one)
sed "s|^root:[^:]*:|root:$ROOT_HASH:|" /etc/master.passwd > /tmp/mp.$$ && cp /tmp/mp.$$ /etc/master.passwd; rm -f /tmp/mp.$$
pwd_mkdb -p /etc/master.passwd || fail "pwd_mkdb failed"
grep -q "^$OPS_USER:" /etc/passwd || fail "ops account not in passwd db"

# ── 4. the prior intruder's found sunsniffer capture log (the win path) ────────
note "planting sunsniffer capture log at $SNIFFLOG"
mkdir -p "`dirname $SNIFFLOG`"
cp "$HERE/files/sunsniff.log" "$SNIFFLOG"
chmod 644 "$SNIFFLOG"                              # world-readable: the foothold can harvest it
grep -q "PASS" "$SNIFFLOG" || fail "sniff log missing captured creds"

# ── 5. toolkit cache flavour + breadcrumb (cf 4001) ────────────────────────────
note "planting toolkit cache in /home/$TRUST_USER"
CACHE="/home/$TRUST_USER"; mkdir -p "$CACHE"
cp "$HERE/files/sunsniffer.c"   "$CACHE/sunsniffer.c"
cp "$HERE/files/sniff-notes.txt" "$CACHE/notes"
chmod 644 "$CACHE/sunsniffer.c" "$CACHE/notes"; chmod 755 "$CACHE"

# ── 6. off-disk flag (decoy on disk, real flag only in RAM at boot) ────────────
[ -n "${FLAG_REAL:-}" ] || fail "FLAG_REAL not provided"
note "installing off-disk flag"
echo "$FLAG_REAL" | rev > /etc/.fb
test "`rev /etc/.fb`" = "$FLAG_REAL" || fail "flag rev round-trip failed"
chown root:wheel /etc/.fb; chmod 600 /etc/.fb
cp "$HERE/gen-flag.sh" /usr/local/sbin/gen-flag.sh
chown root:wheel /usr/local/sbin/gen-flag.sh; chmod 700 /usr/local/sbin/gen-flag.sh
# on-disk DECOY at the loot dir (the real flag overlays it in RAM at boot)
mkdir -p "$LOOT_DIR"; chmod 700 "$LOOT_DIR"
printf '%s\n\nThis box has no plaintext flag on disk.  Sniff the admin and reuse to root.\n' "$FLAG_DECOY" > "$LOOT_DIR/$LOOT_NAME"
chmod 600 "$LOOT_DIR/$LOOT_NAME"
# run gen-flag at every multiuser boot
[ -f /etc/rc.local ] || { echo '#!/bin/sh' > /etc/rc.local; chmod 755 /etc/rc.local; }
grep -q 'gen-flag.sh' /etc/rc.local || echo '/usr/local/sbin/gen-flag.sh' >> /etc/rc.local

note "inject3-guest complete"
exit 0
