#!/usr/bin/env python3
"""Boot the box single-user and dump network/inetd/account diagnostics, so we can
see WHY a multiuser service (e.g. telnetd) isn't reachable without a slow blind
iteration.  Output (the guest's command output) lands in BOX_SOLVE_SERIAL."""
import os, subprocess, sys, time
import pexpect

QEMU=os.environ.get("QEMU_BIN","qemu-system-i386")
IMAGE=os.environ["BOX_IMAGE_ABS"]
MACHINE=os.environ.get("BOX_MACHINE","pc"); CPU=os.environ.get("BOX_CPU","pentium")
MEM=os.environ.get("BOX_MEM_MB","128")
SER=os.environ.get("BOX_SOLVE_SERIAL","work/diag-serial.log")
CR="\r"; PROMPT=r"GX> "
def log(m): print(f"[diag] {m}",file=sys.stderr,flush=True)
def reap(): subprocess.run(["pkill","-9","-f",os.path.basename(IMAGE)],check=False)

DIAG = r"""
echo ===RCTAIL===; tail -8 /etc/rc.conf
echo ===DBFILES===; ls -l /etc/pwd.db /etc/spwd.db /etc/passwd /etc/master.passwd
echo ===ROOTLINE===; grep '^root' /etc/master.passwd
echo ===WCMP===; wc -l /etc/master.passwd /etc/passwd
echo ===PWDMKDB===; /usr/sbin/pwd_mkdb -p /etc/master.passwd; echo "pwd_mkdb_rc=$?"
echo ===AFTERDB===; ls -l /etc/pwd.db /etc/spwd.db
echo ===IDROOT===; id root 2>&1; id brian 2>&1
echo ===DIAGEND===
"""

def main():
    reap(); time.sleep(1)
    cmd=[QEMU,"-machine",f"{MACHINE},graphics=off","-cpu",CPU,"-m",MEM,
         "-drive",f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk",
         "-boot","c","-display","none","-serial","stdio","-monitor","none","-no-reboot",
         "-netdev","user,id=n0,restrict=on","-device","ne2k_pci,netdev=n0"]
    log("booting single-user for diagnostics")
    c=pexpect.spawn(cmd[0],cmd[1:],encoding="latin-1",timeout=2400,dimensions=(50,132))
    c.logfile_read=open(SER,"w",encoding="latin-1")
    try:
        c.expect(r"boot:",timeout=300); time.sleep(1.0)
        for ch in "0:wd(0,a)kernel -s":   # char-by-char: boot2 drops the 1st char of a burst
            c.send(ch); time.sleep(0.06)
        c.send(CR)
        c.expect(r"(pathname of shell|RETURN for /bin/sh|# )",timeout=600); c.send(CR)
        c.expect(r"# ",timeout=120)
        c.sendline("stty -echo 2>/dev/null"); c.expect(r"# ",timeout=30)
        c.sendline("PS1='GX> '; export PS1"); c.expect(PROMPT,timeout=60)
        log("shell ready; fsck+mount")
        c.sendline("/sbin/fsck -y"); c.expect(PROMPT,timeout=2400)
        c.sendline("/sbin/mount -u -o rw /"); c.expect(PROMPT,timeout=120)
        c.sendline("/sbin/mount -a"); c.expect(PROMPT,timeout=180)
        log("running diagnostics")
        for line in DIAG.strip().splitlines():
            c.sendline(line); c.expect(PROMPT,timeout=60)
        c.sendline("echo ALLDIAGDONE"); c.expect(r"ALLDIAGDONE",timeout=30); c.expect(PROMPT,timeout=30)
        log("diagnostics done")
        return 0
    except (pexpect.TIMEOUT,pexpect.EOF) as e:
        log(f"{type(e).__name__}: see {SER}"); return 1
    finally:
        try: c.sendline("halt"); c.expect(r"(halted|press any key)",timeout=120)
        except Exception: pass
        reap()

if __name__=="__main__": sys.exit(main())
