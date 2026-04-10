# Project Hail Mary — Lost Signal
## Instructor Setup Guide

Two deployment options are covered below. Use **Docker** for classroom labs (15 isolated team environments on one machine). Use **Raspberry Pi** for the live competition (shared physical servers, one environment per server).

---

# Part 1 — Docker Setup

## Prerequisites

- Ubuntu/Debian host machine with a static LAN IP (e.g. `192.168.1.100`)
- Docker Engine installed ([docs.docker.com/engine/install](https://docs.docker.com/engine/install))
- Docker Compose v2 (`docker compose` — not `docker-compose`)
- Python 3
- Student machines on the same physical network as the host

Verify Docker is working:
```bash
docker run --rm hello-world
```

---

## Step 1 — Get the Project Files

Copy the project directory to the host machine. Confirm the structure looks like this:

```
CyberStorm Project/
├── docker/
│   ├── sol/
│   │   ├── Dockerfile
│   │   ├── sshd_config
│   │   └── mail_ryland.txt
│   ├── tau/
│   │   ├── Dockerfile
│   │   ├── vsftpd.conf
│   │   ├── entrypoint.sh
│   │   └── shadow
│   └── eri/
│       ├── Dockerfile
│       ├── sshd_config
│       ├── astrophage_data.txt
│       └── astrophage_data_real.txt
├── generate_compose.py
└── docker-compose.yml
```

---

## Step 2 — Build the Docker Images

From the project root, build all three images:

```bash
docker build -t ctf-sol ./docker/sol
docker build -t ctf-tau ./docker/tau
docker build -t ctf-eri ./docker/eri
```

Each build takes 30–60 seconds. Confirm all three images exist:

```bash
docker images | grep ctf-
```

Expected output:
```
ctf-eri    latest   ...
ctf-tau    latest   ...
ctf-sol    latest   ...
```

---

## Step 3 — Generate the Compose File

```bash
python3 generate_compose.py
```

This writes `docker-compose.yml` with 15 isolated team networks (`10.7.1.0/24` through `10.7.15.0/24`), each containing three containers. The gateway for each network is set to `.254` so containers can use `.1`, `.2`, and `.3`.

To change the number of teams, edit `NUM_TEAMS` at the top of `generate_compose.py` and re-run.

---

## Step 4 — Start All Containers

```bash
docker compose up -d
```

This starts 45 containers (3 per team × 15 teams). Verify they are all running:

```bash
docker compose ps --status running -q | wc -l
```

Should print `45`. If any containers are not running, check logs:

```bash
docker compose logs <container-name>
```

---

## Step 5 — Enable IP Forwarding on the Host

Student machines need to route into the Docker networks through the host. Enable IP forwarding:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

To make this persist across reboots:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

---

## Step 6 — Open Docker Networks to Student Traffic

Find the name of the host's physical LAN interface (the one connected to the student network):

```bash
ip route | grep default
```

The interface name appears after `dev` (e.g. `eth0`, `ens3`, `enp2s0`).

Allow student traffic to reach the `10.7.0.0/16` range:

```bash
sudo iptables -I DOCKER-USER -i <interface> -d 10.7.0.0/16 -j ACCEPT
sudo iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Replace `<interface>` with your actual interface name.

> **Note:** These iptables rules are lost on reboot. To persist them, install `iptables-persistent`:
> ```bash
> sudo apt install iptables-persistent
> sudo netfilter-persistent save
> ```

---

## Step 7 — Student Machine Setup

Each student machine needs one static route added. Give each team their team number `N` and the host IP.

```bash
sudo ip route add 10.7.<N>.0/24 via 192.168.1.100
```

Replace `192.168.1.100` with your host machine's actual LAN IP.

This route is lost on reboot. To persist it on Debian/Ubuntu, add to `/etc/network/interfaces`:

```
up ip route add 10.7.<N>.0/24 via 192.168.1.100
```

After adding the route, students can reach their containers:

```
sol       →  10.7.<N>.1   (SSH :22)
tau-ceti  →  10.7.<N>.2   (FTP :21)
eridani   →  10.7.<N>.3   (SSH :22)
```

---

## Step 8 — Verify End-to-End

Run this quick check from a student machine (substituting `N`):

```bash
# Host discovery
nmap -sV 10.7.N.0/24

# sol SSH
ssh ryland@10.7.N.1           # password: microbiology
cat /var/mail/ryland
exit

# tau-ceti FTP
ftp 10.7.N.2                  # user: stratt / password: petrova
ls
bye

# eridani SSH
ssh rocky@10.7.N.3            # password: adrian
ls -a ~
exit
```

---

## Resetting a Team Between Runs

Restarting a team's containers restores them to their original image state:

```bash
docker compose restart team03-sol team03-tau team03-eri
```

Replace `03` with the team number (zero-padded to two digits).

To reset all teams at once:

```bash
docker compose restart
```

---

## Tearing Down Everything

```bash
docker compose down
```

---

---

# Part 2 — Raspberry Pi Setup

## Overview

Three Raspberry Pis are each dedicated to one server role. All Pis and student machines connect to the same physical network switch — no routing setup required.

| Pi   | Hostname   | IP       | Role       |
|------|------------|----------|------------|
| Pi 1 | `sol`      | 10.7.7.1 | SSH server |
| Pi 2 | `tau-ceti` | 10.7.7.2 | FTP server |
| Pi 3 | `eridani`  | 10.7.7.3 | SSH server |

---

## Prerequisites

- 3× Raspberry Pi 3B+ or newer
- 3× microSD cards (8 GB minimum)
- Raspberry Pi Imager ([raspberrypi.com/software](https://www.raspberrypi.com/software/))
- Physical network switch
- Ethernet cables for each Pi and each student machine

---

## Step 1 — Flash Raspberry Pi OS

Using Raspberry Pi Imager, flash **Raspberry Pi OS Lite (64-bit)** to each SD card.

In the Imager's advanced settings (gear icon):
- Enable SSH
- Set a hostname (`sol`, `tau-ceti`, or `eridani` respectively)
- Set a temporary admin password (e.g. `setup123`) — you'll use this to run the setup script

Flash all three cards before moving on.

---

## Step 2 — Assign Static IPs

Insert each SD card, boot each Pi, and SSH in using the hostname you set:

```bash
ssh pi@sol.local        # or by DHCP IP
ssh pi@tau-ceti.local
ssh pi@eridani.local
```

On each Pi, edit `/etc/dhcpcd.conf` to assign a static IP. Add to the bottom of the file:

**sol:**
```
interface eth0
static ip_address=10.7.7.1/24
```

**tau-ceti:**
```
interface eth0
static ip_address=10.7.7.2/24
```

**eridani:**
```
interface eth0
static ip_address=10.7.7.3/24
```

Reboot each Pi:

```bash
sudo reboot
```

Confirm you can reach each Pi at its static IP before continuing.

---

## Step 3 — Run Setup Scripts

Copy the setup scripts from `pi/` to each Pi and run them as root.

**Pi 1 — sol:**
```bash
scp pi/setup_sol.sh pi@10.7.7.1:~
ssh pi@10.7.7.1 "sudo bash ~/setup_sol.sh"
```

**Pi 2 — tau-ceti:**
```bash
scp pi/setup_tau-ceti.sh pi@10.7.7.2:~
ssh pi@10.7.7.2 "sudo bash ~/setup_tau-ceti.sh"
```

**Pi 3 — eridani:**
```bash
scp pi/setup_eridani.sh pi@10.7.7.3:~
ssh pi@10.7.7.3 "sudo bash ~/setup_eridani.sh"
```

Each script installs the required service, creates the challenge user, and places all challenge files.

---

## Step 4 — Verify Each Pi

**sol:**
```bash
ssh ryland@10.7.7.1        # password: microbiology
cat /var/mail/ryland
exit
```

**tau-ceti:**
```bash
ftp 10.7.7.2               # user: stratt / password: petrova
ls
get shadow
bye
cat shadow
```

**eridani:**
```bash
ssh rocky@10.7.7.3         # password: adrian
ls -a ~
cat ~/.astrophage_data.txt
exit
```

---

## Step 5 — Student Machine Setup

Student machines must be connected to the same switch as the Pis. No routing configuration is needed — students connect directly to `10.7.7.1`, `10.7.7.2`, and `10.7.7.3`.

Confirm connectivity with a ping:

```bash
ping 10.7.7.1
```

---

## Resetting Between Heats

Run the reset script on each Pi to restore challenge files to their original state:

```bash
ssh pi@10.7.7.1 "sudo bash ~/reset_sol.sh"
ssh pi@10.7.7.2 "sudo bash ~/reset_tau-ceti.sh"
ssh pi@10.7.7.3 "sudo bash ~/reset_eridani.sh"
```

Reset scripts restore all challenge files and kick any active sessions. They do **not** uninstall software or remove users — they only restore file contents and permissions.

For a guaranteed clean state, re-flash the SD cards from a saved image (see below).

---

## SD Card Imaging (Optional — Full Reset)

After completing Steps 1–3 on each Pi, create a clean image of each SD card. This lets you re-flash for a guaranteed fresh state between competition heats.

**Create image:**
```bash
sudo dd if=/dev/sdX of=sol_clean.img bs=4M status=progress
```

**Restore image:**
```bash
sudo dd if=sol_clean.img of=/dev/sdX bs=4M status=progress
```

Replace `/dev/sdX` with the actual SD card device. Use `lsblk` to identify it.

> **Warning:** `dd` will destroy all data on the target device with no confirmation prompt. Double-check the device path before running.
