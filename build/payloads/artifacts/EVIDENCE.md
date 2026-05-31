# Inert backdoor artifacts — for analysis, NOT live services

The Feb 1995 lore features network backdoors: a trojan `telnetd` (`sportd` ->
`in.pmd`) listening on **port 5553** with trigger word `wank`, and **port-3111**
backdoor shells (cf. ~/takedown TIMELINE 4007, 4014, 4023, 4024).

For SAFETY (see PROVENANCE.md §6) this box reproduces them **only as discoverable
on-disk artifacts to find and analyze** — they are NOT wired into inetd/rc and do
**not** listen. A player who finds them has found forensic evidence, not an open
port.

Planted by the inject hook:
- `/var/tmp/.../in.pmd`        an INERT stub binary (prints a notice and exits;
                              it does not bind any socket). `strings` it like
                              the sessions did (`strings sportd` in 4023).
- `/var/tmp/.../README.pmd`    this notice, in place, explaining the artifact.
- a commented-out, disabled line in `/etc/inetd.conf` referencing 5553/3111 so
  the player can SEE the intended wiring without it ever being active.

None of these affect the intended solve path. They are lore/forensics flavor and
a teaching point about how period persistence looked.
