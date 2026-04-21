# Project Hail Mary — Lost Signal
## Raspberry Pi Architecture Document

---

## Network Diagram

```mermaid
graph TD
    SW[Network Switch] --> A
    SW --> SOL
    SW --> TAU
    SW --> ERI

    A[👩‍💻 Student Machine\nhydra · hashcat · ftp · ssh · nmap]

    subgraph SOL[sol — Raspberry Pi 1]
        S1[SSH :22\nTimeout: 3min]
        S2["/var/mail/ryland\nemail draft → stratt:petrova"]
    end

    subgraph TAU[tau-ceti — Raspberry Pi 2]
        T1[FTP :21\nTimeout: 3min]
        T2[shadow file\nrocky MD5crypt hash]
    end

    subgraph ERI[eridani — Raspberry Pi 3]
        E1[SSH :22\nRate-limited\nTimeout: 3min]
        E2[~/astrophage_data.txt\nDECOY]
        E3[~/.astrophage_data.txt\nFLAG]
    end

    A -->|ssh ryland:astrophage| SOL
    A -->|ftp stratt:petrova| TAU
    A -->|ssh rocky:adrian| ERI

    SOL -->|credentials in mail| TAU
    TAU -->|shadow file download| A
    A -->|hashcat crack| A
```

---

## Exploitation Flow

```mermaid
flowchart LR
    A([Student]) --> B[nmap\ndiscover hosts]
    B --> C[hydra\nbrute-force sol SSH\nrockyou.txt]
    C --> D[ssh into sol\nread /var/mail/ryland]
    D --> E[ftp into tau-ceti\ndownload shadow file]
    E --> F[hashcat\ncrack MD5crypt hash\n→ adrian]
    F --> G[ssh into eridani\nrocky:adrian]
    G --> H[ls → decoy\nastrophage_data.txt]
    H --> I[ls -a or find\n→ .astrophage_data.txt]
    I --> J([FLAG])
```

---

## Hardware

| Pi | Hostname | IP | Model Recommendation |
|----|----------|----|----------------------|
| Pi 1 | `sol` | 10.7.7.1 | Raspberry Pi 3B+ or newer |
| Pi 2 | `tau-ceti` | 10.7.7.2 | Raspberry Pi 3B+ or newer |
| Pi 3 | `eridani` | 10.7.7.3 | Raspberry Pi 3B+ or newer |

- **OS:** Raspberry Pi OS Lite (64-bit, headless)
- **Network:** All three Pis and student machines on the same physical switch — no internet required
- **Static IPs:** Assigned via `/etc/dhcpcd.conf` on each Pi

---

## Pi Specs

### `sol` (10.7.7.1) — Pi 1
- **OS:** Raspberry Pi OS Lite
- **Services:** OpenSSH (`openssh-server`)
- **Users:** `ryland` (password: `astrophage`)
- **Key files:** `/var/mail/ryland` — narrative email draft exposing `stratt:petrova`
- **SSH config** (`/etc/ssh/sshd_config`):
  - `ClientAliveInterval 30`
  - `ClientAliveCountMax 6` (3 minute timeout)

### `tau-ceti` (10.7.7.2) — Pi 2
- **OS:** Raspberry Pi OS Lite
- **Services:** vsftpd
- **Users:** `stratt` (password: `petrova`)
- **Key files:** shadow file containing `rocky`'s MD5crypt hash accessible via FTP
- **FTP config** (`/etc/vsftpd.conf`):
  - `idle_session_timeout=180` (3 minutes)

### `eridani` (10.7.7.3) — Pi 3
- **OS:** Raspberry Pi OS Lite
- **Services:** OpenSSH (`openssh-server`)
- **Users:** `rocky` (password: `adrian`)
- **Key files:**
  - `~/astrophage_data.txt` — decoy, contents: *"Nice try. Look closer."*
  - `~/.astrophage_data.txt` — real flag
- **SSH config** (`/etc/ssh/sshd_config`):
  - `ClientAliveInterval 30`
  - `ClientAliveCountMax 6` (3 minute timeout)
  - `MaxAuthTries 3` (rate limiting)

---

## Setup & Reset

### Initial Setup
Each Pi is configured via a setup script run once after flashing the OS:
- `setup_sol.sh`
- `setup_tau-ceti.sh`
- `setup_eridani.sh`

### Resetting Between Runs
Unlike Docker, Pi state is persistent — files modified or read by students remain changed. Reset scripts restore each Pi to its initial challenge state:
- `reset_sol.sh`
- `reset_tau-ceti.sh`
- `reset_eridani.sh`

Reset scripts should be run between each competition heat.

### SD Card Imaging (Alternative Reset)
For full confidence, maintain a clean SD card image for each Pi. Re-flash between heats using `dd` or the Raspberry Pi Imager. Slower but guarantees clean state.

---

## Shared Server Model

All 15 teams share the same 3 Pis simultaneously. Multiple teams can be connected to the same server at the same time. Since Pis and student machines are on the same physical switch, no routing setup is required — students connect directly to `10.7.7.1`, `10.7.7.2`, and `10.7.7.3` using standard ports.
