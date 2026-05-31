/*
 * in.pmd - INERT reproduction of the "sportd"/"in.pmd" trojan telnetd stub
 *          (TIMELINE 4007/4023: listened on port 5553, trigger word "wank").
 *
 * SAFETY: this reproduction binds NOTHING and listens on NO port. It exists so
 * the artifact can be discovered and `strings`-analyzed exactly as the intruder
 * audited his own tools in 4023. Running it just prints a notice and exits.
 */
#include <stdio.h>
int
main(void)
{
	/* The historical trigger string, present for `strings` to surface: */
	const char *trigger = "wank";
	(void)trigger;
	fprintf(stderr,
	    "in.pmd: inert CTF artifact -- no socket bound, no port opened.\n"
	    "        (reproduction of the port-5553 trojan telnetd; see EVIDENCE.md)\n");
	return 0;
}
