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

Run this command to get access to your network:
``` bash
sudo ip route add 10.7.<N>.0/24 via <HOST IP>
```

| Hostname   | IP          | Service |
|------------|-------------|---------|
| `sol`      |   Unknown   | Unknown |
| `tau-ceti` |   Unknown   | Unknown |
| `eridani`  |   Unknown   | Unknown |

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

Good luck.
