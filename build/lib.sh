#!/bin/sh
# Shared helpers for the build pipeline. Source this from each build/NN-*.sh.
# POSIX sh (the dev host's /bin/sh) — keep it portable.

set -eu

# Resolve repo root regardless of CWD (this file lives in build/).
# Callers in build/ invoke as `sh build/NN.sh`, so $0's dir is build/.  A caller
# elsewhere (e.g. run.sh at the repo root) can preset REPO_ROOT to skip this.
if [ -z "${REPO_ROOT:-}" ]; then
  LIB_DIR=$(cd "$(dirname "$0")" && pwd)
  REPO_ROOT=$(cd "$LIB_DIR/.." && pwd)
fi
export REPO_ROOT

# Load box parameters.  BOX_ENV_FILE selects the box (default box.env = Box 1);
# build/40-inject2.sh etc. set BOX_ENV_FILE=box2.env to build Box 2 on the same
# library.
. "$REPO_ROOT/config/${BOX_ENV_FILE:-box.env}"

# ── logging ────────────────────────────────────────────────────────────────
_ts() { date '+%H:%M:%S'; }
log()  { printf '\033[1;36m[%s] %s\033[0m\n' "$(_ts)" "$*" >&2; }
ok()   { printf '\033[1;32m[%s] OK: %s\033[0m\n' "$(_ts)" "$*" >&2; }
warn() { printf '\033[1;33m[%s] WARN: %s\033[0m\n' "$(_ts)" "$*" >&2; }
die()  { printf '\033[1;31m[%s] FATAL: %s\033[0m\n' "$(_ts)" "$*" >&2; exit 1; }

# ── host tool checks ─────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || die "missing host tool: $1 (run build/00-deps.sh)"; }

# QEMU binary (overridable via box.env).
QEMU_BIN="${BOX_QEMU:-qemu-system-i386}"

# Absolute paths derived from box.env (which uses repo-relative paths).
MEDIA_DIR="$REPO_ROOT/$BOX_MEDIA_DIR"
DIST_DIR="$REPO_ROOT/$BOX_DIST_DIR"
WORK_DIR="$REPO_ROOT/$BOX_WORK_DIR"
IMAGE="$REPO_ROOT/$BOX_IMAGE"
ENC_IMAGE="$REPO_ROOT/${BOX_ENC_IMAGE:-dist/box1-enc.qcow2}"
LUKS_KEYFILE="$REPO_ROOT/${BOX_LUKS_KEYFILE:-secret/luks.key}"
PAYLOAD_DIR="$REPO_ROOT/build/${BOX_PAYLOAD_SUBDIR:-payloads}"

# Resolve the LUKS key: $BOX_LUKS_KEY env wins, else the keyfile.  Writes the key
# to a 0600 temp file and echoes its path (QEMU's secret object reads from a file).
luks_keyfile() {
  if [ -n "${BOX_LUKS_KEY:-}" ]; then
    _kf="$WORK_DIR/.luks.key"; mkdir -p "$WORK_DIR"
    printf '%s' "$BOX_LUKS_KEY" > "$_kf"; chmod 600 "$_kf"; printf '%s\n' "$_kf"
  elif [ -f "$LUKS_KEYFILE" ]; then
    printf '%s\n' "$LUKS_KEYFILE"
  else
    return 1
  fi
}

mkdirs() { mkdir -p "$MEDIA_DIR" "$DIST_DIR" "$WORK_DIR"; }

# ── QEMU invocation (single source of truth) ──────────────────────────────────
# Usage: qemu_args_base   -> echoes the common machine definition.
# Callers append -fda/-cdrom/-hdb/-boot/-serial as needed.
qemu_args_base() {
  printf '%s\n' \
    -M "$BOX_MACHINE" -cpu "$BOX_CPU" -m "$BOX_MEM_MB" \
    -drive "file=$IMAGE,format=qcow2,if=ide,index=0,media=disk" \
    -rtc base=localtime -no-reboot
}

# Host-only user-mode networking with NO route/DNS to the internet, plus the
# period-service port forwards the player needs. 'restrict=on' blocks the guest
# from reaching anything but the host-forwarded ports — this is the safety
# guarantee (no bridged/internet access). Build-time installs that legitimately
# need upstream fetch override this with their own -netdev.
qemu_net_hostonly() {
  hostfwd="hostfwd=tcp:127.0.0.1:${BOX_FWD_TELNET}-:23"
  hostfwd="$hostfwd,hostfwd=tcp:127.0.0.1:${BOX_FWD_FTP}-:21"
  hostfwd="$hostfwd,hostfwd=tcp:127.0.0.1:${BOX_FWD_SHELL}-:513"
  printf '%s\n' -netdev "user,id=n0,restrict=on,$hostfwd" -device "ne2k_pci,netdev=n0"
}

# ── checksum helpers ───────────────────────────────────────────────────────────
sha256_of() { sha256sum "$1" | awk '{print $1}'; }
