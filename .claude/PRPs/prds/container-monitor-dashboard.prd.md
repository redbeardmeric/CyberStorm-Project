# Container Monitor Dashboard

## Problem Statement

During a CyberStorm CTF session with up to 15 teams, the instructor has no visibility into
which containers are running, which teams are actively working, or what students are doing on
each server. Without this visibility, the instructor cannot gauge class progress, spot students
who are stuck, or verify the environment is healthy before/during a competition heat.

## Evidence

- The project's `startup.sh` only verifies containers started — it has no ongoing monitoring.
- Reset scripts (`reset_*.sh`) manually kick SSH sessions with `pkill`, showing a need to know
  who is connected but no tool to see it.
- Up to 45 containers (15 teams × 3) must be managed simultaneously with no dashboard.
- Assumption: instructors want to see student activity without asking students to report in.

## Proposed Solution

A lightweight Python HTTP server (stdlib only, no pip installs) that serves a single-page
HTML dashboard. The dashboard auto-polls a `/api/status` endpoint every 5 seconds. The
backend executes `docker exec` commands in parallel across all containers and returns
structured JSON covering container state, active sessions, and current user commands.

## Key Hypothesis

We believe a real-time container dashboard will let the instructor monitor all 15 teams at a
glance without leaving the host machine. We'll know it works when the instructor can identify
which teams are connected and what they're doing without running any CLI commands manually.

## What We're NOT Building

- Flag submission tracking — out of scope, separate concern
- Student-facing views — dashboard is instructor-only
- Historical logs or session recording — real-time only, no persistence
- Authentication on the dashboard — it runs on localhost, no exposure to student network
- Raspberry Pi support — Docker mode only for now

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| Poll latency | < 3s for 45 containers | Time backend response with all teams running |
| Data freshness | Auto-refresh every 5s | Observe in browser |
| Zero dependencies | No pip installs required | `python3 monitor.py` just works |

## Open Questions

- [x] ~~Should the dashboard show the container's internal IP alongside the team number?~~ **Yes — show both container name and internal IP on every card.**
- [x] ~~Should FTP connection source IPs be shown (student machine IPs)?~~ **Yes — show peer IPs for FTP connections.**
- [x] ~~Is a "reset team" button (calls docker restart) in scope for a future phase?~~ **Yes — include in this build.**

---

## Users & Context

**Primary User**
- **Who**: CTF instructor/proctor running the Docker host
- **Current behavior**: Manually runs `docker ps`, `docker exec`, checks nothing
- **Trigger**: Students start a challenge heat; instructor opens browser to monitor progress
- **Success state**: Can see all teams' container health and student activity in one tab

**Job to Be Done**
When running a CTF heat, I want to see all container states and active student sessions at a
glance, so I can spot stuck students, verify the environment is healthy, and know when
everyone has finished.

**Non-Users**
Students — they SSH/FTP directly to containers and have no need for this dashboard.

---

## Solution Detail

### Core Capabilities (MoSCoW)

| Priority | Capability | Rationale |
|----------|------------|-----------|
| Must | Show running/stopped state for all containers | Core health visibility |
| Must | Show container name and internal IP on every card | Instructor needs to identify containers |
| Must | Show active SSH session count per container (sol, eri) | Know who's connected |
| Must | Show current command each SSH user is running (`w` output) | Know what they're doing |
| Must | Show source IP of each SSH session | Know which student machine is connected |
| Must | Show active FTP connection count + peer IPs per tau container | FTP has no TTY, need ss |
| Must | Auto-refresh every 5 seconds | Real-time without manual reload |
| Must | "Reset Team" button per team row — restarts all 3 containers | Kick sessions and restore service state |
| Should | Color-code containers (green=running+connected, yellow=running+idle, red=stopped) | Quick scan |
| Should | Show total connected students across all teams | Room-level summary |
| Could | Filter by team number | Useful for 15+ teams |
| Could | Timestamp of last state change | Know when a container went down |
| Won't | Full challenge file restore from dashboard | Use reset scripts for that; restart is sufficient to kick sessions |

### MVP Scope

Single Python file + single HTML file. Python server reads `docker ps` and `docker exec w` /
`docker exec ss` in parallel. HTML polls `/api/status` and renders a team grid. No external
dependencies, no build step.

### User Flow

1. Instructor runs `python3 monitor.py` on the host
2. Opens `http://localhost:8888` in browser
3. Dashboard loads, immediately shows all container states
4. Every 5 seconds the view updates automatically
5. Instructor scans the grid — stopped containers show red, active sessions highlighted

---

## Technical Approach

**Feasibility**: HIGH

**Architecture Notes**

- **Backend**: `monitor.py` — stdlib `http.server` + `subprocess` + `concurrent.futures.ThreadPoolExecutor`
  - `GET /` → serves `dashboard.html`
  - `GET /api/status` → returns cached JSON refreshed every 5s in background thread
  - Parallel `docker exec` across all containers using `ThreadPoolExecutor(max_workers=20)`

- **Container data gathered per poll:**
  - `docker ps --format json` → all container names + status
  - For each running **SSH container** (sol, eri): `docker exec <name> w --no-header`
    - Parses: USER, TTY, FROM (source IP), LOGIN@, IDLE, WHAT (current command)
  - For each running **FTP container** (tau): `docker exec <name> ss -tnp state established '( dport = :21 or sport = :21 )'`
    - Parses: connection count + peer addresses

- **Frontend**: Single HTML file, vanilla JS, no framework
  - `setInterval(() => fetch('/api/status').then(render), 5000)`
  - Grid layout: rows = teams 1–N, columns = sol / tau / eri
  - Each cell: status badge + session list with user + command

- **JSON response shape** (synthetic example):
```json
{
  "generated_at": "2026-04-30T10:00:00",
  "summary": { "total_teams": 15, "containers_running": 43, "active_sessions": 7 },
  "teams": [
    {
      "team_num": 1,
      "containers": {
        "sol":  { "name": "team01-sol", "ip": "10.7.1.1", "status": "running", "sessions": [{ "user": "ryland", "from": "10.7.1.100", "idle": "0:00s", "what": "cat /var/mail/ryland" }] },
        "tau":  { "name": "team01-tau", "ip": "10.7.1.2", "status": "running", "connections": 1, "peers": ["10.7.1.100:54321"] },
        "eri":  { "name": "team01-eri", "ip": "10.7.1.3", "status": "running", "sessions": [] }
      }
    }
  ]
}
```

- **Reset button**: `POST /api/reset/<team_num>` → runs `docker compose restart team<NN>-sol team<NN>-tau team<NN>-eri` from project root (line 132 of `startup.sh`). Restarts the containers, kicking all active SSH/FTP sessions. Does **not** restore modified challenge files — use the pi reset scripts for full restore.
  - Server must be started from the project root (same directory as `docker-compose.yml`)
  - Confirmation dialog in the UI before firing the request

**Technical Risks**

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| 45 parallel `docker exec` slow to respond | M | ThreadPoolExecutor + 5s timeout per exec; serve cached result |
| `w` not in debian:bookworm-slim image | L | `procps` package provides `w` — verify/add to Dockerfiles |
| vsftpd `ss` parsing fragile | M | Fall back to connection count only if parse fails |
| Port 8888 already in use on host | L | Make port configurable via CLI arg |
| Reset button misfire during active heat | M | Confirmation dialog: "Reset Team NN? This kicks all active sessions." |

---

## Implementation Phases

| # | Phase | Description | Status | Parallel | Depends | PRP Plan |
|---|-------|-------------|--------|----------|---------|----------|
| 1 | Backend server | Python monitor script: Docker data collection + JSON API + background refresh | in-progress | with 2 | - | `.claude/PRPs/plans/container-monitor-dashboard.plan.md` |
| 2 | HTML dashboard | Auto-polling team grid showing container name, IP, status cards | in-progress | with 1 | - | `.claude/PRPs/plans/container-monitor-dashboard.plan.md` |
| 3 | SSH session detail | Parse `w` output: user, source IP, current command per SSH container | in-progress | with 4 | 1, 2 | `.claude/PRPs/plans/container-monitor-dashboard.plan.md` |
| 4 | FTP connections | Parse `ss` output for tau containers: count + peer IPs | in-progress | with 3 | 1, 2 | `.claude/PRPs/plans/container-monitor-dashboard.plan.md` |
| 5 | Reset button | POST /api/reset/<team_num> endpoint + confirmation dialog in UI | in-progress | - | 3, 4 | `.claude/PRPs/plans/container-monitor-dashboard.plan.md` |
| 6 | Polish & summary | Header totals bar, color coding, responsive grid layout | in-progress | - | 5 | `.claude/PRPs/plans/container-monitor-dashboard.plan.md` |

### Phase Details

**Phase 1: Backend server**
- **Goal**: Working Python server that returns valid JSON for all teams
- **Scope**: `monitor.py` — `/` and `/api/status` routes, background refresh thread, parallel docker exec
- **Success signal**: `curl localhost:8888/api/status` returns correct JSON with all teams

**Phase 2: HTML dashboard**
- **Goal**: Browser shows a team grid that auto-updates
- **Scope**: `dashboard.html` — renders container status cards, polls every 5s
- **Success signal**: Page loads, refreshes, shows running/stopped state for all containers

**Phase 3: SSH session detail**
- **Goal**: Instructor sees who is logged in and what they're doing on SSH containers
- **Scope**: Parse `docker exec <name> w --no-header`; surface user, from IP, command in each card
- **Success signal**: When a student SSHes in, their username and current command appears within 5s

**Phase 4: FTP connections**
- **Goal**: Show active FTP sessions on tau containers
- **Scope**: Parse `docker exec <name> ss -tnp state established` for port 21; show count + peer IPs
- **Success signal**: FTP card updates when a student connects via `ftp`

**Phase 5: Reset button**
- **Goal**: Instructor can restart any team's containers from the dashboard
- **Scope**: `POST /api/reset/<team_num>` in backend runs `docker compose restart team<NN>-{sol,tau,eri}`; UI shows a confirmation dialog before firing; button per team row
- **Success signal**: Clicking reset, confirming, and observing containers restart and sessions drop

**Phase 6: Polish & summary**
- **Goal**: Dashboard is scannable at a glance for 15 teams
- **Scope**: Header bar with totals (containers up, active sessions); color coding per card; clean layout
- **Success signal**: Instructor can identify all active teams in under 10 seconds

### Parallelism Notes

Phases 1 and 2 can be developed in parallel since they share a clear JSON contract defined
above. Phases 3 and 4 can also run in parallel once 1 and 2 are working.

---

## Decisions Log

| Decision | Choice | Alternatives | Rationale |
|----------|--------|--------------|-----------|
| Backend language | Python stdlib | Flask, Node, bash | Zero install, already on any Linux host |
| Data collection | `docker exec w` + `docker exec ss` | Docker SDK, log parsing | No pip deps; direct and readable |
| Refresh model | Server-side cache + client polling | WebSockets, SSE | Simpler; 5s polling is fine for classroom |
| Dashboard delivery | Single HTML file served by Python | Separate static files | One `python3 monitor.py` command, nothing else |
| Port | 8888 | 80, 8080 | Avoids common conflicts; configurable via arg |
| Reset scope | `docker compose restart` (kicks sessions) | Full reset scripts (also restores files) | Dashboard button is for emergency session kick; file restore is a separate deliberate action |
| Reset safety | Confirmation dialog in UI | No confirmation | Prevents accidental reset during active heat |

---

## Research Summary

**Market Context**
Standard CTF platforms (CTFd, rCTF) focus on flag submission and scoreboards, not live
infrastructure monitoring. Portainer and similar Docker dashboards are overkill for a
single-host classroom setup. A custom minimal tool is the right fit.

**Technical Context**
- `w` command is provided by the `procps` package (debian:bookworm-slim base) — needs
  verification that `procps` is installed in sol/eri Dockerfiles, or must be added
- `ss` is provided by `iproute2` (typically pre-installed on debian:bookworm-slim)
- `docker ps --format '{{json .}}'` gives reliable structured output per container
- ThreadPoolExecutor with 20 workers handles 45 containers well within 3s at typical
  `docker exec` latency of ~50–100ms each

---

*Generated: 2026-04-30*
*Status: DRAFT*
