/* MANIAC firewall -- shared declarations (SYNTHETIC STUB) */
#ifndef _MANIAC_H_
#define _MANIAC_H_

#define PERMIT 1
#define DENY   0
#define MAXRULE 256

struct pkt { unsigned long src, dst; int proto, dport; };
struct rule { unsigned long src, smask; int proto, dport, action; };

int  inspect(struct pkt *);
int  acl_eval(unsigned long, unsigned long, int, int);
int  acl_load(const char *);
int  read_pkt(struct pkt *);
void log_drop(struct pkt *);

#endif /* _MANIAC_H_ */
