#!/bin/sh
# gen-flag.sh (Box 4) -- materialise the real flag into a RAM (MFS) overlay at
# every boot, from the obfuscated root-only /etc/.fb.  Boot-gated (/etc/rc.local).
# The powered-off disk carries only the decoy.  POSIX/ash.
PATH=/bin:/usr/bin:/sbin:/usr/sbin; export PATH
LOOT=/var/adm/.loot
NAME=flag.txt
BLOB=/etc/.fb
SWAP=/dev/wd0s1b
LOG=/root/.genflag.log
glog() { echo "`date '+%H:%M:%S'` $*" >> "$LOG" 2>/dev/null; }
: > "$LOG" 2>/dev/null; chmod 600 "$LOG" 2>/dev/null

[ -r "$BLOB" ] || { glog "no /etc/.fb blob; abort"; exit 0; }
FLAG=`rev "$BLOB" 2>/dev/null`
case "$FLAG" in BU\{*\}) : ;; *) glog "deobfuscated value not a flag; abort"; exit 0 ;; esac

/sbin/umount "$LOOT" 2>/dev/null
i=0; mounted=no
while [ $i -lt 8 ]; do
  if /sbin/mount_mfs -s 2048 "$SWAP" "$LOOT" 2>>"$LOG"; then mounted=yes; break; fi
  i=`expr $i + 1`; glog "mount_mfs try $i failed; retrying"; sleep 2
done
[ "$mounted" = yes ] || { glog "mount_mfs FAILED after retries; will retry next boot"; exit 0; }
chmod 700 "$LOOT"

cat > "$LOOT/$NAME" <<EOF
Berkeley Underground -- Box 4 "the backdoor"

You found the prior intruder's persistence -- the in.pmd trojan wired to inetd --
and knocked with the magic word to get a root shell, no password needed.  Exactly
the Feb 1995 tradecraft (cf ~/takedown TIMELINE 4007/4008: sportd->in.pmd, port
5553, trigger 'wank').

FLAG: $FLAG

This trophy lives only in RAM on a running, rooted box.
EOF
chmod 600 "$LOOT/$NAME"
glog "real flag materialised in MFS overlay"
exit 0
