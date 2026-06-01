#!/bin/sh
# Stage 90: sanity-check the emitted artifacts WITHOUT running a full solve.
# Static checks only (fast); the real end-to-end solve test is a separate manual
# step documented in docs/walkthrough.md.  Exit non-zero on the first hard failure.
set -eu
. "$(dirname "$0")/lib.sh"

fails=0
chk()  { if eval "$2"; then ok "$1"; else warn "FAIL: $1"; fails=$((fails+1)); fi; }

log "verifying media"
chk "boot floppy present"  '[ -s "$MEDIA_DIR/floppies/boot.flp" ]'
chk "bin set present"      '[ -s "$MEDIA_DIR/dist/bin/bin.aa" ]'
chk "CHECKSUM.MD5 present" '[ -s "$MEDIA_DIR/dist/bin/CHECKSUM.MD5" ]'

log "verifying build artifacts"
chk "install ISO built"    '[ -s "$WORK_DIR/install-${BOX_OS_VERSION}.iso" ]'
chk "box image present"    '[ -s "$IMAGE" ]'
if [ -s "$IMAGE" ]; then
  chk "box image is qcow2"  'qemu-img info "$IMAGE" 2>/dev/null | grep -qi qcow2'
fi

log "verifying loot tarball + flag"
sh "$PAYLOAD_DIR/loot/build-loot.sh" >/dev/null 2>&1 || warn "loot build reported issues"
LOOT="$PAYLOAD_DIR/loot/$BOX_LOOT_NAME"
chk "loot tarball builds"  '[ -s "$LOOT" ]'
if [ -s "$LOOT" ]; then
  chk "loot contains flag.txt" 'tar tzf "$LOOT" | grep -q "maniac/flag.txt"'
  chk "loot flag.txt has a BU{ flag" 'tar xzf "$LOOT" -O maniac/flag.txt 2>/dev/null | grep -q "BU{"'
  chk "loot has README breadcrumb"  'tar tzf "$LOOT" | grep -q "maniac/README"'
fi

log "verifying payload sources"
chk "newgrp trojan source"  '[ -s "$PAYLOAD_DIR/files/newgrp-trojan.c" ]'
chk "rhosts is + +"         'grep -q "^+ +" "$PAYLOAD_DIR/files/rhosts"'
chk "pei breadcrumb present"'grep -q "newgrp -hack root" "$PAYLOAD_DIR/files/pei.bash_history"'
chk "inject-guest present"  '[ -s "$PAYLOAD_DIR/inject-guest.sh" ]'
chk "theme-guest present"   '[ -s "$PAYLOAD_DIR/theme-guest.sh" ]'

log "verifying driver scripts"
chk "drive_install.py"      '[ -s "$REPO_ROOT/build/drive_install.py" ]'
chk "drive_guest.py"        '[ -s "$REPO_ROOT/build/drive_guest.py" ]'

echo
if [ "$fails" -eq 0 ]; then
  ok "verify: all static checks passed"
  log "next: ./run.sh, then solve per docs/walkthrough.md to confirm end-to-end"
else
  die "verify: $fails check(s) failed"
fi
