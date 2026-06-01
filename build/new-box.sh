#!/bin/sh
# new-box.sh — scaffold a new box on the proven pipeline from templates/.
# Usage: build/new-box.sh <N> <hostname> <domain>
#   e.g. build/new-box.sh 3 ariel sdsc.edu
# Creates config/box<N>.env, build/payloads<N>/inject<N>-guest.sh (+ files/),
# and build/40-inject<N>.sh — each with @@N@@/@@HOST@@/@@DOMAIN@@ filled in.
# Idempotent-ish: refuses to clobber existing files.  See docs/new-box-checklist.md.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T="$ROOT/templates"

[ $# -eq 3 ] || { echo "usage: $0 <N> <hostname> <domain>" >&2; exit 1; }
N="$1"; HOST="$2"; DOMAIN="$3"
case "$N" in ''|*[!0-9]*) echo "N must be a number" >&2; exit 1;; esac

fill() {  # template -> dest (refuse to clobber)
  src="$1"; dst="$2"
  [ -f "$src" ] || { echo "missing template $src" >&2; exit 1; }
  [ -e "$dst" ] && { echo "refusing to clobber existing $dst" >&2; exit 1; }
  sed -e "s/@@N@@/$N/g" -e "s/@@HOST@@/$HOST/g" -e "s/@@DOMAIN@@/$DOMAIN/g" "$src" > "$dst"
}

mkdir -p "$ROOT/build/payloads$N/files"
fill "$T/box.env.template"          "$ROOT/config/box$N.env"
fill "$T/inject-guest.template.sh"  "$ROOT/build/payloads$N/inject$N-guest.sh"
fill "$T/40-inject.template.sh"     "$ROOT/build/40-inject$N.sh"
chmod +x "$ROOT/build/payloads$N/inject$N-guest.sh" "$ROOT/build/40-inject$N.sh"

echo "scaffolded Box $N ($HOST.$DOMAIN):"
echo "  config/box$N.env"
echo "  build/payloads$N/inject$N-guest.sh   (+ files/)"
echo "  build/40-inject$N.sh"
echo
echo "next: fill the TODOs (config + inject), copy build/drive_solve2.py ->"
echo "      build/drive_solve$N.py and adjust the chain, then build/40-inject$N.sh."
echo "see docs/new-box-checklist.md"
