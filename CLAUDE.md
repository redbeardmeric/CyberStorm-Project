# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

CyberStorm is a CTF (Capture the Flag) competition infrastructure for a classroom cybersecurity course (CYEN-301). The challenge is themed around Andy Weir's *Project Hail Mary*. Students exploit a chain of three hosts — `sol`, `tau-ceti`, `eridani` — to recover a hidden flag.

There are two deployment modes:
- **Docker** — classroom/lab use; each team gets its own isolated `/24` subnet with three containers running simultaneously
- **Raspberry Pi** — competition use; 3 physical Pis shared by all teams, reset between heats

## Key Commands

### Full environment startup (Docker)
```bash
./startup.sh <num_teams>
```
This is the single command for instructors. It updates `generate_compose.py`, loads or builds Docker images, generates `docker-compose.yml`, starts all containers, configures nftables/iptables routing, enables IP forwarding, and launches the monitor dashboard.

### Rebuild Docker images manually
```bash
docker build -t ctf-sol ./docker/sol
docker build -t ctf-tau ./docker/tau
docker build -t ctf-eri ./docker/eri
```

### Regenerate docker-compose.yml (after changing NUM_TEAMS or SUBNET_BASE)
```bash
python3 generate_compose.py
```

### Start/stop containers
```bash
docker compose up -d
docker compose down
docker compose restart team<NN>-sol team<NN>-tau team<NN>-eri   # reset one team
docker compose restart                                            # reset all teams
```

### Monitor dashboard
```bash
python3 monitor.py          # http://localhost:8888
python3 monitor.py --port 9000
```

### Pi setup and reset scripts (run on each Pi individually)
```bash
# Initial setup (once after flashing OS)
bash pi/setup_sol.sh
bash pi/setup_tau-ceti.sh
bash pi/setup_eridani.sh

# Reset between competition heats
bash pi/reset_sol.sh
bash pi/reset_tau-ceti.sh
bash pi/reset_eridani.sh
```

## Architecture

### generate_compose.py is the source of truth for configuration

`generate_compose.py` defines three constants that flow everywhere:
- `NUM_TEAMS` — number of teams; `startup.sh` patches this with `sed` before calling the script
- `SUBNET_BASE` — first two octets (default `"10.7"`); change if it conflicts with the physical LAN
- `SKIP_SUBNETS` — subnet octets to skip (currently `{7}`); see below

`monitor.py` parses `generate_compose.py` at startup via regex to read these same values, so they never need to be duplicated.

### Subnet skipping — team numbering vs. subnet numbering

**Team 7 is skipped** (`SKIP_SUBNETS = {7}`). Teams are numbered 1–15, but subnet octets skip 7, so teams 1–6 use subnets 1–6 and teams 7–15 use subnets 8–16. This exists because `10.7.7.0/24` conflicts with the physical router subnet and makes containers unreachable.

`generate_compose.py::subnet_numbers()` and `monitor.py::_team_subnets()` both implement this same skip logic — they must stay in sync.

### Per-team flag generation

The flag is not static. `docker/eri/entrypoint.sh` runs at container start and writes `/home/rocky/.astrophage_data.txt` with the flag `FLAG{astrophage_confirmed_tau_ceti_e_t{TEAM_NUM}}` where `TEAM_NUM` comes from the `TEAM_NUM` environment variable set in `docker-compose.yml`. This makes each team's flag unique and traceable. The Pi deployment uses a fixed flag since Pis are shared.

### Monitor internals

`monitor.py` is a single-file HTTP server that:
- Polls all containers every 5 seconds via `docker ps` and `docker exec ... cat /proc/net/tcp`
- Uses `/proc/net/tcp` (not `w`/`who`) to detect active connections, because Docker containers have no utmp
- Serves `dashboard.html` at `/` and JSON at `/api/status`
- Accepts `POST /api/reset/{n}` to restart a team's three containers
- Uses a thread-safe cache so HTTP requests never block on Docker calls

### nftables workaround in startup.sh

`startup.sh` inserts an nft rule into `ip raw PREROUTING` before iptables rules. This is required because Docker's nftables backend inserts per-container drop rules that silently discard student traffic arriving on the LAN interface before iptables `DOCKER-USER` rules can accept it.

### Docker vs. Pi differences

| | Docker | Raspberry Pi |
|---|---|---|
| Isolation | Each team has its own containers | All teams share 3 servers |
| Flag | Team-specific (`t{NN}` suffix) | Single shared flag |
| Reset | `docker compose restart` | Run reset scripts between heats |
| Routing | Static route + iptables/nft on host | No routing needed (same switch) |
| FTP passive ports | 60000–60010 | Standard vsftpd defaults |
