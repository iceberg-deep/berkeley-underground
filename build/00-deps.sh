#!/bin/sh
# Stage 0: ensure host build tools exist.
#
# This dev host is an unprivileged proot (uid != 0, sudo needs a password we do
# not have) BUT /usr, /var/lib/dpkg, /etc are writable and apt's archives are
# cached, so `fakeroot apt-get install` works for packages whose postinst we do
# not actually need to run. ISO tooling is installed that way; pexpect via pip.
# On a normal host with real root, just `apt-get install` / `pip install`.
set -eu
. "$(dirname "$0")/lib.sh"

log "checking host build tools"

# --- QEMU (already verified present in this environment) ---
need "$QEMU_BIN"
need qemu-img
ok "qemu: $($QEMU_BIN --version | head -1)"

# --- core unix tools ---
for t in curl tar gzip awk sed md5sum sha256sum python3; do need "$t"; done

# --- ISO builder (genisoimage|mkisofs|xorriso) ---
if command -v genisoimage >/dev/null 2>&1 || command -v mkisofs >/dev/null 2>&1 \
   || command -v xorriso >/dev/null 2>&1; then
  ok "iso builder present"
else
  warn "no ISO builder; attempting fakeroot apt-get install genisoimage"
  if command -v fakeroot >/dev/null 2>&1; then
    fakeroot apt-get install -y genisoimage >/dev/null 2>&1 || \
      warn "genisoimage install reported errors (postinst); checking binary anyway"
  fi
  command -v genisoimage >/dev/null 2>&1 || command -v mkisofs >/dev/null 2>&1 \
    || die "could not obtain an ISO builder (install genisoimage/xorriso)"
  ok "iso builder installed"
fi

# --- pexpect (output-driven installer/inject driver) ---
if python3 -c 'import pexpect' 2>/dev/null; then
  ok "python pexpect present"
else
  warn "installing pexpect into .venv"
  python3 -m venv "$REPO_ROOT/.venv" 2>/dev/null || python3 -m venv --system-site-packages "$REPO_ROOT/.venv"
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.venv/bin/activate"
  pip -q install pexpect || die "pip install pexpect failed"
  ok "pexpect installed in .venv (activate it, or scripts will find it automatically)"
fi

ok "host deps satisfied"
