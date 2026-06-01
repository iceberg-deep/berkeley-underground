#!/usr/bin/env python3
"""FEASIBILITY PROBE for Box 3: can BPF/tcpdump capture cleartext LOCALHOST traffic
on FreeBSD 2.2.8 under QEMU host-only net?  Boots the Box 1 base, roots via the
newgrp trojan, then runs tcpdump on lo0 and ed1 while doing an FTP login to
localhost and to the box's own ed1 IP — and reports which interface saw the
cleartext password.  If neither does, the live-sniffer mechanic is infeasible and
Box 3 must use the found-log path instead.  Throwaway diagnostic; reaps the box."""
import os, socket, subprocess, sys, time
import pexpect

QEMU="qemu-system-i386"
IMAGE=os.environ["BOX_IMAGE_ABS"]
MACHINE="pc"; CPU="pentium"; MEM="128"
TPORT="2323"; FPORT="2121"; SPORT="5514"
SERLOG="work/bpftest-serial.log"
def log(m): print(f"[bpftest] {m}", file=sys.stderr, flush=True)
def reap(): subprocess.run(["pkill","-9","-f",os.path.basename(IMAGE)],check=False)

def boot():
    reap(); time.sleep(1)
    fwd=f"hostfwd=tcp:127.0.0.1:{TPORT}-:23,hostfwd=tcp:127.0.0.1:{FPORT}-:21,hostfwd=tcp:127.0.0.1:{SPORT}-:513"
    cmd=[QEMU,"-machine",f"{MACHINE},graphics=off","-cpu",CPU,"-m",MEM,
         "-drive",f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk",
         "-boot","c","-display","none","-serial",f"file:{SERLOG}","-monitor","none","-no-reboot",
         "-netdev",f"user,id=n0,restrict=on,{fwd}","-device","ne2k_pci,netdev=n0"]
    log("booting base box"); return subprocess.Popen(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def main():
    box=boot()
    try:
        dl=time.time()+600
        while time.time()<dl:
            try: socket.create_connection(("127.0.0.1",int(TPORT)),timeout=3).close(); break
            except OSError: time.sleep(5)
        tn=None
        for _ in range(16):
            time.sleep(10)
            tn=pexpect.spawn(f"telnet 127.0.0.1 {TPORT}",encoding="latin-1",timeout=60)
            tn.logfile_read=open(SERLOG.replace(".log","-telnet.log"),"w",encoding="latin-1")
            try: tn.expect(r"login:",timeout=30); break
            except (pexpect.TIMEOUT,pexpect.EOF): tn=None
        if not tn: log("no login prompt"); return 1
        tn.sendline("brian"); tn.expect(r"[Pp]assword:",timeout=30); tn.sendline("newriver")
        tn.expect([r"\$ ",r"% "],timeout=60)
        tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ",r"% "],timeout=30)
        # root via the Box 1 newgrp trojan (one-shot into a marker)
        tn.sendline("newgrp -hack root"); time.sleep(1)
        tn.sendline("id; echo RC_X"); tn.expect(r"RC_X",timeout=20)
        if "uid=0" not in tn.before: log("no root via newgrp: %r"%tn.before[-120:]); return 2
        log("root OK")
        def root(cmd,tmo=120):
            tn.sendline(cmd+"; echo X_$?_X"); tn.expect(r"X_\d+_X",timeout=tmo); return tn.before
        root("PATH=/bin:/usr/bin:/sbin:/usr/sbin; export PATH")
        log("tcpdump present: %r"% " ".join(root("ls -l /usr/sbin/tcpdump /sbin/tcpdump /usr/bin/tcpdump 2>&1").split())[-100:])
        log("bpf nodes: %r"% " ".join(root("ls -l /dev/bpf* 2>&1").split())[-120:])
        log("ifconfig: %r"% " ".join(root("ifconfig -a 2>&1 | grep -E 'flags|inet' ").split())[-160:])
        # --- capture test on each interface ---
        for iface, target in [("lo0","localhost"), ("ed1","10.0.2.15")]:
            root(f"rm -f /tmp/cap_{iface} /tmp/tderr_{iface} /tmp/ftp_{iface}")
            # background tcpdump (valid snaplen) -> pcap file; then an ftp login; read via strings
            root(f"tcpdump -i {iface} -s 1514 -w /tmp/cap_{iface} port 21 >/tmp/tderr_{iface} 2>&1 & echo $! > /tmp/td_{iface}; sleep 3", tmo=60)
            root(f"( echo open {target}; sleep 1; echo user brian newriver; sleep 1; echo quit ) | ftp -nv >/tmp/ftp_{iface} 2>&1; sleep 2", tmo=60)
            root(f"kill `cat /tmp/td_{iface}` 2>/dev/null; sleep 1")
            ftp = root(f"echo FTP:; tail -2 /tmp/ftp_{iface} 2>&1")
            diag = root(f"echo TDERR:; head -1 /tmp/tderr_{iface} 2>&1; echo BYTES:; wc -c < /tmp/cap_{iface} 2>/dev/null; echo HIT:; strings /tmp/cap_{iface} 2>/dev/null | grep -c newriver")
            ls = lambda o:[l.strip() for l in o.splitlines() if l.strip() and "X_" not in l]
            log(f"=== {iface} ({target}) :: {ls(ftp)} | {ls(diag)}")
        log("=== PROBE DONE — look for 'newriver' count > 0 on some interface ===")
        return 0
    except (pexpect.TIMEOUT,pexpect.EOF) as e:
        log("%s — see %s"%(type(e).__name__,SERLOG)); return 1
    finally:
        reap()
        if box.poll() is None: box.terminate()

if __name__=="__main__": sys.exit(main())
