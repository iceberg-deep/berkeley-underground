#!/bin/sh
# Runs as root INSIDE the guest.  Applies the DISCLOSED cosmetic "SunOS costume"
# on top of the real FreeBSD system: login banner, message of the day, hostname,
# and the /vmunix -> /kernel symlink (SunOS names its kernel /vmunix; FreeBSD
# uses /kernel).  None of this changes the kernel or userland — see README and
# docs/historicity.md "banners lie".  POSIX/ash only.
set -u
HERE=$(dirname "$0")
. "$HERE/box-guest.env"

note() { echo ">> $*"; }

note "installing SunOS banners"
cp "$HERE/theme/motd"  /etc/motd
cp "$HERE/theme/issue" /etc/issue
chmod 644 /etc/motd /etc/issue

note "linking /vmunix -> /kernel (SunOS kernel name)"
ln -sf /kernel /vmunix

note "setting hostname $HOSTNAME_FQDN"
grep -q '^hostname=' /etc/rc.conf 2>/dev/null || \
  echo "hostname=\"$HOSTNAME_FQDN\"" >> /etc/rc.conf
hostname "$HOSTNAME_FQDN" 2>/dev/null || true

note "theme-guest complete"
exit 0
