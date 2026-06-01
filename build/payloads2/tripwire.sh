#!/bin/sh
# tripwire.sh -- "the watchful sysadmin" (Box 2: The Traced Call).
#
# Runs INSIDE the guest as root, on a timer (a loop launched from /etc/rc.local).
# Each sweep it looks for the intruder's traces in the login + accounting logs.
# While ANY trace of the foothold user remains, only a DECOY trophy exists; the
# sweep AFTER the player scrubs every trace materialises the REAL flag into a RAM
# (MFS) overlay -- so the flag rewards NOT getting caught.  Faithful to TIMELINE
# sessions 4005/4016 ("scrub reboot logs -- the traced call").
#
# The real flag lives obfuscated + root-only in /etc/.fb (reversed; no literal
# "BU{" to grep), exactly like Box 1's gen-flag.sh; we reuse that MFS machinery.
# POSIX/ash (2.2.8 /bin/sh).

PATH=/bin:/usr/bin:/sbin:/usr/sbin; export PATH   # cron runs with a minimal PATH

INTRUDER="${1:-brian}"          # foothold user whose records betray the break-in
SRCHOST="${2:-gaia}"            # planted source host in the records (extra signature)

LOOT=/var/account/.trophy       # where the trophy (decoy or real) is served
NAME=trophy.txt
BLOB=/etc/.fb                   # obfuscated real flag (root-only, reversed)
SWAP=/dev/wd0s1b                # swap partition, MFS backing store
WTMP=/var/log/wtmp
UTMP=/var/run/utmp
LASTLOG=/var/log/lastlog
ACCT=/var/account/awtmp         # the host accounting/billing log (grep -v target)
DECOY='BU{th3_c4ll_w4s_tr4c3d__scrub_wtmp_utmp_lastlog_and_th3_4cct_l0gs}'
DONE=/var/account/.released     # marker: real flag already materialised, stop sweeping
LOG=/root/.tripwire.log
glog() { echo "`date '+%H:%M:%S'` $*" >> "$LOG" 2>/dev/null; }

mkdir -p "$LOOT" 2>/dev/null
chmod 700 "$LOOT" 2>/dev/null

# Already released?  Nothing to do (flag stays live in RAM until reboot).
[ -f "$DONE" ] && exit 0

# ---- decide: is the intruder still visible in the logs? ----------------------
traces=0; why=""

# wtmp (login history) via last(1) — the intruder's own sessions
if last "$INTRUDER" 2>/dev/null | grep -q "$INTRUDER"; then traces=1; why="$why wtmp"; fi
# utmp (who is on now) via who(1)
if who 2>/dev/null | grep -q "$INTRUDER"; then traces=1; why="$why utmp"; fi
# accounting/billing log (plain text we planted) via grep
if [ -f "$ACCT" ] && grep -q "$INTRUDER" "$ACCT" 2>/dev/null; then traces=1; why="$why acct"; fi
# NOTE: no lastlog gate — lastlogin(1) prints the username even for a zeroed
# record, so it can't tell clean from dirty.  zap.c still clears lastlog; the
# decoy message still tells the player to, but the watcher keys on wtmp/utmp/acct.

# ---- anti-cheese: deleting/zeroing the logs is itself a red flag -------------
# (the historically-correct move is surgical editing with zap/cloak, not rm).
for f in "$WTMP" "$UTMP"; do
  if [ ! -s "$f" ]; then traces=1; why="$why tampered:`basename $f`"; fi
done

# ---- serve the appropriate trophy -------------------------------------------
if [ "$traces" = 1 ]; then
  # still hot: ensure only the decoy is present
  if [ ! -f "$LOOT/$NAME" ] || ! grep -q "$DECOY" "$LOOT/$NAME" 2>/dev/null; then
    printf 'The sysadmin reviews `last` and the billing logs.\nYour session is still in them -- the call was traced.\n\n%s\n\nScrub wtmp, utmp, lastlog AND the accounting logs, then check back.\n' "$DECOY" > "$LOOT/$NAME"
    chmod 600 "$LOOT/$NAME"
  fi
  glog "traces present ->$why ; serving decoy"
  exit 0
fi

# clean!  materialise the real flag into RAM (MFS), like Box 1's gen-flag.
[ -r "$BLOB" ] || { glog "clean but no /etc/.fb blob; abort"; exit 0; }
FLAG=`rev "$BLOB" 2>/dev/null`
case "$FLAG" in BU\{*\}) : ;; *) glog "deobfuscated value not a flag; abort"; exit 0 ;; esac

/sbin/umount "$LOOT" 2>/dev/null
i=0; mounted=no
while [ $i -lt 8 ]; do
  if /sbin/mount_mfs -s 2048 "$SWAP" "$LOOT" 2>>"$LOG"; then mounted=yes; break; fi
  i=`expr $i + 1`; glog "mount_mfs try $i failed; retrying"; sleep 2
done
[ "$mounted" = yes ] || { glog "mount_mfs FAILED after retries; will retry next sweep"; exit 0; }
chmod 700 "$LOOT"

cat > "$LOOT/$NAME" <<EOF
Berkeley Underground -- Box 2 "The Traced Call"

You rooted the box AND covered your tracks: \`last\` no longer shows your session,
and the billing logs are clean.  The sysadmin's review found nothing -- the call
was never traced.  This is the discipline the Feb 1995 sessions spent most of
their keystrokes on (cf ~/takedown TIMELINE 4005 / 4016).

FLAG: $FLAG

This trophy lives only in RAM, released the moment your traces vanished.
EOF
chmod 600 "$LOOT/$NAME"
: > "$DONE" 2>/dev/null
glog "logs clean -> REAL flag materialised in MFS overlay"
exit 0
