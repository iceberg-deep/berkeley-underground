#!/bin/sh
# Stage 2: build the install CD-ROM image from the distribution tree.
#
# 2.2.8 has no monolithic install ISO in the archive; the install is "boot floppy
# + distribution tree".  We boot the floppy, then point sysinstall at this CD for
# the 'bin' set.  The CD's root must hold cdrom.inf (sysinstall reads it to
# confirm the release) and the dist subdirs (bin/) exactly as the tree is laid
# out under media/<ver>/dist/.  Rock Ridge (-r) preserves the lower-case,
# long part filenames (e.g. bin.mtree, CHECKSUM.MD5) that ISO9660 8.3 would mangle.
set -eu
. "$(dirname "$0")/lib.sh"

SRC="$MEDIA_DIR/dist"
ISO="$WORK_DIR/install-${BOX_OS_VERSION}.iso"

[ -f "$SRC/cdrom.inf" ]    || die "missing $SRC/cdrom.inf (run: make fetch)"
[ -d "$SRC/bin" ]          || die "missing $SRC/bin (run: make fetch)"
[ -f "$SRC/bin/bin.aa" ]   || die "bin set looks empty (run: make fetch)"

# pick whatever ISO builder 00-deps left us
if command -v genisoimage >/dev/null 2>&1; then MKISO=genisoimage
elif command -v mkisofs    >/dev/null 2>&1; then MKISO=mkisofs
elif command -v xorriso    >/dev/null 2>&1; then MKISO="xorriso -as mkisofs"
else die "no ISO builder (run: make deps)"; fi

mkdir -p "$WORK_DIR"
log "building install CD from $SRC with $MKISO"
$MKISO -quiet -r -J -V "FREEBSD_${BOX_OS_VERSION}" -o "$ISO" "$SRC" \
  || die "ISO build failed"

sz=$(du -h "$ISO" | awk '{print $1}')
ok "install CD: $ISO ($sz)"
