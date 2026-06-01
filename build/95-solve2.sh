#!/bin/sh
# Stage 95 (Box 2): end-to-end solve gate.  Boots the box host-only and walks the
# Traced-Call chain over telnet (build/drive_solve2.py).  Exits 0 only if root is
# reached AND the real flag is recovered after the logs are scrubbed.
set -eu
export BOX_ENV_FILE=box2.env
. "$(dirname "$0")/lib.sh"
need telnet; need "$QEMU_BIN"
PY="python3"; [ -x "$REPO_ROOT/.venv/bin/python3" ] && PY="$REPO_ROOT/.venv/bin/python3"
"$PY" -c 'import pexpect' 2>/dev/null || die "pexpect missing (run: make deps)"

IMG="$IMAGE"
if [ -f "$ENC_IMAGE" ]; then
  IMG="$ENC_IMAGE"; export BOX_LUKS_KEYFILE_ABS="$(luks_keyfile)"
fi
[ -f "$IMG" ] || die "no image $IMG (run build/40-inject2.sh)"

export BOX_IMAGE_ABS="$IMG"
export QEMU_BIN BOX_MACHINE BOX_CPU BOX_MEM_MB
export BOX_FWD_TELNET BOX_FWD_FTP BOX_FWD_SHELL
export BOX_FOOTHOLD_USER BOX_FOOTHOLD_PASS BOX_TRUST_USER BOX_LOGIN_MAGIC
export BOX_LOOT_DIR BOX_ACCT_LOG BOX_WATCH_INTERVAL BOX_FLAG_DECOY
export BOX_SOLVE_SERIAL="$WORK_DIR/solve2-serial.log"
export BOX_EXPECT_FLAG="$(sh "$REPO_ROOT/build/flag.sh")"
log "Box 2 solve: image $(basename "$IMG"); expecting $BOX_EXPECT_FLAG"
"$PY" "$REPO_ROOT/build/drive_solve2.py" && ok "BOX 2 SOLVE PASSED" || die "Box 2 solve failed"
