# Project Hail Mary — Lost Signal
## CyberStorm Challenge Design Document

---

## Overview

**Challenge Name:** Lost Signal
**Theme:** Project Hail Mary — stellar bodies from Andy Weir's novel
**Target Class:** CYEN-301 Intro to Cybersecurity
**Format:** Team-based, progressive CTF

**Narrative:**
You've lost contact with the Hail Mary mission. Classified astrophage research is locked across three remote systems named after key stellar bodies from the mission. Find the data before it's lost forever.

---

## Infrastructure

Three hosts on a shared network (e.g. 10.7.7.x range):

| Hostname   | IP          | Service        | User     | Password    |
|------------|-------------|----------------|----------|-------------|
| `sol`      | 10.7.7.1    | SSH            | `ryland` | `astrophage` |
| `tau-ceti` | 10.7.7.2    | FTP            | `stratt` | `petrova`   |
| `eridani`  | 10.7.7.3    | SSH (rate-limited) | `rocky` | `adrian` |

---

## Exploitation Chain

### Step 1 — Enumeration
- Tool: `nmap`
- Scan the 10.7.7.x network to discover all three hosts and their open services

### Step 2 — Credential Attack on `sol`
- Tool: `hydra`
- Brute-force SSH login for user `ryland` on `sol` using rockyou.txt
- Password: `astrophage`

### Step 3 — Intelligence Gathering on `sol`
- Location: `/var/mail/ryland`
- A narrative email draft from Ryland to Stratt that naturally exposes FTP credentials
- Reveals: `stratt:petrova` on `tau-ceti`

### Step 4 — FTP Access on `tau-ceti`
- Tool: `ftp`
- Login as `stratt` with password `petrova`
- Download the shadow file containing `rocky`'s MD5crypt hash

### Step 5 — Offline Password Cracking
- Tool: `hashcat`
- Hash type: MD5crypt (`$1$`)
- Crack `rocky`'s hash → `adrian`

### Step 6 — SSH into `eridani`
- Tool: `ssh`
- Login as `rocky` with password `adrian`
- Note: SSH is rate-limited — brute-force is not viable, cracking the hash first is required

### Step 7 — Finding the Flag
- A decoy file `astrophage_data.txt` exists in `rocky`'s home directory
- Contents: *"Nice try. Look closer."*
- The real flag is `.astrophage_data.txt` (hidden file)
- Tools: `ls -a` or `find`

### Step 8 — Flag
- File: `/home/rocky/.astrophage_data.txt`
- Contents: Narrative classified research paragraph followed by:
  `FLAG{astrophage_confirmed_tau_ceti_e}`

---

## Tool Chain Summary

| Tool       | Purpose                                      |
|------------|----------------------------------------------|
| `nmap`     | Network enumeration — discover hosts/services |
| `hydra`    | SSH brute-force on `sol`                     |
| `ftp`      | Access `tau-ceti`, download shadow file      |
| `hashcat`  | Crack MD5crypt hash for `rocky`              |
| `ssh`      | Access `sol` and `eridani`                   |
| `find`/`ls -a` | Locate hidden flag file on `eridani`    |

---

## Design Notes

- All services are standard default Linux services (SSH, FTP) — no custom servers required
- Rate-limiting on `eridani` SSH enforces the intended path (crack first, then login)
- The decoy file rewards students who slow down and think rather than rushing
- Passwords are all in rockyou.txt and thematically tied to the novel
- Shadow file on `tau-ceti` contains only `rocky`'s hash to keep scope focused

---

## Still To Do

- [x] Write the full email draft content for `/var/mail/ryland`
- [x] Write the contents of `.astrophage_data.txt` (narrative + flag)
- [x] Write setup scripts for each Pi
- [x] Write setup scripts for Docker
- [x] Write student-facing challenge brief
