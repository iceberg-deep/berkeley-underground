# Ghosts in the Wires: A Historical Primer

### Read this before you boot the box

*In memory of Kevin David Mitnick — August 6, 1963 to July 16, 2023.*

---

## How to read this document

This primer exists so you understand what you are about to practice, and where
it came from. It is built on a foundation of **primary evidence**: 27 captured
network sessions from February 1995, reconstructed and hashed in this project's
sibling evidence repository (`TIMELINE.md`). Where this account describes
something the captured sessions actually show, it is on solid ground and you can
check it against the transcript.

But the *full* story — the years before those two weeks, the human manipulation,
the manhunt, the arrest, and the bitter argument about what it all meant — does
**not** live in the evidence. It lives in three books written by people who
despised each other's versions, and in court records, and in Kevin's own later
account. Those sources **disagree**, sometimes furiously. This primer will not
pretend they agree. When it leaves the evidence and enters disputed territory, it
will say so, and it will show you both sides rather than choosing one for you.

That is the honest way to tell this story. It is also, fittingly, the way Kevin
himself would have wanted it told: he spent the second half of his life
correcting the myth.

---

## Part I — The two weeks the evidence can prove

For roughly ten days in February 1995, someone moved through the networks of the
WELL, Netcom, Internex, Colorado SuperNet, Motorola, and the personal machines of
a security researcher and two journalists. We know what that someone did with
unusual precision, because the traffic was being captured.

The technical spine is not in dispute, because it was recorded as it happened.
The intruder logged into the WELL through a stolen account, escalated to root
using a **trojaned `newgrp` program**, and wiped his tracks from the system's
accounting logs. He planted **`.rhosts` trust files** — the infamous `+ +` that
tells a Unix host to trust *anyone, from anywhere, with no password* — in the home
directories of journalists Jon Littman and John Markoff, then used that trust to
walk back in at will and read their private mail. He traded exploits over `talk`
sessions with a collaborator known as **jsz** at Ben-Gurion University in Israel.
He broke into security researcher Dan Farmer's machine and stole **SATAN**. He
broke into Motorola and stole the source code to their **MANIAC firewall product**
— a 1.8-megabyte file that failed to transfer on the first attempt and succeeded
on the second. He swapped the kernel on a Colorado SuperNet server for one
containing a **packet sniffer**, forging the timestamps to hide the change. And in
a thirty-three-second session, he typed a query into the NEXIS news database:
`MITNICK W/30 KEVIN` — searching the news for his own name.

These are not embellishments. They are in the transcript, command by command,
timestamped. If you want to see the trust-model attack you are about to practice
*actually being used*, it is session 4003 and session 4023. The privilege
escalation is session 4007. The kernel swap is 4015. The theft you will mirror in
this box — root, locate the loot, exfiltrate it — is the MANIAC theft in sessions
4014 and 4017.

This is the layer this CTF box teaches. Everything in your path — telnet in, find
the trust file, exploit `.rhosts`, escalate with `newgrp`, take the loot off the
box — is a real technique from these real sessions, distilled onto a single host.

But the captured sessions are only the **technical residue** of the attack. They
are the keystrokes. They are not the reason the keystrokes worked.

---

## Part II — What the evidence cannot show: the human layer

Here we leave the transcript, and you should know it.

Kevin Mitnick's defining skill was never the exploit. It was the phone call. He
was, by broad agreement even among people who agreed on nothing else, one of the
most effective **social engineers** who ever lived — a person who could call a
phone company, sound like a colleague, and talk an employee into handing over the
credentials, the procedures, the trust that the technical attack then merely
*used*. The stolen accounts that gave him his foothold on the WELL did not come
from a buffer overflow. Many came from a human being who believed they were
helping a coworker.

None of that is in the captured sessions, because you cannot packet-capture a
conversation. So when you finish this box having "done what Mitnick did," hold
onto this: you will have done what his *keyboard* did. The part that made him
singular happened in the space between people, and it left no logs.

This matters for a second reason. The popular image of Mitnick — the
super-genius cyber-wizard, the digital Hannibal Lecter the government claimed
could launch nuclear missiles by whistling into a payphone — was a *myth*, and a
damaging one. The reality was a brilliant, obsessive man whose primary weapon was
understanding people, not magic. Kevin spent his entire post-prison life as a
security consultant arguing exactly this: that the human is the vulnerability,
that no firewall stops a trusted voice on the phone. The box you are about to
solve teaches the technical half. The historical lesson — the one worth
remembering him for — is the half the box can't contain.

---

## Part III — The scale the box compresses

The real intrusion was not one host solved in one sitting. It was a sprawl.

Trace the chain the evidence shows: connections laundered through Netcom dial-ups,
into the WELL, out to Internex, pivoting to escape.com, reaching into Motorola and
Dan Farmer's fish.com and Colorado SuperNet — dozens of systems, across days, with
constant log-wiping, timestamp forgery, and obsessive watching of the system
administrators (`w`, `last`, `ps`, over and over) to see if anyone was onto him
yet. Between every theft there was housekeeping: scrubbing accounting files,
backdating trojans, laundering file ownership.

Your box is one host, one clean path, one sitting. That is the correct shape for
learning a technique in isolation — but it is a distillation, not a reenactment.
The full topology, the pivots, the persistence, the days of patient
track-covering: those are stripped here so the core mechanic stands alone. Later
boxes in this series restore them one layer at a time. This is the first rung.

---

## Part IV — The capture, and the part everyone fought about

On February 15, 1995, at 1:30 in the morning, FBI agents arrested Kevin Mitnick in
his apartment in Raleigh, North Carolina. This is the one fact with no dispute: the
Department of Justice announced it that day, describing an "intensive two-week
electronic manhunt." When agents took him, the federal record states he was found
with cloned cellular phone codes, false identification, and cloned phone hardware.

The last captured session in the evidence is from the evening before — a quiet,
read-only check of his stashed files, hours before the agents arrived. He seemed,
the day-page notes, comfortable. He was already surrounded.

**Everything about *how* he was caught, and whether it was right, is contested.**
Here the sources fracture, and a memorial that respects the truth has to show the
fracture rather than smooth it:

- **The Shimomura/Markoff account** (*Takedown*, 1996): the heroic version.
  Tsutomu Shimomura, a security researcher whose own machines Mitnick had attacked
  on Christmas 1994, led the technical pursuit — tracing the connections, working
  with the cellular carrier, and ultimately using **radio direction-finding** in
  Raleigh to locate the exact apartment. The good guy wins; the outlaw goes to
  jail. It became a book (reportedly a ~$750,000 advance, with movie and game
  deals pushing toward $2 million) and then a film.

- **The Littman account** (*The Fugitive Game*, 1996): the dissent. Journalist
  Jonathan Littman, who was in telephone contact with Mitnick through much of the
  chase, alleged that the story had been *manufactured*. He charged journalistic
  impropriety against Markoff — who covered the case for the *New York Times*
  while, Littman said, never interviewing Mitnick — and argued that Markoff's
  coverage hyped a "petty criminal" into a national menace, that the prosecution
  was overzealous, and that Shimomura's role in the pursuit was of "unclear or
  dubious legality." As one contemporary critic put it, Markoff had *elevated a
  petty criminal to "most wanted" status, and then helped to catch him* — and then
  sold the rights. Markoff flatly denied being anything more than "an observer";
  his lawyers called Littman's charges defamatory.

- **Mitnick's own account** (*Ghost in the Wires*, 2011): expands on the argument
  that Shimomura's and the government's conduct was itself unethical and possibly
  illegal — surveillance and methods that, turned around, looked a great deal like
  the crimes Mitnick was charged with.

You do not have to resolve this. You should *know* it is unresolved. The evidence
in this project proves what was *typed*. It does not prove who was the hero, or
whether there was one.

---

## Part V — What happened to the man

Mitnick was held for years — a long stretch of it in solitary confinement, on the
strength of a prosecutor's claim, now infamous, that he might whistle launch codes
into a prison payphone. The myth, in other words, shaped the punishment. In the
end the towering charges mostly collapsed; he pleaded and was sentenced, serving
five years total, released in 2000.

Then he did the thing that reframes the whole story: he became one of the most
respected security professionals in the world. He ran Mitnick Security Consulting.
He wrote books teaching the very awareness that would have stopped him. He stood on
stages and explained, patiently, that the weakest link was never the cryptography —
it was the person who wanted to be helpful. The hacker the government said was the
most dangerous man on a keyboard spent his second act teaching everyone else how
not to be the next victim.

He died on July 16, 2023, of pancreatic cancer, at 59.

The conventional wisdom in 1995 was that the good guy won and the bad guy went to
jail. Time has not been kind to that binary. Of the figures in this story, it is
Kevin Mitnick who is the better-known and more trusted name in security today — not
despite having been on the losing end of the chase, but because of what he chose to
do with the rest of his life.

---

## Now go solve the box

You are about to use his keyboard's techniques against a single host: find the
trust, abuse it, escalate, take the loot. As you do, remember the three things the
box cannot show you, because they are the actual lesson:

1. The real foothold came from a **conversation**, not an exploit.
2. The real attack was **dozens of hosts over days**, not one box in one sitting.
3. The real story has **no agreed-upon hero** — only a typed record, and a man who
   spent his life telling everyone what it really meant.

Check the transcript when you want to know what's real. Question everything else.

That's the lesson. *My kung fu is not stronger than yours — it's just better
documented.*

---

*Primary evidence: the 27 captured sessions in this project's evidence repository
(see `TIMELINE.md`), hash-verified, with the chain of custody documented in
`PROVENANCE.md`. Secondary accounts cited as contested: Shimomura & Markoff,*
Takedown *(1996); Littman,* The Fugitive Game *(1996); Mitnick & Simon,* Ghost in
the Wires *(2011); U.S. Department of Justice arrest release, February 15, 1995.
Where these conflict, the conflict is shown, not resolved.*
