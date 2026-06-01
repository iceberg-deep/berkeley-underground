#!/bin/sh
# gen-flag.sh -- regenerate the per-instance flag and the loot tarball at boot.
#
# Runs INSIDE the guest (installed by build/40-inject.sh; invoked from /etc/rc.local
# every boot, and once during inject).  The flag is DERIVED from a secret seed, so
# the disk image never stores a literal flag -- `grep -r 'BU{'` on a never-booted
# image finds only the decoy baked into the build-time tarball.  Deterministic, so
# build/flag.sh on the host computes the same value (the owner's copy).
#
#     token = first 16 hex of md5( seed )        flag = BU{ token _ suffix }
#
# POSIX/ash (2.2.8 /bin/sh).
CONF=/etc/flag.conf
[ -r "$CONF" ] || exit 0
. "$CONF"

# BSD md5 reads stdin and prints just the hash; awk $NF also copes with the
# "MD5 (stdin) = <hash>" form, and printf avoids echo -n portability snags.
TOKEN=`printf '%s' "$FLAG_SEED" | md5 2>/dev/null | awk '{print $NF}' | cut -c1-16`
[ -n "$TOKEN" ] || exit 0
FLAG="BU{${TOKEN}_${FLAG_SUFFIX}}"

DIR="$LOOT_DIR"
[ -d "$DIR" ] || exit 0

# 1) the trophy file inside the loot source tree
cat > "$DIR/flag.txt" <<EOF
Berkeley Underground -- Box 1 "gaia"

You rooted gaia, found the planted MANIAC firewall source, and pulled it off the
box -- exactly the objective of the Feb 1995 Motorola theft (cf. ~/takedown
TIMELINE sessions 4014 and 4017).

FLAG: $FLAG

How you proved it: this archive is now on a host you control.  No service on the
box had to "detect" anything -- possession after transfer is the proof.
EOF

# 2) rebuild the exfil tarball so the flag INSIDE it is the live one
TMP=/tmp/.maniacgen.$$
rm -rf "$TMP"; mkdir -p "$TMP/maniac"
for f in acl.c maniac.c maniac.h access Makefile README flag.txt; do
  [ -f "$DIR/$f" ] && cp "$DIR/$f" "$TMP/maniac/$f"
done
( cd "$TMP" && tar cf - maniac | gzip -9 > "$DIR/$LOOT_NAME" )
rm -rf "$TMP"
chown -R root "$DIR" 2>/dev/null
chmod -R go-w "$DIR" 2>/dev/null

# 3) owner's reference copy, root-only
echo "$FLAG" > /root/flag.txt
chmod 600 /root/flag.txt
exit 0
