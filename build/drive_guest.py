#!/usr/bin/env python3
"""Drive the *installed* guest over serial to run a payload script as root.

Channel (see docs/field-manual.md "Why injection runs inside the guest"): this
dev host cannot mount the guest's UFS, so we hand the guest a tar archive as a
raw second disk (-hdb).  The whole-disk raw device IS the tar stream, so the
guest unpacks it with `tar xpf /dev/rwd1` — no filesystem, no loopback, no SSH.
We log in on the serial console with the root password set at install time, drop
to /bin/sh for a predictable prompt, unpack the tar, run RUN.sh, and wait for a
success sentinel before halting.

Env in:
  BOX_IMAGE_ABS   installed qcow2 to boot
  BOX_PAYLOAD_TAR raw tar to attach as the second disk
  BOX_SERIAL_LOG  where to tee the console
  BOX_ROOT_PASS   root password (set during install)
  QEMU_BIN, BOX_MACHINE, BOX_CPU, BOX_MEM_MB
"""
import os
import subprocess
import sys
import time

import pexpect

QEMU      = os.environ.get("QEMU_BIN", "qemu-system-i386")
IMAGE     = os.environ["BOX_IMAGE_ABS"]
PTAR      = os.environ["BOX_PAYLOAD_TAR"]
SERLOG    = os.environ.get("BOX_SERIAL_LOG", "guest-serial.log")
ROOT_PASS = os.environ.get("BOX_ROOT_PASS", "toor1995")
MACHINE   = os.environ.get("BOX_MACHINE", "pc")
CPU       = os.environ.get("BOX_CPU", "pentium")
MEM       = os.environ.get("BOX_MEM_MB", "128")

CR = "\r"
PROMPT = r"GX>\s"   # our private /bin/sh prompt — unambiguous vs csh's default

def log(m): print(f"[guest] {m}", file=sys.stderr, flush=True)

def qemu_cmd():
    # graphics=off routes SeaBIOS + the installed disk's boot blocks to COM1 (see
    # drive_install.py); the install also enabled a serial getty so login: lands
    # on this line.  The payload tar rides as a raw second IDE disk (guest wd1).
    return [
        QEMU, "-machine", f"{MACHINE},graphics=off", "-cpu", CPU, "-m", MEM,
        # writethrough: the guest's sync only reaches the *emulated* disk; QEMU's
        # default writeback cache keeps writes in host RAM, and we SIGKILL qemu —
        # so late writes (pwd_mkdb's spwd.db!) were lost, corrupting the on-disk
        # password DB.  writethrough makes every write durable to the qcow2.
        "-drive", f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk,cache=writethrough",
        "-drive", f"file={PTAR},format=raw,if=ide,index=1,media=disk",
        "-display", "none", "-serial", "stdio", "-monitor", "none",
        "-no-reboot",
        "-netdev", "user,id=n0,restrict=on", "-device", "ne2k_pci,netdev=n0",
    ]


# proot translates PIDs, so child.pid misses the real qemu and leaks it (holding
# the qcow2 lock).  pkill by name fails (comm truncated); reap by full cmdline.
REAP_KEY = os.path.basename(IMAGE)

def reap_qemu():
    subprocess.run(["pkill", "-9", "-f", REAP_KEY], check=False)

def kill(child):
    reap_qemu()        # reap first (pexpect close targets the wrong proot pid)
    try: child.logfile_read.close()
    except Exception: pass
    try: child.close(force=True)
    except Exception: pass
    reap_qemu()

def sh(child, cmd, timeout=120):
    """Send one /bin/sh command and wait for our prompt to return."""
    log(f"  $ {cmd}  (<= {timeout}s)")
    child.sendline(cmd)
    child.expect(PROMPT, timeout=timeout)

def main():
    reap_qemu()        # clear any leaked qemu before we start
    time.sleep(1)
    cmd = qemu_cmd()
    log("launching: " + " ".join(cmd))
    child = pexpect.spawn(cmd[0], cmd[1:], timeout=2400, encoding="latin-1",
                          dimensions=(50, 132))
    child.logfile_read = open(SERLOG, "w", encoding="latin-1")
    try:
        # 1. Boot to SINGLE-USER over serial — no multiuser login, so no root
        #    password / getty timing races (the player never logs in as root
        #    anyway; the solve reaches root via .rhosts -> newgrp).  boot.config
        #    already selects the serial console; we override at boot: to add -s.
        log("booting guest single-user (boot: 0:wd(0,a)kernel -s)")
        child.expect(r"boot:", timeout=300)
        time.sleep(1.0)
        # /boot.config already passes -h (serial console); -h is a TOGGLE, so do
        # NOT repeat it here or the console flips back to VGA.  Send -s (single
        # user) only.  CHAR-BY-CHAR: boot2 intermittently drops the first char of
        # a burst, which mangles the boot string into a reboot loop.
        for ch in "0:wd(0,a)kernel -s":
            child.send(ch); time.sleep(0.06)
        child.send(CR)
        child.expect(r"(pathname of shell|RETURN for /bin/sh|# )", timeout=600)
        child.send(CR)
        child.expect(r"# ", timeout=120)
        # NO terminal echo first (so command text isn't mistaken for output), THEN
        # set the private prompt in a SEPARATE command — critical: the prompt
        # string must not appear in any *echoed* command, or expect() matches the
        # echo and the next step races against a leftover real prompt.
        child.sendline("stty -echo 2>/dev/null")
        child.expect(r"# ", timeout=30)
        child.sendline("PS1='GX> '; export PS1")
        child.expect(PROMPT, timeout=60)
        log("single-user root shell ready")

        # 2. The disk may be dirty (a prior run was killed); clean + mount R/W so
        #    /usr (cc, pwd_mkdb) and the rest are available to the payload.  fsck of
        #    the ~1GB /usr under TCG is slow — allow plenty of time.  Once a run
        #    halts cleanly the disk stays clean and this is fast.
        sh(child, "/sbin/fsck -y", timeout=2400)
        sh(child, "/sbin/mount -u -o rw /", timeout=120)
        sh(child, "/sbin/mount -a", timeout=180)
        log("filesystems clean + mounted R/W")

        # 3. Materialise the second disk's device node, then unpack the tar that
        #    *is* that disk.  Try the raw whole-disk node first, then fallbacks.
        sh(child, "cd /dev && (test -c rwd1 || sh MAKEDEV wd1) ; cd /", timeout=120)
        sh(child, "rm -rf /tmp/payload && mkdir -p /tmp/payload", timeout=60)
        child.sendline(
            "for d in /dev/rwd1 /dev/rwd1c /dev/wd1 /dev/wd1c; do "
            "if tar xpf $d -C /tmp/payload 2>/dev/null; then echo UNPACK_OK $d; break; fi; done")
        child.expect(r"UNPACK_OK\s+\S+", timeout=300)
        log("payload tar unpacked: " + child.after.strip())
        child.expect(PROMPT, timeout=60)

        # 4. Run the payload and gate on a UNIQUE marker carrying its exit code
        #    (echo is off, so only real output reaches us — no command-text races).
        log("running /tmp/payload/RUN.sh")
        child.sendline("sh /tmp/payload/RUN.sh; echo XDONE_$?_X")
        j = child.expect([r"XDONE_0_X", r"XDONE_[1-9][0-9]*_X"], timeout=1200)
        child.expect(PROMPT, timeout=120)
        if j == 1:
            log("RUN.sh reported FAILURE — see " + SERLOG)
            return 2
        log("RUN.sh OK")
        return 0
    except (pexpect.TIMEOUT, pexpect.EOF) as e:
        log(f"{type(e).__name__}: aborted — inspect {SERLOG}")
        return 1
    finally:
        # ALWAYS shut down cleanly, marking the filesystems clean — single-user
        # `halt` only SYNCS, it does not unmount, so without this every later boot
        # re-fscks the ~1GB /usr (minutes under TCG).  Unmount what we can and
        # remount root read-only so the clean flag is set; then halt.
        try:
            child.sendline("cd / ; sync; sync")
            child.expect(PROMPT, timeout=30)
            child.sendline("/sbin/umount -a 2>/dev/null; /sbin/mount -u -o ro / 2>/dev/null; sync")
            child.expect(PROMPT, timeout=90)
            child.sendline("/sbin/halt")
            child.expect(r"(halted|press any key|rebooting)", timeout=120)
        except Exception:
            log("clean shutdown did not complete; terminating qemu")
        kill(child)

if __name__ == "__main__":
    sys.exit(main())
