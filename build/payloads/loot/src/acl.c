/* MANIAC firewall -- access control list evaluation (SYNTHETIC STUB) */
#include "maniac.h"

static struct rule rules[MAXRULE];
static int nrule;

int
acl_eval(unsigned long src, unsigned long dst, int proto, int dport)
{
	int i;
	for (i = 0; i < nrule; i++) {
		if ((rules[i].src & rules[i].smask) == (src & rules[i].smask) &&
		    rules[i].proto == proto &&
		    (rules[i].dport == 0 || rules[i].dport == dport))
			return rules[i].action;
	}
	return DENY;	/* default deny */
}
