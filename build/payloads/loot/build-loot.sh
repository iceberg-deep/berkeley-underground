#!/bin/sh
# Build the "stolen source" loot tarball with the flag inside.
# Deterministic: same flag -> same contents. Output is git-ignored.
# Run standalone or via build/40-inject.sh.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$(cd "$HERE/../../.." && pwd)/config/box.env"

OUT="$HERE/$BOX_LOOT_NAME"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

DEST="$STAGE/maniac"
mkdir -p "$DEST"
cp "$HERE/src/"* "$DEST/"

# The trophy. Possession of THIS file after exfil proves the win.
cat > "$DEST/flag.txt" <<EOF
Berkeley Underground -- Box 1 "gaia"

You got root, found the planted source, and pulled it off the box.
That is exactly the objective of the Feb 1995 Motorola MANIAC theft
(cf. ~/takedown TIMELINE sessions 4014 and 4017).

FLAG: $BOX_FLAG

How you proved it: this archive is now on a host you control. No service
on the box had to "detect" anything -- possession after transfer is the proof.
EOF

# Period-style archive name. We use .tar.gz (gzip) rather than 1995's .tar.Z
# (compress) for toolchain portability; the field manual notes the difference.
( cd "$STAGE" && tar czf "$OUT" maniac )
echo "loot: $OUT ($(wc -c < "$OUT") bytes)"
