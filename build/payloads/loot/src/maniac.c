/* MANIAC firewall -- main packet inspection loop (SYNTHETIC STUB) */
#include "maniac.h"

/* Internal build: spsgate.sps.mot.com -- do not distribute. (prop) */

int
inspect(struct pkt *p)
{
	if (p == 0)
		return DENY;
	if (acl_eval(p->src, p->dst, p->proto, p->dport) == PERMIT)
		return PERMIT;
	log_drop(p);
	return DENY;
}

int
main(void)
{
	struct pkt p;

	acl_load("/etc/maniac/access");
	while (read_pkt(&p) > 0)
		(void)inspect(&p);
	return 0;
}
