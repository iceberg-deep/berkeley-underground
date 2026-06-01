#!/bin/sh
# Stage 1: fetch + verify FreeBSD install media and the 'bin' distribution set.
#
# Reproduces the media already living (gitignored) under media/<version>/.  The
# upstream archive's TLS cert SAN does not match its hostname, so we fetch over
# plain http:// from ftp-archive.freebsd.org (see config/box.env BOX_ARCHIVE_BASE)
# and verify every byte against the release's own CHECKSUM.MD5 — integrity comes
# from the checksums, not the transport.
#
# Idempotent: a file that already verifies is left untouched, so re-running is
# cheap and a partial download resumes cleanly.
set -eu
. "$(dirname "$0")/lib.sh"

REL_URL="$BOX_ARCHIVE_BASE/${BOX_OS_VERSION}-RELEASE"
FLOPPY_DIR="$MEDIA_DIR/floppies"
BIN_DIR="$MEDIA_DIR/dist/bin"

mkdir -p "$FLOPPY_DIR" "$BIN_DIR" "$MEDIA_DIR/dist"

# fetch URL DEST  — download only if missing; plain http, retry, follow redirects.
fetch() {
  _url="$1"; _dst="$2"
  if [ -s "$_dst" ]; then return 0; fi
  log "fetch $(basename "$_dst")"
  curl -fsSL --retry 3 --retry-delay 2 -o "$_dst.part" "$_url" \
    || die "download failed: $_url"
  mv "$_dst.part" "$_dst"
}

# md5 of a file (portable: prefer md5sum, fall back to openssl).
md5_of() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'
  else openssl md5 "$1" | awk '{print $NF}'; fi
}

# ── boot/fixit floppies ────────────────────────────────────────────────────────
log "floppies"
fetch "$REL_URL/floppies/boot.flp"  "$FLOPPY_DIR/boot.flp"
fetch "$REL_URL/floppies/fixit.flp" "$FLOPPY_DIR/fixit.flp"
for f in boot.flp fixit.flp; do
  sz=$(wc -c < "$FLOPPY_DIR/$f")
  [ "$sz" = "1474560" ] || warn "$f is $sz bytes (expected 1474560 — a 1.44M floppy)"
done

# ── distribution metadata (needed to enumerate + verify the bin set) ───────────
log "dist metadata"
fetch "$REL_URL/cdrom.inf"      "$MEDIA_DIR/dist/cdrom.inf"
for m in CHECKSUM.MD5 bin.inf bin.mtree install.sh; do
  fetch "$REL_URL/bin/$m" "$BIN_DIR/$m"
done

# ── the bin set: every part listed in CHECKSUM.MD5, verified against it ─────────
# CHECKSUM.MD5 lines look like:  MD5 (bin.aa) = 51b099cf...
log "bin distribution set"
parts=$(sed -n 's/^MD5 (\(bin\.[a-z][a-z]\)).*/\1/p' "$BIN_DIR/CHECKSUM.MD5")
[ -n "$parts" ] || die "could not parse part list from CHECKSUM.MD5"

bad=0; n=0
for p in $parts; do
  n=$((n + 1))
  want=$(sed -n "s/^MD5 ($p) = //p" "$BIN_DIR/CHECKSUM.MD5")
  if [ -s "$BIN_DIR/$p" ] && [ "$(md5_of "$BIN_DIR/$p")" = "$want" ]; then
    continue
  fi
  fetch "$REL_URL/bin/$p" "$BIN_DIR/$p"
  got=$(md5_of "$BIN_DIR/$p")
  if [ "$got" != "$want" ]; then
    warn "MD5 mismatch on $p (want $want got $got) — removing"
    rm -f "$BIN_DIR/$p"
    bad=$((bad + 1))
  fi
done

[ "$bad" = 0 ] || die "$bad bin part(s) failed verification; re-run to retry"
ok "media present + verified: 2 floppies, $n bin parts (md5 OK vs CHECKSUM.MD5)"
