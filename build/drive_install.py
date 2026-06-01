#!/usr/bin/env python3
"""Drive a scripted FreeBSD 2.2.8 serial-console install under QEMU with pexpect.

This is the deliberately-observable installer driver.  Every byte of the serial
console is teed to BOX_SERIAL_LOG, and every scripted step logs what it matched
and what it sent, because the install is SLOW (TCG emulation) and fragile (we are
steering an ncurses installer through a VT100 serial line).  Iterate by watching
the log and editing the STEPS table — the engine itself rarely needs to change.

Modes:
  (default)        run the full scripted install
  PROBE=<seconds>  just boot and tee the console for N seconds, then quit.
                   Use this first against a new QEMU/boot-floppy combo to SEE
                   what the console actually prints before scripting against it.
"""
import os
import subprocess
import sys
import time

import pexpect

# ── config from the environment (exported by 30-install.sh) ────────────────────
QEMU      = os.environ.get("QEMU_BIN", "qemu-system-i386")
IMAGE     = os.environ["BOX_IMAGE_ABS"]
FLOPPY    = os.environ["BOX_FLOPPY_ABS"]
ISO       = os.environ["BOX_ISO_ABS"]
SERLOG    = os.environ.get("BOX_SERIAL_LOG", "install-serial.log")
MACHINE   = os.environ.get("BOX_MACHINE", "pc")
CPU       = os.environ.get("BOX_CPU", "pentium")
MEM       = os.environ.get("BOX_MEM_MB", "128")
ROOT_PASS = os.environ.get("BOX_ROOT_PASS", "toor1995")
PROBE     = os.environ.get("PROBE")

# ── VT100 / console key constants ──────────────────────────────────────────────
CR    = "\r"
ESC   = "\x1b"
UP    = "\x1b[A"
DOWN  = "\x1b[B"
RIGHT = "\x1b[C"
LEFT  = "\x1b[D"
SPACE = " "
TAB   = "\t"

def log(msg):
    print(f"[drive] {msg}", file=sys.stderr, flush=True)

# This proot translates PIDs, so pexpect's child.pid does NOT match the real OS
# pid — os.kill(child.pid) (and pexpect's own close(force=True)) miss and LEAK the
# qemu, which then holds the qcow2/floppy lock and corrupts the next run.  pkill
# by NAME also fails (comm truncated to 15 chars).  Reap by full cmdline instead,
# keyed on our unique image filename.
REAP_KEY = os.path.basename(IMAGE)

def reap_qemu():
    subprocess.run(["pkill", "-9", "-f", REAP_KEY], check=False)

def qemu_cmd():
    # The 2.2.8 boot blocks do their console I/O through BIOS int10h/int16h, not
    # COM1 — so by default nothing reaches a serial line and there is no way to
    # type at the `Boot:` prompt headlessly.  `-machine pc,graphics=off` tells
    # SeaBIOS to mirror its console (and keyboard input) to COM1 (the modern
    # replacement for the removed sgabios), which carries boot0/boot2 and the
    # `Boot:` prompt onto serial.  We then type `-h` so the *kernel* + sysinstall
    # also use the serial console.  stdio is purely COM1 so pexpect owns it.
    return [
        QEMU,
        "-machine", f"{MACHINE},graphics=off", "-cpu", CPU, "-m", MEM,
        "-drive", f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk"
                  + (f",cache={os.environ['INSTALL_CACHE']}" if os.environ.get("INSTALL_CACHE") else ""),
        "-drive", f"file={FLOPPY},format=raw,if=floppy,unit=0,readonly=on",
        # Install CD as a SCSI CDROM on a Symbios 53c810 (2.2.8 'ncr' driver) —
        # the emulated ATAPI/wcd path reported "no disc inside" and sysinstall's
        # mount failed; old FreeBSD handles SCSI CD far more reliably than ATAPI.
        "-device", "lsi53c810,id=scsi0",
        "-drive", f"id=cd0,file={ISO},format=raw,if=none,media=cdrom,readonly=on",
        "-device", "scsi-cd,bus=scsi0.0,drive=cd0",
        "-boot", "a",
        "-display", "none",
        "-serial", "stdio",
        "-monitor", "none",
        "-no-reboot",
        # host-only during install too: never let a build touch the internet.
        "-netdev", "user,id=n0,restrict=on", "-device", "ne2k_pci,netdev=n0",
    ]

def spawn():
    reap_qemu()        # clear any leaked qemu from a prior run before we start
    time.sleep(1)
    cmd = qemu_cmd()
    log("launching: " + " ".join(cmd))
    child = pexpect.spawn(cmd[0], cmd[1:], timeout=900, encoding="latin-1",
                          dimensions=(50, 132))
    # Tee everything we read to the serial log for offline inspection.
    child.logfile_read = open(SERLOG, "w", encoding="latin-1")
    return child

# ── the scripted install ───────────────────────────────────────────────────────
# Step = (description, expect_regex, send_string, timeout_s, optional).
#   expect_regex "<DRAIN>"  -> just read/tee for `timeout` seconds (no match).
#   expect_regex "<SEND>"   -> send immediately without waiting for anything.
#   send=None               -> wait for the marker, send nothing.
#   optional=True           -> on TIMEOUT, log and continue instead of aborting
#                              (lets one slow boot walk as far as it can while we
#                              still tune later dialogs against the serial log).
# Patterns match the raw VT100 stream, so anchor on stable dialog text. sysinstall
# libdialog menus accept the first character of an item's name to select it; we
# use that (deterministic regardless of on-screen position) + CR to invoke.
DOWN_CR = DOWN + CR
STEPS = [
    # boot blocks: request serial console so kernel + sysinstall talk to COM1.
    ("boot prompt", r"boot:", "-h" + CR, 180, False),
    # 2.2.8 BOOTMFS UserConfig CLI: `quit` saves and continues booting.
    ("userconfig", r"(Kernel Configuration Utility|config>)", "quit" + CR, 300, False),
    # sysinstall (init) asks terminal type; 2 = VT100.
    ("term type", r"Your choice: \(1-4\)", "2" + CR, 600, False),

    # main menu -> Express.  IMPORTANT: select by NUMERIC TAG, not by name's first
    # letter — the menu's button hotkeys are S(elect) and E(xit Install), so 'e'
    # would trigger "Exit Install" and reboot.  Tag 6 == Express; CR invokes it.
    ("main menu", r"sysinstall Main Menu", "6" + CR, 120, False),

    # Express runs the FDISK editor on the sole disk (wd0).
    ("fdisk intro", r"(set up.*DOS|partition.*scheme|geometry|Press F1)", CR, 90, True),
    ("fdisk editor", r"FDISK Partition Editor", "A", 120, False),   # A = use entire disk
    # 'A' pops "true partition entry ... cooperative with future OSes?" -> Yes (default).
    ("fdisk true-part", r"(true partition entry|cooperative|dangerously dedicated)", CR, 60, True),
    ("fdisk finish", r"FDISK Partition Editor", "Q", 30, True),     # Q = finish (re-match editor)

    # Boot manager: a RADIOLIST (*) BootMgr / ( ) Standard / ( ) None.  We need a
    # plain, non-interactive MBR for a headless serial box, so select "Standard".
    # CRITICAL: SPACE moves the radio selection; just DOWN+CR leaves the radio on
    # the default BootMgr (= "Booteasy", an interactive selector that hangs a
    # serial boot).  So: DOWN to highlight Standard, SPACE to select it, CR = OK.
    # NOTE: arrow keys do NOT work here — libdialog switches the VT100 to
    # application cursor-key mode (Down = ESC O B, not ESC [ B), so our arrows
    # were silently dropped and the radio stayed on the default BootMgr.  Instead
    # use the item's first-letter hotkey: 's' jumps to "Standard", SPACE selects
    # the radio, CR activates [OK].  (Letters are read directly, no mode issue.)
    ("bootmgr", r"Install Boot Manager for drive", None, 120, False),
    ("bootmgr settle", "<DRAIN>", None, 3),
    ("bootmgr pick", "<SEND>", "sS", 3, False),     # 's'/'S' hotkey -> Standard
    ("bootmgr d2", "<DRAIN>", None, 2),
    ("bootmgr select", "<SEND>", " ", 3, False),    # select the radio
    ("bootmgr s2", "<DRAIN>", None, 3),
    ("bootmgr ok", "<SEND>", CR, 3, False),

    # Disklabel editor: 'A' = auto BSD partitions, 'Q' = finish.  'A' may also pop
    # confirmations; answer any with Yes (CR) via the optional step below.
    ("disklabel", r"(Disklabel Editor|FreeBSD Disklabel)", "A", 150, True),
    ("disklabel confirm", r"(User Confirmation|partition|swap|Yes)", CR, 30, True),
    ("disklabel finish", r"(Disklabel Editor|FreeBSD Disklabel)", "Q", 30, True),

    # Distribution selection is a CHECKLIST (SPACE toggles [ ]->[X], ENTER = OK).
    # Tag 6 = "Minimal" (= the base 'bin' set, all our CD carries).  The menu needs
    # a beat to become interactive, so settle BEFORE sending keys (sending too
    # early dropped the keystrokes and left nothing selected).  Move to Minimal
    # (6), let the highlight settle, toggle it (SPACE), then confirm we see [X].
    ("dists", r"Choose Distributions", None, 150, False),
    ("dists settle", "<DRAIN>", None, 3),
    ("dists pick", "<SEND>", "6", 3, False),
    ("dists settle2", "<DRAIN>", None, 2),
    ("dists toggle", "<SEND>", " ", 3, False),
    ("dists confirm", r"\[X\]", None, 30, False),   # a box got checked (Minimal)
    ("dists ok", "<SEND>", CR, 3, False),
    # Minimal may pop "install the ports collection?" -> No.
    ("ports? no", r"(ports collection|Would you like to install)", "n", 30, True),

    # Choose Installation Media -> CDROM (tag 1, then CR).  NOTE: do NOT drain
    # after this — a drain would consume the "Last Chance" dialog text before the
    # next step can match it (that exact bug stalled an earlier run).
    ("media", r"Choose Installation Media", "1" + CR, 150, False),

    # "Last Chance!" yesno — [ Yes ] is the default/highlighted button, so a bare
    # CR selects Yes and the commit (newfs + extract) begins.
    ("last chance", r"Last Chance", CR, 180, False),

    # Commit writes the MBR + partition table FIRST (before the slow newfs/extract).
    # Used as a fast STOP_AFTER checkpoint to inspect the on-disk MBR.
    ("mbr written", r"(Writing partition information|partition information to drive)", None, 200, True),
    ("mbr flush", "<DRAIN>", None, 15),   # let the MBR write persist (use INSTALL_CACHE=writethrough)

    # Commit: writes MBR + bootblocks, newfs's the partitions, then extracts the
    # bin set from the SCSI CD.  Wait for extraction to actually FINISH, signalled
    # by the first post-install configuration question (Express asks about the
    # network first).  TCG extraction of the bin set is slow — allow ~25 min.
    ("installing", r"(nstalling|Extracting|Chunking|Verifying)", None, 300, True),
    ("extract done", r"(Congratulations|configure.*(network|Ethernet)|"
                     r"Would you like to configure|network devices|Gateway|"
                     r"general configuration|registration|installed)", None, 1500, False),
]

STOP_AFTER = os.environ.get("STOP_AFTER")   # for fast isolated dialog testing

def run_steps(child):
    for desc, pat, send, tmo, *rest in STEPS:
        optional = rest[0] if rest else False
        if pat == "<DRAIN>":
            log(f"step: {desc!r}  (drain {tmo}s)")
            deadline = time.time() + tmo
            while time.time() < deadline:
                try: child.expect(r".+", timeout=2)
                except pexpect.TIMEOUT: pass
                except pexpect.EOF: break
            if STOP_AFTER and desc == STOP_AFTER: return
            continue
        if pat == "<SEND>":
            log(f"step: {desc!r}  -> send {send!r} (no wait)")
            child.send(send)
            time.sleep(1.0)
            if STOP_AFTER and desc == STOP_AFTER: return
            continue
        log(f"step: {desc!r}  (await /{pat}/{'  [optional]' if optional else ''})")
        try:
            child.expect(pat, timeout=tmo)
        except pexpect.TIMEOUT:
            if optional:
                log(f"  (optional) no match for {desc!r}; continuing")
                continue
            log(f"TIMEOUT waiting for {desc!r}; see {SERLOG}")
            raise
        except pexpect.EOF:
            log(f"EOF (qemu exited) waiting for {desc!r}; see {SERLOG}")
            raise
        if send is not None:
            log(f"  -> send {send!r}")
            child.send(send)
        time.sleep(0.8)
        if STOP_AFTER and desc == STOP_AFTER:
            log(f"STOP_AFTER {desc!r} — halting step run for inspection")
            return

def spawn_hd():
    """Boot the freshly-installed disk (wd0) only — no floppy, no CD."""
    reap_qemu(); time.sleep(1)
    cmd = [
        QEMU, "-machine", f"{MACHINE},graphics=off", "-cpu", CPU, "-m", MEM,
        "-drive", f"file={IMAGE},format=qcow2,if=ide,index=0,media=disk",
        "-boot", "c", "-display", "none", "-serial", "stdio", "-monitor", "none",
        "-no-reboot",
        "-netdev", "user,id=n0,restrict=on", "-device", "ne2k_pci,netdev=n0",
    ]
    log("finalize: launching " + " ".join(cmd))
    child = pexpect.spawn(cmd[0], cmd[1:], timeout=900, encoding="latin-1",
                          dimensions=(50, 132))
    child.logfile_read = open(SERLOG.replace(".log", "-finalize.log"), "w",
                              encoding="latin-1")
    return child

def finalize_phase():
    """Boot the installed disk to SINGLE USER over serial and make it usable
    headlessly for the later inject/theme stages: set the root password, enable a
    secure serial getty, and write /boot.config '-h' so every later boot comes up
    on the serial console automatically.  Line-oriented and deterministic."""
    child = spawn_hd()
    try:
        # boot2 waits at `boot:`.  Use the full boot spec + combined flags (the
        # proven form): single-user (-s) on the serial console (-h).  Bare "-sh"
        # loads the kernel but does not bring it up on serial.
        child.expect(r"boot:", timeout=180)
        time.sleep(0.5)
        child.send("0:wd(0,a)kernel -sh" + CR)
        # single-user drops to "Enter pathname of shell or RETURN for /bin/sh:".
        child.expect(r"(pathname of shell|RETURN for /bin/sh|# )", timeout=600)
        child.send(CR)
        child.expect(r"# ", timeout=120)
        log("finalize: single-user shell up")

        def sh(cmd, tmo=120):
            child.sendline(cmd); child.expect(r"# ", timeout=tmo)

        # The install was SIGKILLed (not cleanly unmounted), so the filesystems are
        # marked dirty and the kernel refuses a R/W remount until fsck.  Clean them,
        # then mount R/W.  fsck of /usr (~1GB) under TCG can take a couple of minutes.
        log("finalize: fsck (filesystems dirty from the killed install)")
        sh("/sbin/fsck -y", tmo=600)
        sh("/sbin/mount -u -o rw /")
        sh("/sbin/mount -a", tmo=180)

        # root password (interactive passwd avoids $-escaping a hash over the wire)
        log("finalize: setting root password")
        child.sendline("/usr/bin/passwd")
        child.expect(r"[Nn]ew password:", timeout=60); child.send(ROOT_PASS + CR)
        child.expect(r"[Rr]etype.*password:", timeout=60); child.send(ROOT_PASS + CR)
        child.expect(r"# ", timeout=60)

        # enable a SECURE getty on the serial line so root can log in over COM1.
        log("finalize: enabling serial getty (ttyd0 on+secure)")
        sh("cp /etc/ttys /etc/ttys.orig")
        sh("sed -e '/^ttyd0/s|.*|ttyd0\t\"/usr/libexec/getty std.9600\"\tvt100\ton secure|' "
           "/etc/ttys.orig > /etc/ttys")
        sh("grep ttyd0 /etc/ttys")

        # every future boot: serial console automatically (no -h needed at boot:).
        sh("echo '-h' > /boot.config")
        sh("cat /boot.config")

        log("finalize: halting")
        child.sendline("sync; sync; halt")
        child.expect(r"(halted|press any key|rebooting)", timeout=180)
        log("finalize: complete")
        return 0
    except (pexpect.TIMEOUT, pexpect.EOF) as e:
        log(f"finalize {type(e).__name__}: see {SERLOG.replace('.log','-finalize.log')}")
        return 1
    finally:
        kill(child)

def probe(child, seconds):
    log(f"PROBE mode: teeing console to {SERLOG} for {seconds}s")
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            child.expect(r".+", timeout=2)   # drain output to the tee'd logfile
        except pexpect.TIMEOUT:
            pass
        except pexpect.EOF:
            log("qemu exited during probe")
            break
    log("probe window elapsed")


def kill(child):
    """Reap qemu reliably (see reap_qemu) so we never leak a lock-holding process.
    Reap FIRST — pexpect's own close(force=True) targets the wrong (untranslated)
    pid and can block, so do the cmdline-based kill before touching the child."""
    reap_qemu()
    try: child.logfile_read.close()
    except Exception: pass
    try: child.close(force=True)
    except Exception: pass
    reap_qemu()

PHASE = os.environ.get("PHASE", "both")   # install | finalize | both

def install_main():
    child = spawn()
    try:
        if PROBE:
            probe(child, int(PROBE))
            return 0
        run_steps(child)
        log("install steps exhausted — see serial log to confirm extraction")
        return 0
    finally:
        kill(child)

def main():
    if PROBE:
        return install_main()
    rc = 0
    if PHASE in ("install", "both"):
        rc = install_main()
        if rc != 0:
            return rc
    if PHASE in ("finalize", "both"):
        rc = finalize_phase()
    return rc

if __name__ == "__main__":
    sys.exit(main())
