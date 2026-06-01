#!/usr/bin/env python3
"""Live diagnostic for Box 2: connect to the ALREADY-RUNNING box, get root via the
trojan login, and dump the watcher state (cron entry, did it run, run it manually
with -x trace, is the trophy/MFS materialised).  Does not boot or reap anything."""
import os, sys, time, pexpect

TPORT = os.environ.get("BOX_FWD_TELNET", "2323")
FUSER = os.environ.get("BOX_FOOTHOLD_USER", "brian")
FPASS = os.environ.get("BOX_FOOTHOLD_PASS", "newriver")
MAGIC = os.environ.get("BOX_LOGIN_MAGIC", "wank")
def log(m): print(f"[diag2] {m}", file=sys.stderr, flush=True)

tn = pexpect.spawn(f"telnet 127.0.0.1 {TPORT}", encoding="latin-1", timeout=60)
tn.logfile_read = open("work/diag2-telnet.log", "w", encoding="latin-1")
tn.expect(r"login:", timeout=60)
tn.sendline(FUSER); tn.expect(r"[Pp]assword:", timeout=30); tn.sendline(FPASS)
tn.expect([r"\$ ", r"% "], timeout=60)
tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ", r"% "], timeout=30)
tn.sendline("/usr/bin/login"); tn.expect(r"login: ", timeout=30)
tn.sendline(MAGIC); time.sleep(1)
tn.sendline("id; echo RC_X"); tn.expect(r"RC_X", timeout=20)
if "uid=0" not in tn.before:
    log("could not get root: %r" % tn.before[-100:]); sys.exit(1)
log("root OK")

def run(cmd, tmo=120):
    tn.sendline(cmd + "; echo E_$?_E")
    tn.expect(r"E_\d+_E", timeout=tmo)
    return tn.before

for label, cmd in [
    ("cron entry",    "grep tripwire /etc/crontab 2>&1"),
    ("cron running",  "ps -ax 2>/dev/null | grep cron | grep -v grep"),
    ("tripwire log",  "cat /root/.tripwire.log 2>&1"),
    ("trophy now",    "cat /var/account/.trophy/trophy.txt 2>&1 | head -4"),
    ("mfs mounted",   "mount 2>&1 | grep -i mfs"),
    ("done marker",   "ls -la /var/account/.released 2>&1"),
    ("MANUAL run -x", "sh -x /usr/local/sbin/tripwire.sh brian gaia 2>&1 | tail -35"),
    ("trophy after",  "cat /var/account/.trophy/trophy.txt 2>&1 | head -4"),
    ("mfs after",     "mount 2>&1 | grep -i mfs"),
]:
    out = run(cmd)
    lines = [l.rstrip() for l in out.splitlines() if l.strip() and "E_" not in l]
    log(f"--- {label} ---")
    for l in lines[-36:]:
        print("    " + l, file=sys.stderr, flush=True)
sys.exit(0)
