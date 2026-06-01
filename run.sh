#!/bin/sh
# Boot the finished Box 1 — HOST-ONLY.  The guest gets QEMU user-mode networking
# with restrict=on (no route or DNS to the internet); the only way in is the
# host-forwarded period-service ports on 127.0.0.1.  This is the safety contract:
# a deliberately-vulnerable 1990s box that cannot reach anything but your loopback.
#
# Serial console + QEMU monitor are muxed onto this terminal (-nographic).  The
# PLAYER does not use this console — they attack the forwarded ports below.  To
# leave the console without killing the box, detach your terminal; to stop it,
# use the monitor (Ctrl-A C, then `quit`) or just Ctrl-C.
set -eu
REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
. "$REPO_ROOT/build/lib.sh"

[ -f "$IMAGE" ] || die "no box image $IMAGE — run: make build"
need "$QEMU_BIN"

log "booting Box 1 '$BOX_HOSTNAME' (host-only; internet unreachable from guest)"
log "attack surface on 127.0.0.1:"
log "  telnet  -> 127.0.0.1:$BOX_FWD_TELNET   (login as $BOX_FOOTHOLD_USER)"
log "  ftp     -> 127.0.0.1:$BOX_FWD_FTP"
log "  rlogin/rsh (513) -> 127.0.0.1:$BOX_FWD_SHELL"
log "console + monitor are on this terminal (Ctrl-A C for monitor, 'quit' to stop)"

# qemu_args_base / qemu_net_hostonly emit newline-separated args; word-splitting
# (no spaces inside any single arg) reassembles them correctly here.
# shellcheck disable=SC2046
exec "$QEMU_BIN" $(qemu_args_base) $(qemu_net_hostonly) -boot c -nographic
