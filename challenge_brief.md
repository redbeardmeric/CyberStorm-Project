# Project Hail Mary — Lost Signal
## Student Challenge Brief

---

## Situation

Contact with the Hail Mary mission has gone dark.

Classified astrophage research is locked across three remote systems named after stellar bodies from the mission. Your team has been given limited network access to the mission relay grid. Recover the data before the transmission window closes.

**Find the flag. Format:** `FLAG{...}`

---

## Your Network

Each team has an isolated subnet. Your instructor will give you your team number `N`.

| Hostname   | IP          | Service |
|------------|-------------|---------|
| `sol`      | `10.7.N.1`  | Unknown |
| `tau-ceti` | `10.7.N.2`  | Unknown |
| `eridani`  | `10.7.N.3`  | Unknown |

> Replace `N` with your assigned team number throughout (e.g. team 3 uses `10.7.3.x`).

---

## Tools Available

The following tools are installed on your attack machine:

| Tool      | Man Page          |
|-----------|-------------------|
| `nmap`    | `man nmap`        |
| `hydra`   | `hydra -h`        |
| `ftp`     | `man ftp`         |
| `hashcat` | `hashcat --help`  |
| `ssh`     | `man ssh`         |
| `find`    | `man find`        |

A copy of `rockyou.txt` is available at `/usr/share/wordlists/rockyou.txt`.

---

## Rules

- Stay on your team's subnet (`10.7.N.0/24`) — do not probe other teams' ranges
- Do not attempt to attack the host machine or the classroom network
- Flag submission is individual — all team members must submit the flag to receive credit
- There is one flag. It is a text string in the format `FLAG{...}`

---

## Hints

Hints are available from your instructor. Each hint costs points — use them as a last resort.

| Hint # | Costs |
|--------|-------|
| 1      | 10 pts |
| 2      | 20 pts |
| 3      | 30 pts |

---

## Submission

Submit the flag text (`FLAG{...}`) on the course portal under **CyberStorm > Lost Signal > Flag Submission**.

Good luck.
