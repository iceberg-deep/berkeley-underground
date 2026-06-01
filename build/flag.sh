#!/bin/sh
# Print the live flag for the current seed + instance id.  The box reveals the
# SAME value only at runtime (decoded into RAM, never stored as plaintext on disk)
# — this is the owner's copy so you know what the player is hunting for.  The SEED
# is owner-only and MUST stay out of the repo/image/history; it is read from the
# $BOX_FLAG_SEED env var, or a git-ignored secret/flag.seed file.  Deterministic:
#     token = first 16 hex of md5( seed + instance_id )    flag = BU{ token _ suffix }
set -eu
. "$(dirname "$0")/lib.sh"

if [ -n "${BOX_FLAG_SEED:-}" ]; then
  SEED="$BOX_FLAG_SEED"
elif [ -r "$REPO_ROOT/secret/flag.seed" ]; then
  SEED=$(cat "$REPO_ROOT/secret/flag.seed")
else
  die "no flag seed: export BOX_FLAG_SEED or create secret/flag.seed (git-ignored)"
fi

token=$(printf '%s' "${SEED}${BOX_FLAG_INSTANCE}" | md5sum | cut -c1-16)
printf 'BU{%s_%s}\n' "$token" "$BOX_FLAG_SUFFIX"
