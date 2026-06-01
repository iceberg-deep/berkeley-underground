#!/bin/sh
# Stage 98: SHIP TEST — prove the RELEASED bundle works exactly as a player gets it.
# Extracts the distributable tarball into a clean dir OUTSIDE the repo, verifies the
# SHA-256 manifest, boots the box with the bundled play.sh (the box is launched ONLY
# by the shipped launcher — nothing in the repo touches qemu), then drives the full
# solve over the forwarded telnet port.  Exits 0 only if the shipped image solves.
set -eu
. "$(dirname "$0")/lib.sh"

TARBALL="$DIST_DIR/box1-${BOX_HOSTNAME}-release.tar.gz"
[ -f "$TARBALL" ] || die "no release tarball $TARBALL (run: make package)"
need telnet; need "$QEMU_BIN"
PY="python3"; [ -x "$REPO_ROOT/.venv/bin/python3" ] && PY="$REPO_ROOT/.venv/bin/python3"
"$PY" -c 'import pexpect' 2>/dev/null || die "pexpect missing (run: make deps)"

T=$(mktemp -d "${TMPDIR:-/tmp}/box1-shiptest.XXXXXX")
cleanup() { pkill -9 -f "$T" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT INT TERM

log "extracting $TARBALL into a clean dir $T (simulating a fresh player download)"
tar xzf "$TARBALL" -C "$T"
B="$T/box1-${BOX_HOSTNAME}"
[ -x "$B/play.sh" ] || die "bundle missing an executable play.sh"

log "verifying the shipped SHA256SUMS"
( cd "$B" && sha256sum -c SHA256SUMS ) || die "checksum mismatch in the shipped bundle"
ok "bundle integrity OK"

log "booting the box via the SHIPPED play.sh (host-only)"
( cd "$B" && ./play.sh < /dev/null > "$T/play.log" 2>&1 ) &

# Drive the solve against the already-running (play.sh) box; do NOT manage qemu.
export BOX_NO_BOOT=1
export QEMU_BIN BOX_MACHINE BOX_CPU BOX_MEM_MB
export BOX_FWD_TELNET BOX_FWD_FTP BOX_FWD_SHELL
export BOX_FOOTHOLD_USER BOX_FOOTHOLD_PASS BOX_TRUST_USER BOX_LOOT_DIR BOX_FLAG_DECOY
export BOX_IMAGE_ABS="$B/box1-${BOX_HOSTNAME}.enc.qcow2"   # for reap-key basename only
export BOX_SOLVE_SERIAL="$WORK_DIR/shiptest-serial.log"
export BOX_EXPECT_FLAG="$(sh "$REPO_ROOT/build/flag.sh" 2>/dev/null || true)"

log "solving the SHIPPED box (expecting ${BOX_EXPECT_FLAG:-<any BU{...}>})"
rc=0; "$PY" "$REPO_ROOT/build/drive_solve.py" || rc=$?
[ "$rc" = 0 ] && ok "SHIP TEST PASSED — the released bundle boots + solves on a clean host" \
              || die "SHIP TEST FAILED (rc=$rc) — see $T/play.log + $WORK_DIR/shiptest-serial-telnet.log"
