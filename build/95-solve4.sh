#!/bin/sh
# Stage 95 (Box 4): end-to-end solve gate.  Boots host-only and walks the backdoor
# chain over telnet (build/drive_solve4.py).  Exits 0 only if root is reached
# through the in.pmd backdoor AND the real flag is recovered.
set -eu
export BOX_ENV_FILE=box4.env
. "$(dirname "$0")/lib.sh"
need telnet; need "$QEMU_BIN"
PY="python3"; [ -x "$REPO_ROOT/.venv/bin/python3" ] && PY="$REPO_ROOT/.venv/bin/python3"
"$PY" -c 'import pexpect' 2>/dev/null || die "pexpect missing (run: make deps)"

IMG="$IMAGE"
if [ -f "$ENC_IMAGE" ]; then IMG="$ENC_IMAGE"; export BOX_LUKS_KEYFILE_ABS="$(luks_keyfile)"; fi
[ -f "$IMG" ] || die "no image $IMG (run build/40-inject4.sh)"

export BOX_IMAGE_ABS="$IMG"
export QEMU_BIN BOX_MACHINE BOX_CPU BOX_MEM_MB
export BOX_FWD_TELNET BOX_FWD_FTP BOX_FWD_SHELL
export BOX_FOOTHOLD_USER BOX_FOOTHOLD_PASS BOX_BACKDOOR_PORT BOX_BACKDOOR_MAGIC
export BOX_LOOT_DIR BOX_LOOT_NAME BOX_FLAG_DECOY
export BOX_SOLVE_SERIAL="$WORK_DIR/solve4-serial.log"
export BOX_EXPECT_FLAG="$(sh "$REPO_ROOT/build/flag.sh")"
log "Box 4 solve: image $(basename "$IMG"); expecting $BOX_EXPECT_FLAG"
"$PY" "$REPO_ROOT/build/drive_solve4.py" && ok "BOX 4 SOLVE PASSED" || die "Box 4 solve failed"
