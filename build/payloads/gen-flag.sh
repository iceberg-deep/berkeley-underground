#!/bin/sh
# gen-flag.sh -- materialise the real flag into a MEMORY filesystem at every boot.
#
# Runs INSIDE the guest as root, from /etc/rc.local (every boot).  The persistent
# disk holds only a DECOY flag (in the on-disk loot) plus an OBFUSCATED copy of the
# real flag in /etc/.fb (root-only, reversed -- no literal "BU{" to grep).  At boot
# we mount a small MFS (RAM, swap-backed) OVER the loot directory and rebuild the
# loot there with the real flag -- so:
#   * a powered-off / offline-mounted disk shows only the decoy (and ciphertext
#     once LUKS-wrapped);
#   * the real flag exists only in RAM on a running, rooted box.
# POSIX/ash (2.2.8 /bin/sh).
LOOT=/usr/src/sys/maniac
NAME=maniac1.3.4.tar.gz
BLOB=/etc/.fb
SWAP=/dev/wd0s1b          # swap partition, MFS backing store
[ -r "$BLOB" ] || exit 0
[ -d "$LOOT" ] || exit 0

# de-obfuscate the real flag (stored reversed)
FLAG=`rev "$BLOB" 2>/dev/null`
case "$FLAG" in BU\{*\}) : ;; *) exit 0 ;; esac   # sanity: looks like a flag

# stash the on-disk loot SOURCES (not the decoy flag) before we hide them with MFS
STAGE=/tmp/.lootstage.$$
rm -rf "$STAGE"; mkdir -p "$STAGE"
for f in acl.c maniac.c maniac.h access Makefile README EVIDENCE.md; do
  [ -f "$LOOT/$f" ] && cp "$LOOT/$f" "$STAGE/$f"
done

# overlay a memory filesystem on the loot dir (hides the persistent decoy)
/sbin/umount "$LOOT" 2>/dev/null
if ! /sbin/mount_mfs -s 4096 "$SWAP" "$LOOT" 2>/dev/null; then
  rm -rf "$STAGE"; exit 0     # no MFS -> leave the (decoy) on-disk loot as-is
fi
mkdir -p "$LOOT"
cp "$STAGE"/* "$LOOT/" 2>/dev/null
rm -rf "$STAGE"

# write the real trophy + rebuild the exfil tarball, all in RAM
cat > "$LOOT/flag.txt" <<EOF
Berkeley Underground -- Box 1 "gaia"

You rooted gaia, found the planted MANIAC firewall source, and pulled it off the
box -- exactly the Feb 1995 Motorola theft (cf. ~/takedown TIMELINE 4014 / 4017).

FLAG: $FLAG

Possession after transfer is the proof.  This file lives only in RAM on a running
box; the powered-off disk carries a decoy.
EOF
TMP=/tmp/.mgen.$$
rm -rf "$TMP"; mkdir -p "$TMP/maniac"
for f in acl.c maniac.c maniac.h access Makefile README flag.txt; do
  [ -f "$LOOT/$f" ] && cp "$LOOT/$f" "$TMP/maniac/$f"
done
( cd "$TMP" && tar cf - maniac | gzip -9 > "$LOOT/$NAME" )
rm -rf "$TMP"
chown -R root "$LOOT" 2>/dev/null
chmod -R go-w "$LOOT" 2>/dev/null
# owner-readable live flag for convenience (root-only, in RAM too if /root is mfs?
# no -- /root is on disk, so keep this OUT of persistent disk):
exit 0
