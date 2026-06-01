#!/bin/sh
# Stage 99: assemble the player-facing RELEASE BUNDLE.
#
# Produces dist/release/<name>/ with everything a player needs to run the box —
# the LUKS-encrypted image, a SELF-CONTAINED launcher (no repo dependencies), a
# player README, the LUKS key, and SHA256SUMS — plus a tarball for distribution.
#
# Distribution model: this is a VulnHub-style DISTRIBUTED box, so the key ships
# WITH the bundle (the player must boot it).  The LUKS layer + off-disk flag raise
# the bar against lazy grep / offline mount; they are not DRM (see docs).
set -eu
. "$(dirname "$0")/lib.sh"

need "$QEMU_BIN"; command -v sha256sum >/dev/null 2>&1 || die "need sha256sum"

[ -f "$ENC_IMAGE" ] || die "no encrypted image $ENC_IMAGE (run: make luks)"
KF=$(luks_keyfile) || die "no LUKS key (run: make luks)"

REL="$DIST_DIR/release/box1-${BOX_HOSTNAME}"
log "assembling release bundle in $REL"
rm -rf "$REL"; mkdir -p "$REL"

cp "$ENC_IMAGE" "$REL/box1-${BOX_HOSTNAME}.enc.qcow2"
cp "$KF"        "$REL/box1-${BOX_HOSTNAME}.key"
chmod 600       "$REL/box1-${BOX_HOSTNAME}.key"

# ── self-contained launcher (no lib.sh / repo needed) ──────────────────────────
cat > "$REL/play.sh" <<PLAY
#!/bin/sh
# Boot "$BOX_HOSTNAME" — HOST-ONLY (the guest has no route to the internet).
# Requires: qemu-system-i386.  The LUKS key is the .key file next to this script.
# Attack it from 127.0.0.1: telnet $BOX_FWD_TELNET, ftp $BOX_FWD_FTP, rlogin/rsh $BOX_FWD_SHELL.
# Stop the VM with Ctrl-A then X (or Ctrl-C).
set -eu
DIR=\$(cd "\$(dirname "\$0")" && pwd)
IMG="\$DIR/box1-${BOX_HOSTNAME}.enc.qcow2"
KEY="\${BOX1_KEY:-\$DIR/box1-${BOX_HOSTNAME}.key}"
command -v ${BOX_QEMU} >/dev/null 2>&1 || { echo "install ${BOX_QEMU} (QEMU) first"; exit 1; }
[ -f "\$KEY" ] || { echo "missing LUKS key: \$KEY"; exit 1; }
echo ">> booting $BOX_HOSTNAME (host-only).  Attack 127.0.0.1: telnet $BOX_FWD_TELNET / ftp $BOX_FWD_FTP / rlogin $BOX_FWD_SHELL"
echo ">> first boot is slow (emulated i386); wait for the login banner, then telnet in."
exec ${BOX_QEMU} -machine ${BOX_MACHINE},graphics=off -cpu ${BOX_CPU} -m ${BOX_MEM_MB} \\
  -object secret,id=sec0,file="\$KEY" \\
  -drive file="\$IMG",format=qcow2,if=ide,index=0,media=disk,encrypt.key-secret=sec0 \\
  -boot c -nographic -no-reboot \\
  -netdev user,id=n0,restrict=on,hostfwd=tcp:127.0.0.1:${BOX_FWD_TELNET}-:23,hostfwd=tcp:127.0.0.1:${BOX_FWD_FTP}-:21,hostfwd=tcp:127.0.0.1:${BOX_FWD_SHELL}-:513 \\
  -device ne2k_pci,netdev=n0
PLAY
chmod +x "$REL/play.sh"

# ── player README (the challenge description) ──────────────────────────────────
"$REPO_ROOT/build/mk-player-readme.sh" > "$REL/README.md"

# ── SHA-256 manifest (image + keyfile + launcher + README) ─────────────────────
( cd "$REL" && sha256sum \
    box1-${BOX_HOSTNAME}.enc.qcow2 \
    box1-${BOX_HOSTNAME}.key \
    play.sh README.md > SHA256SUMS )

# ── distributable tarball ──────────────────────────────────────────────────────
TARBALL="$DIST_DIR/box1-${BOX_HOSTNAME}-release.tar.gz"
( cd "$DIST_DIR/release" && tar czf "$TARBALL" "box1-${BOX_HOSTNAME}" )

ok "release bundle: $REL"
log "  files: $(ls "$REL" | tr '\n' ' ')"
ok "distributable tarball: $TARBALL ($(du -h "$TARBALL" | awk '{print $1}'))"
warn "the bundle INCLUDES the LUKS key (players must boot it).  The flag the box"
warn "yields is BU{...} = $(sh "$REPO_ROOT/build/flag.sh" 2>/dev/null || echo '<set a seed>')  (grade against this)."
