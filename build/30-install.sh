#!/bin/sh
# Stage 3: create the qcow2 and drive a scripted serial-console install of
# FreeBSD under QEMU.  SLOW: i386 is emulated via TCG (no KVM on this aarch64
# host), so a full boot+install runs in MINUTES, not seconds.  That is expected.
#
# How it works (see docs/field-manual.md "Why the install is driven over serial"):
#   * We create an empty qcow2 (the box's only hard disk -> guest wd0).
#   * We boot the 2.2.8 boot floppy with COM1 on stdio; the 2.2.8 boot blocks
#     speak serial at 9600, and `-h` hands the kernel + sysinstall to the serial
#     console so a program can read/write it.
#   * drive_install.py (pexpect) walks sysinstall's dialogs, installs the 'bin'
#     set from the CD we built, and enables the serial console + a root password
#     in the freshly installed system so later stages can log back in headlessly.
#
# Idempotent-ish: re-running recreates the qcow2 from scratch (a half-installed
# image is worthless).  Pass KEEP_IMAGE=1 to reuse an existing image.
set -eu
. "$(dirname "$0")/lib.sh"

FLOPPY="$MEDIA_DIR/floppies/boot.flp"
ISO="$WORK_DIR/install-${BOX_OS_VERSION}.iso"
DRIVER="$REPO_ROOT/build/drive_install.py"

[ -f "$FLOPPY" ] || die "missing boot floppy $FLOPPY (run: make fetch)"
[ -f "$ISO" ]    || die "missing install CD $ISO (run: make iso)"
[ -f "$DRIVER" ] || die "missing $DRIVER"

need "$QEMU_BIN"; need qemu-img

# pexpect: prefer the repo .venv if 00-deps created one, else system python.
PY="python3"
if [ -x "$REPO_ROOT/.venv/bin/python3" ]; then PY="$REPO_ROOT/.venv/bin/python3"; fi
"$PY" -c 'import pexpect' 2>/dev/null || die "pexpect missing (run: make deps)"

mkdir -p "$DIST_DIR" "$WORK_DIR"

if [ "${KEEP_IMAGE:-0}" = "1" ] && [ -f "$IMAGE" ]; then
  log "reusing existing image $IMAGE (KEEP_IMAGE=1)"
else
  log "creating fresh qcow2 $IMAGE ($BOX_DISK_SIZE)"
  rm -f "$IMAGE"
  qemu-img create -f qcow2 "$IMAGE" "$BOX_DISK_SIZE" >/dev/null || die "qemu-img create failed"
fi

# Everything the driver needs, passed via env so box.env stays the single source.
# (box.env is already sourced into this shell by lib.sh, so these are populated.)
export BOX_IMAGE_ABS="$IMAGE"
export BOX_FLOPPY_ABS="$FLOPPY"
export BOX_ISO_ABS="$ISO"
export BOX_SERIAL_LOG="$WORK_DIR/install-serial.log"
export QEMU_BIN BOX_MACHINE BOX_CPU BOX_MEM_MB BOX_SERIAL_SPEED
export BOX_ROOT_PASS BOX_HOSTNAME
rc=0; "$PY" "$DRIVER" || rc=$?
# belt-and-suspenders: never leave a qemu holding the image lock (proot pid xlation)
pkill -9 -f "$(basename "$IMAGE")" 2>/dev/null || true
[ "$rc" = 0 ] || die "install driver exited $rc (see $WORK_DIR/install-serial.log)"
ok "install driver finished"
