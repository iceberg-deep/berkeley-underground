#!/bin/sh
# Stage 95: the end-to-end SOLVE TEST.  Boots the finished box host-only and walks
# the intended kill chain over the forwarded telnet port (telnet brian -> rlogin
# dono via .rhosts -> newgrp -hack root -> read the loot flag).  Exits 0 only if a
# uid=0 shell is reached AND the expected flag is recovered.  This is the gate for
# "the box is solvable end to end".
set -eu
. "$(dirname "$0")/lib.sh"

need "$QEMU_BIN"; need telnet

PY="python3"; [ -x "$REPO_ROOT/.venv/bin/python3" ] && PY="$REPO_ROOT/.venv/bin/python3"
"$PY" -c 'import pexpect' 2>/dev/null || die "pexpect missing (run: make deps)"

# Prefer the LUKS-encrypted distributable (proves the SHIPPED box solves); else plaintext.
if [ -f "$ENC_IMAGE" ] && KF=$(luks_keyfile 2>/dev/null); then
  export BOX_IMAGE_ABS="$ENC_IMAGE" BOX_LUKS_KEYFILE_ABS="$KF"
  log "solving the LUKS-encrypted image $BOX_ENC_IMAGE"
elif [ -f "$IMAGE" ]; then
  export BOX_IMAGE_ABS="$IMAGE"
  log "solving the plaintext image $BOX_IMAGE"
else
  die "no box image (run: make build)"
fi
export QEMU_BIN BOX_MACHINE BOX_CPU BOX_MEM_MB
export BOX_FWD_TELNET BOX_FWD_FTP BOX_FWD_SHELL
export BOX_FOOTHOLD_USER BOX_FOOTHOLD_PASS BOX_TRUST_USER BOX_LOOT_DIR BOX_FLAG_DECOY
export BOX_SOLVE_SERIAL="$WORK_DIR/solve-serial.log"
# the flag the box should yield (computed from the owner-side seed); empty if no
# seed is configured (then the test only checks a BU{...} flag is recovered).
export BOX_EXPECT_FLAG="$(sh "$REPO_ROOT/build/flag.sh" 2>/dev/null || true)"

log "solve test: expecting flag ${BOX_EXPECT_FLAG:-<any BU{...}>}"
"$PY" "$REPO_ROOT/build/drive_solve.py"
rc=$?
pkill -9 -f "$(basename "$IMAGE")" 2>/dev/null || true
[ "$rc" = 0 ] && ok "SOLVE TEST PASSED — box is solvable end to end" || die "solve test failed (rc=$rc)"
