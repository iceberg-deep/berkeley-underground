#!/bin/sh
# Runs as root INSIDE the installed FreeBSD 2.2.8 guest (delivered via the
# tar-on-raw-disk channel; see build/drive_guest.py).  It plants the REAL
# weaknesses that make the intended path work — nothing here is simulated:
#   * unprivileged login accounts (brian foothold, pei breadcrumb, dono trust)
#   * a world-readable ~pei/.bash_history breadcrumb
#   * dono's .rhosts "+ +"  -> rsh/rlogin trust bypasses authentication
#   * a setuid-root trojaned newgrp  -> `newgrp -hack root` gives a root shell
#   * inetd telnet/ftp/shell/login/finger enabled, static net for host-fwd
#   * the planted "stolen source" loot tarball (flag inside) as the exfil object
#   * an inert in.pmd artifact (period red herring; not wired to inetd)
#
# POSIX/ash only (2.2.8 /bin/sh).  Sourced config comes from box-guest.env,
# written by build/40-inject.sh so config/box.env stays the single source.
set -u
HERE=$(dirname "$0")
. "$HERE/box-guest.env"

note() { echo ">> $*"; }
fail() { echo "!! FATAL: $*" >&2; exit 1; }

# ── accounts ───────────────────────────────────────────────────────────────────
addgroup() {  # name gid
  grep -q "^$1:" /etc/group || echo "$1:*:$2:" >> /etc/group
}
adduser() {   # user hash uid gecos home shell
  _u=$1; _h=$2; _id=$3; _g=$4; _home=$5; _sh=$6
  if ! grep -q "^$_u:" /etc/master.passwd; then
    # name:passwd:uid:gid:class:change:expire:gecos:home:shell
    echo "$_u:$_h:$_id:$_id::0:0:$_g:$_home:$_sh" >> /etc/master.passwd
  fi
  mkdir -p "$_home"
  chown "$_id:$_id" "$_home"
  chmod 755 "$_home"
}

note "creating accounts"
addgroup "$FOOTHOLD_USER" "$FOOTHOLD_UID"
addgroup "$PEI_USER"      "$PEI_UID"
addgroup "$TRUST_USER"    "$TRUST_UID"
adduser "$FOOTHOLD_USER" "$FOOTHOLD_HASH" "$FOOTHOLD_UID" "$FOOTHOLD_USER contractor" "/home/$FOOTHOLD_USER" /bin/sh
adduser "$PEI_USER"      "$PEI_HASH"      "$PEI_UID"      "pei (former sysadmin)"      "/home/$PEI_USER"      /bin/sh
adduser "$TRUST_USER"    "$TRUST_HASH"    "$TRUST_UID"    "$TRUST_USER (build acct)"   "/home/$TRUST_USER"    /bin/sh
pwd_mkdb -p /etc/master.passwd || fail "pwd_mkdb failed"
grep -q "^$FOOTHOLD_USER:" /etc/passwd || fail "foothold account not in passwd db"

# ── breadcrumbs ────────────────────────────────────────────────────────────────
note "planting breadcrumbs"
# pei's shell history is world-readable on purpose — it leaks the whole path.
cp "$HERE/files/pei.bash_history" "/home/$PEI_USER/.bash_history"
chown "$PEI_UID:$PEI_UID" "/home/$PEI_USER/.bash_history"
chmod 644 "/home/$PEI_USER/.bash_history"
# handover note lands in the foothold user's home (the "new contractor").
cp "$HERE/files/handover.txt" "/home/$FOOTHOLD_USER/handover.txt"
chown "$FOOTHOLD_UID:$FOOTHOLD_UID" "/home/$FOOTHOLD_USER/handover.txt"
chmod 644 "/home/$FOOTHOLD_USER/handover.txt"

# ── the r-services trust: dono trusts everyone ("+ +") ─────────────────────────
note "planting dono .rhosts trust"
cp "$HERE/files/rhosts" "/home/$TRUST_USER/.rhosts"
chown "$TRUST_UID:$TRUST_UID" "/home/$TRUST_USER/.rhosts"
chmod 600 "/home/$TRUST_USER/.rhosts"   # must be owned by dono, not group/other-writable

# ── setuid-root trojaned newgrp ────────────────────────────────────────────────
note "compiling + installing setuid newgrp trojan"
# 2.2.8 /bin/sh (ash) has no working `command -v`; check the compiler by path.
CC=/usr/bin/cc
[ -x "$CC" ] || CC=/usr/bin/gcc
[ -x "$CC" ] || fail "no C compiler at /usr/bin/cc or /usr/bin/gcc"
note "using compiler $CC"
"$CC" -o /tmp/newgrp "$HERE/files/newgrp-trojan.c" || fail "newgrp compile failed"
cp /tmp/newgrp /usr/bin/newgrp
chown root:wheel /usr/bin/newgrp
chmod 4755 /usr/bin/newgrp
test -u /usr/bin/newgrp || fail "newgrp setuid bit not set"
rm -f /tmp/newgrp

# ── enable the period network services ─────────────────────────────────────────
note "enabling inetd services (telnet/ftp/shell/login/finger)"
TAB=$(printf '\t')
sed -e "s/^#[ $TAB]*telnet/telnet/" \
    -e "s/^#[ $TAB]*ftp/ftp/" \
    -e "s/^#[ $TAB]*shell/shell/" \
    -e "s/^#[ $TAB]*login/login/" \
    -e "s/^#[ $TAB]*finger/finger/" \
    /etc/inetd.conf > /tmp/inetd.conf && cp /tmp/inetd.conf /etc/inetd.conf
rm -f /tmp/inetd.conf

note "configuring boot-time services + static host-only network"
# Network/service knobs go in /etc/rc.conf.local, which the shipped /etc/rc.conf
# sources LAST ("if [ -f /etc/rc.conf.local ]; then . /etc/rc.conf.local; fi") —
# the intended, reliable override point (defaults in rc.conf are set earlier and we
# win).  Idempotent: drop any prior line for the key, then append ours.
RCLOCAL=/etc/rc.conf.local
set_rc() {  # key value
  if [ -f "$RCLOCAL" ]; then
    grep -v "^$1=" "$RCLOCAL" > "$RCLOCAL.new" 2>/dev/null
    cp "$RCLOCAL.new" "$RCLOCAL"; rm -f "$RCLOCAL.new"
  fi
  echo "$1=\"$2\"" >> "$RCLOCAL"
}
set_rc inetd_enable        "YES"
set_rc hostname            "$HOSTNAME_FQDN"
set_rc network_interfaces  "$GUEST_IFACE lo0"
set_rc "ifconfig_$GUEST_IFACE" "inet $GUEST_IP netmask 255.255.255.0"
set_rc defaultrouter       "$GUEST_GW"

# ── anonymous FTP (handover note + welcome banner) ─────────────────────────────
note "configuring anonymous ftp"
addgroup ftp 14
adduser ftp "*" 14 "Anonymous FTP" /var/ftp /nonexistent
pwd_mkdb -p /etc/master.passwd || fail "pwd_mkdb (ftp) failed"  # rebuild db incl. ftp
mkdir -p /var/ftp/pub/incoming /var/ftp/bin /var/ftp/etc
cp "$HERE/files/handover.txt" /var/ftp/pub/incoming/handover.txt
chmod 644 /var/ftp/pub/incoming/handover.txt
cp "$HERE/files/ftp-welcome.txt" /etc/ftpwelcome
chmod 644 /etc/ftpwelcome

# ── the loot: planted "stolen source" with the flag inside ─────────────────────
note "planting loot at $LOOT_DIR"
mkdir -p "$(dirname "$LOOT_DIR")"
tar xzf "$HERE/loot/$LOOT_NAME" -C "$(dirname "$LOOT_DIR")" || fail "loot extract failed"
cp "$HERE/loot/$LOOT_NAME" "$LOOT_DIR/$LOOT_NAME"
chown -R root:wheel "$LOOT_DIR"
chmod -R go-w "$LOOT_DIR"
test -f "$LOOT_DIR/$LOOT_NAME" || fail "loot tarball missing after plant"
test -f "$LOOT_DIR/README"     || fail "loot README missing (breadcrumb expects it)"

# ── inert period artifact: in.pmd (compiled, placed, NOT enabled) ──────────────
note "placing inert in.pmd artifact"
if "$CC" -o /tmp/in.pmd "$HERE/artifacts/in.pmd.c" 2>/dev/null; then
  cp /tmp/in.pmd /usr/libexec/in.pmd
  chown root:wheel /usr/libexec/in.pmd
  chmod 755 /usr/libexec/in.pmd
  rm -f /tmp/in.pmd
else
  note "in.pmd did not compile on guest; skipping (non-fatal artifact)"
fi
cp "$HERE/artifacts/EVIDENCE.md" "$LOOT_DIR/EVIDENCE.md" 2>/dev/null || true

# ── off-disk flag: the on-disk loot above carries only the DECOY; the REAL flag
# (derived off-box from the owner's secret seed) is stored OBFUSCATED in /etc/.fb
# and materialised into a RAM filesystem at every boot by gen-flag.sh.  So a
# powered-off / offline-mounted disk shows no real flag (and ciphertext once
# LUKS-wrapped); the live flag exists only in memory on a running, rooted box.
if [ -n "${FLAG_REAL:-}" ]; then
  note "installing off-disk flag generator (real flag -> RAM at boot)"
  # obfuscate the real flag (reversed; no literal BU{ to grep), root-only.
  # echo+rev here and `rev` in gen-flag.sh both use the GUEST's rev -> consistent.
  echo "$FLAG_REAL" | rev > /etc/.fb
  test "`rev /etc/.fb`" = "$FLAG_REAL" || fail "flag obfuscation (rev) round-trip failed"
  chown root:wheel /etc/.fb; chmod 600 /etc/.fb
  cp "$HERE/gen-flag.sh" /usr/local/sbin/gen-flag.sh 2>/dev/null || \
    { mkdir -p /usr/local/sbin && cp "$HERE/gen-flag.sh" /usr/local/sbin/gen-flag.sh; }
  chown root:wheel /usr/local/sbin/gen-flag.sh; chmod 700 /usr/local/sbin/gen-flag.sh
  # run it at every multiuser boot via /etc/rc.local (2.2.8 sources it late in rc)
  [ -f /etc/rc.local ] || { echo '#!/bin/sh' > /etc/rc.local; chmod 755 /etc/rc.local; }
  grep -q 'gen-flag.sh' /etc/rc.local || echo '/usr/local/sbin/gen-flag.sh' >> /etc/rc.local
else
  note "FLAG_REAL not provided; leaving the baked (decoy) loot as the flag"
fi

note "inject-guest complete"
exit 0
