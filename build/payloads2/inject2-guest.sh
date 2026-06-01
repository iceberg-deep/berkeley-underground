#!/bin/sh
# Runs as root INSIDE the cloned Box 1 base image (FreeBSD 2.2.8, SunOS-costumed),
# delivered via the tar-on-raw-disk channel (build/drive_guest.py).  Box 2 "The
# Traced Call" turns the gaia base into teal.csn.org and plants the anti-forensics
# challenge:
#   * NEUTRALISE Box 1's vuln chain (so the intended Box 2 path is the way)
#   * trojaned setuid /usr/bin/login  -> magic word gives root (cf 4015/4016/4007)
#   * a watcher (tripwire.sh) that releases the real flag ONLY when the intruder's
#     traces are gone from wtmp/utmp/lastlog + the accounting log (cf 4005/4016)
#   * the toolkit cache (zap.c + notes) and a pre-seeded billing log to scrub
# POSIX/ash only (2.2.8 /bin/sh).  Config comes from box-guest.env (written by
# build/40-inject2.sh so config/box2.env stays the single source).
set -u
HERE=$(dirname "$0")
. "$HERE/box-guest.env"

note() { echo ">> $*"; }
fail() { echo "!! FATAL: $*" >&2; exit 1; }

CC=/usr/bin/cc
[ -x "$CC" ] || CC=/usr/bin/gcc
[ -x "$CC" ] || fail "no C compiler at /usr/bin/cc or /usr/bin/gcc"

RCLOCAL=/etc/rc.conf.local
set_rc() {  # key value  (idempotent: drop prior line for key, append ours)
  if [ -f "$RCLOCAL" ]; then
    grep -v "^$1=" "$RCLOCAL" > "$RCLOCAL.new" 2>/dev/null
    cp "$RCLOCAL.new" "$RCLOCAL"; rm -f "$RCLOCAL.new"
  fi
  echo "$1=\"$2\"" >> "$RCLOCAL"
}

# ── 1. neutralise Box 1's vuln chain (we cloned the gaia base) ──────────────────
note "removing Box 1 artifacts (newgrp setuid, dono trust, gen-flag, loot)"
[ -f /usr/bin/newgrp ] && chmod u-s /usr/bin/newgrp 2>/dev/null   # kill the setuid privesc
rm -f /home/dono/.rhosts                                          # kill the rsh/rlogin trust
rm -f /usr/local/sbin/gen-flag.sh                                 # Box 1 flag generator
if [ -f /etc/rc.local ]; then                                     # and its boot hook
  grep -v 'gen-flag.sh' /etc/rc.local > /tmp/rl.$$ 2>/dev/null
  cp /tmp/rl.$$ /etc/rc.local; rm -f /tmp/rl.$$
fi
rm -rf /usr/src/sys/maniac                                        # Box 1 loot
rm -f /etc/.fb 2>/dev/null                                        # Box 1 obfuscated flag (rewritten below)
rm -f /home/pei/.bash_history /home/$FOOTHOLD_USER/handover.txt \
      /var/ftp/pub/incoming/handover.txt 2>/dev/null              # Box 1 breadcrumbs
# (kept on purpose: accounts incl. the $FOOTHOLD_USER foothold, inetd services,
#  host-only network, the SunOS costume.)

# ── 2. re-identify the host as teal.csn.org ────────────────────────────────────
note "retheming host identity -> $HOSTNAME_FQDN"
set_rc hostname "$HOSTNAME_FQDN"
cp "$HERE/files/motd.notice" /etc/motd                            # the "you are watched" notice
chmod 644 /etc/motd

# ── 3. the root vector: trojaned setuid /usr/bin/login ─────────────────────────
note "installing trojaned login (magic '$LOGIN_MAGIC' -> root)"
LOGIN=/usr/bin/login
[ -f "$LOGIN" ] || fail "no $LOGIN in base image"
[ -f /usr/bin/login.real ] || cp -p "$LOGIN" /usr/bin/login.real  # stash the genuine login once
"$CC" -DMAGIC="\"$LOGIN_MAGIC\"" -DREAL='"/usr/bin/login.real"' \
      -o /tmp/login.$$ "$HERE/login-trojan.c" || fail "login trojan compile failed"
cp /tmp/login.$$ "$LOGIN"; rm -f /tmp/login.$$
chown root:wheel "$LOGIN"; chmod 4755 "$LOGIN"
test -u "$LOGIN"            || fail "login setuid bit not set"
test -x /usr/bin/login.real || fail "genuine login.real backup missing"

# ── 4. the toolkit cache (a prior intruder's stash; cf 4001) ───────────────────
note "planting toolkit cache in /home/$TRUST_USER"
CACHE="/home/$TRUST_USER"            # dono's home — kept as the cache (trust removed above)
mkdir -p "$CACHE"
cp "$HERE/zap.c"               "$CACHE/zap.c"
cp "$HERE/files/cache-notes.txt" "$CACHE/notes"
chmod 644 "$CACHE/zap.c" "$CACHE/notes"
chmod 755 "$CACHE"

# ── 5. the accounting / billing log (pre-seeded; the grep -v target) ───────────
note "seeding accounting log $ACCT_LOG"
mkdir -p "$(dirname "$ACCT_LOG")"
cp "$HERE/files/awtmp.seed" "$ACCT_LOG"
chown root:wheel "$ACCT_LOG"; chmod 644 "$ACCT_LOG"   # root can edit; readable for grep
grep -q "$FOOTHOLD_USER" "$ACCT_LOG" || fail "accounting log missing intruder signature"

# ── 6. off-disk real flag + decoy trophy + the watcher ─────────────────────────
[ -n "${FLAG_REAL:-}" ] || fail "FLAG_REAL not provided"
note "installing off-disk flag + tripwire watcher"
echo "$FLAG_REAL" | rev > /etc/.fb                    # obfuscated (reversed), root-only
test "`rev /etc/.fb`" = "$FLAG_REAL" || fail "flag obfuscation (rev) round-trip failed"
chown root:wheel /etc/.fb; chmod 600 /etc/.fb

cp "$HERE/tripwire.sh" /usr/local/sbin/tripwire.sh
chown root:wheel /usr/local/sbin/tripwire.sh; chmod 700 /usr/local/sbin/tripwire.sh

# pre-seed the on-disk DECOY trophy so it exists before the first sweep (the real
# flag will be overlaid in RAM by tripwire once the logs are clean).
mkdir -p "$LOOT_DIR"; chmod 700 "$LOOT_DIR"
printf 'The sysadmin reviews `last` and the billing logs.\nYour session is still in them -- the call was traced.\n\n%s\n\nScrub wtmp, utmp, lastlog AND the accounting logs, then check back.\n' \
  "$FLAG_DECOY" > "$LOOT_DIR/trophy.txt"
chmod 600 "$LOOT_DIR/trophy.txt"

# launch the watcher loop at every multiuser boot via /etc/rc.local
[ -f /etc/rc.local ] || { echo '#!/bin/sh' > /etc/rc.local; chmod 755 /etc/rc.local; }
if ! grep -q 'tripwire.sh' /etc/rc.local; then
  cat >> /etc/rc.local <<EOF
( while : ; do /usr/local/sbin/tripwire.sh "$FOOTHOLD_USER" "$INTRUDER_SRCHOST" ; sleep $WATCH_INTERVAL ; done ) &
EOF
fi

note "inject2-guest complete"
exit 0
