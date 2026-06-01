#!/bin/sh
# Stage 70: wrap the finished plaintext qcow2 in QEMU-native LUKS encryption,
# producing the DISTRIBUTABLE encrypted image.  Offline enumeration of this image
# (qemu-nbd / virt-filesystems / libguestfs / a raw loop mount) hits ciphertext,
# not a mountable filesystem.  Defense-in-depth: in a distributed VM the key must
# still reach QEMU to boot, so this raises effort, it is not absolute (see docs).
#
# 2.2.8 cannot do guest-side encryption (no GELI/LUKS until FreeBSD 6), so the LUKS
# layer lives at the QEMU/qcow2 layer.  The guest sees a normal disk; QEMU
# encrypts/decrypts transparently with the key.
set -eu
. "$(dirname "$0")/lib.sh"

need "$QEMU_BIN"; need qemu-img

[ -f "$IMAGE" ] || die "no plaintext image $IMAGE (run: make build)"

# Key: reuse $BOX_LUKS_KEY / the keyfile if present, else mint a strong random key.
if [ -z "${BOX_LUKS_KEY:-}" ] && [ ! -f "$LUKS_KEYFILE" ]; then
  log "no LUKS key found — generating a random one at $LUKS_KEYFILE"
  mkdir -p "$(dirname "$LUKS_KEYFILE")"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n' > "$LUKS_KEYFILE"
  else
    head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$LUKS_KEYFILE"
  fi
  chmod 600 "$LUKS_KEYFILE"
  warn "KEEP $LUKS_KEYFILE SAFE and out of git — it is the only way to boot the image"
fi
KF=$(luks_keyfile) || die "no LUKS key (set BOX_LUKS_KEY or create $LUKS_KEYFILE)"

log "encrypting $IMAGE -> $ENC_IMAGE (LUKS via qemu-img convert)"
rm -f "$ENC_IMAGE"
qemu-img convert \
  --object "secret,id=sec0,file=$KF" \
  -O qcow2 -o "encrypt.format=luks,encrypt.key-secret=sec0" \
  "$IMAGE" "$ENC_IMAGE" || die "qemu-img LUKS convert failed"

# Sanity: the encrypted image must report encrypted, and be UNreadable without the key.
qemu-img info "$ENC_IMAGE" 2>/dev/null | grep -qi 'encrypted: yes' \
  || die "result is not marked encrypted"
if qemu-img convert -O raw "$ENC_IMAGE" /dev/null 2>/dev/null; then
  die "SECURITY: encrypted image was readable WITHOUT the key — aborting"
fi

ok "LUKS distributable: $ENC_IMAGE ($(du -h "$ENC_IMAGE" | awk '{print $1}'))"
log "boot it with: ./run.sh   (reads the key from $LUKS_KEYFILE or \$BOX_LUKS_KEY)"
log "ship $ENC_IMAGE + the keyfile SEPARATELY; never bake the key into the image"
