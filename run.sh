#!/bin/sh
# Boot the finished Box 1 — HOST-ONLY.  The guest gets QEMU user-mode networking
# with restrict=on (no route or DNS to the internet); the only way in is the
# host-forwarded period-service ports on 127.0.0.1.  This is the safety contract:
# a deliberately-vulnerable 1990s box that cannot reach anything but your loopback.
#
# Prefers the LUKS-encrypted distributable (dist/...enc.qcow2) if present, reading
# the key from $BOX_LUKS_KEY or the git-ignored keyfile; otherwise boots the
# plaintext build image.  Serial console + monitor are muxed onto this terminal
# (-nographic); the PLAYER uses the forwarded ports, not this console.  Stop with
# the monitor (Ctrl-A C, then `quit`) or Ctrl-C.
set -eu
REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
. "$REPO_ROOT/build/lib.sh"
need "$QEMU_BIN"

# Choose disk: encrypted distributable (needs key) > plaintext build image.
SECRET_ARGS=""
if [ -f "$ENC_IMAGE" ]; then
  KF=$(luks_keyfile) || die "encrypted image present but no LUKS key (set BOX_LUKS_KEY or create $BOX_LUKS_KEYFILE)"
  DISK_IMG="$ENC_IMAGE"
  SECRET_ARGS="-object secret,id=sec0,file=$KF"
  DRIVE="file=$ENC_IMAGE,format=qcow2,if=ide,index=0,media=disk,encrypt.key-secret=sec0"
  log "booting ENCRYPTED image $BOX_ENC_IMAGE (LUKS; key from ${BOX_LUKS_KEY:+\$BOX_LUKS_KEY}${BOX_LUKS_KEY:-$BOX_LUKS_KEYFILE})"
elif [ -f "$IMAGE" ]; then
  DISK_IMG="$IMAGE"
  DRIVE="file=$IMAGE,format=qcow2,if=ide,index=0,media=disk"
  log "booting plaintext build image $BOX_IMAGE (run 'make luks' for the encrypted distributable)"
else
  die "no box image — run: make build"
fi

log "Box 1 '$BOX_HOSTNAME' host-only; internet unreachable from guest.  Attack surface on 127.0.0.1:"
log "  telnet -> :$BOX_FWD_TELNET (login $BOX_FOOTHOLD_USER) | ftp -> :$BOX_FWD_FTP | rlogin/rsh -> :$BOX_FWD_SHELL"
log "console + monitor on this terminal (Ctrl-A C for monitor, 'quit' to stop)"

# shellcheck disable=SC2046,SC2086
exec "$QEMU_BIN" -machine "$BOX_MACHINE,graphics=off" -cpu "$BOX_CPU" -m "$BOX_MEM_MB" \
  $SECRET_ARGS -drive "$DRIVE" -rtc base=localtime -no-reboot \
  $(qemu_net_hostonly) -boot c -nographic
