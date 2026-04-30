# Plan: Container Monitor Dashboard

## Summary

A stdlib-only Python HTTP server (`monitor.py`) and a single-page HTML dashboard
(`dashboard.html`) that give the CyberStorm instructor real-time visibility into all team
containers: running/stopped state, active SSH sessions with current commands, active FTP
connections with peer IPs, and a per-team reset button backed by `docker compose restart`.

## User Story

As a CTF instructor running a CyberStorm heat, I want a browser dashboard that auto-refreshes
every 5 seconds, so that I can see which containers are up, which teams are working, and what
commands students are running — without typing any CLI commands.

## Problem → Solution

No monitoring exists beyond a startup health check → Python server + HTML frontend polling
`/api/status` every 5s, backed by parallel `docker exec` calls for live session data.

## Metadata

- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/container-monitor-dashboard.prd.md`
- **PRD Phases**: 1–6 (all phases planned together; phases 1+2 are parallel, 3+4 are parallel)
- **Estimated Files**: 4 (monitor.py, dashboard.html, docker/sol/Dockerfile, docker/eri/Dockerfile)

---

## UX Design

### Before

```
Instructor has no visibility:
  $ docker ps          <- manual, shows all 45 containers as a wall of text
  $ docker exec team01-sol w    <- must run per-container
  $ docker exec team01-tau ...  <- manual, no overview
```

### After

```
+-----------------------------------------------------------------------------+
|  CyberStorm Monitor           15 teams . 43/45 running . 7 active sessions  |
|  Last updated: 10:35:12                                                      |
+--------+---------------------------+------------------------+----------------+
|  Team  |  SOL  ssh :22             |  TAU-CETI  ftp :21     |  ERI  ssh :22  |
+--------+---------------------------+------------------------+----------------+
|  01    |  * RUNNING  team01-sol    |  * RUNNING  team01-tau |  * IDLE        |
|        |    10.7.1.1               |    10.7.1.2             |    10.7.1.3    |
|        |   ryland  10.7.1.100      |  1 conn                 |                |
|        |   cat /var/mail/ryland    |  10.7.1.100:54321       |                |
+--------+---------------------------+------------------------+----------------+
|  02    |  o STOPPED                |  * IDLE                 |  * IDLE        |
+--------+---------------------------+------------------------+----------------+
|  [Reset Team 01]  <- confirmation dialog before firing                       |
+-----------------------------------------------------------------------------+
```

### Interaction Changes

| Touchpoint | Before | After | Notes |
|---|---|---|---|
| Container health check | `docker ps` wall of text | Color-coded table | Green=up+sessions, yellow=up+idle, red=stopped |
| SSH session visibility | `docker exec <n> w` per container | Shown inline on each card | user, source IP, current command |
| FTP connection visibility | None | Connection count + peer IPs | Via `/proc/net/tcp` parsing |
| Session reset | `docker compose restart ...` in terminal | "Reset Team N" button with dialog | Confirms before firing |

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| P0 | `generate_compose.py` | 1-25 | `NUM_TEAMS` and `SUBNET_BASE` constants — backend reads these at startup |
| P0 | `generate_compose.py` | 27-60 | IP assignment: `{BASE}.{n}.1/2/3` for sol/tau/eri |
| P0 | `startup.sh` | 132 | Exact reset command: `docker compose restart team<NN>-sol team<NN>-tau team<NN>-eri` |
| P1 | `docker/sol/Dockerfile` | all | Missing `procps` — must add for `w` command |
| P1 | `docker/eri/Dockerfile` | all | Missing `procps` — must add for `w` command |
| P1 | `docker/tau/Dockerfile` | all | No change needed — use `/proc/net/tcp` instead of `ss` |
| P2 | `docker-compose.yml` | all | Confirms naming: `team01-sol`, `team01-tau`, `team01-eri` |

## External Documentation

| Topic | Key Takeaway |
|---|---|
| `/proc/net/tcp` format | Fields: sl, local_addr, rem_addr, state(01=ESTAB). Addresses are little-endian hex `AABBCCDD:PPPP` |
| `w --no-header` output | Columns: USER TTY FROM LOGIN@ IDLE JCPU PCPU WHAT — use `split(None, 7)` to preserve spaces in WHAT |
| `docker ps --format` | `{{.Names}}\t{{.Status}}` gives tab-separated name + status |
| `http.server` | Override `do_GET`, `do_POST`; override `log_message` to suppress per-request noise |

---

## Patterns to Mirror

No existing Python/HTML in the project — patterns below come from the shell scripts.

### CONFIG_READING_PATTERN
```python
# Mirror: startup.sh:29-35 reads SUBNET_BASE from generate_compose.py via regex
import re
txt = open("generate_compose.py").read()
m = re.search(r'^SUBNET_BASE\s*=\s*"(.+?)"', txt, re.MULTILINE)
SUBNET_BASE = m.group(1) if m else "10.7"
```

### CONTAINER_NAMING_PATTERN
```python
# SOURCE: generate_compose.py SERVICE_BLOCK
# Names are always zero-padded two digits
name = f"team{n:02d}-{suffix}"   # suffix: "sol", "tau", "eri"
ip   = f"{SUBNET_BASE}.{n}.{ip_last}"  # ip_last: 1, 2, 3
```

### RESET_COMMAND_PATTERN
```bash
# SOURCE: startup.sh:132
# Must run from project root where docker-compose.yml lives
docker compose restart team<NN>-sol team<NN>-tau team<NN>-eri
```

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `docker/sol/Dockerfile` | UPDATE | Add `procps` to apt-get install — provides `w` command |
| `docker/eri/Dockerfile` | UPDATE | Add `procps` to apt-get install — provides `w` command |
| `monitor.py` | CREATE | Python stdlib HTTP server with Docker data collection |
| `dashboard.html` | CREATE | Auto-polling single-page HTML dashboard |

## NOT Building

- Authentication — dashboard is localhost-only
- Historical logs or session recording
- Full challenge file restore — `docker compose restart` is sufficient to kick sessions
- Raspberry Pi support
- Flag tracking or scoring

---

## Step-by-Step Tasks

### Task 1: Add `procps` to sol and eri Dockerfiles

- **ACTION**: Edit both Dockerfiles — add `procps` on the same `apt-get install` line
- **IMPLEMENT**:
  ```dockerfile
  # docker/sol/Dockerfile  (identical change for docker/eri/Dockerfile)
  RUN apt-get update && apt-get install -y openssh-server procps && rm -rf /var/lib/apt/lists/*
  ```
- **MIRROR**: Existing `apt-get install -y` pattern already in both files
- **GOTCHA**: Must be on the same line to avoid creating an extra layer with a stale package index
- **VALIDATE**: `docker build -t ctf-sol ./docker/sol && docker run --rm ctf-sol w --version` — should print procps version, not "not found"

---

### Task 2: Create `monitor.py` — config, parsers, Docker queries

- **ACTION**: Create `monitor.py` in project root; implement config reading, parsers, and Docker exec wrappers
- **IMPLEMENT**:

```python
#!/usr/bin/env python3
"""CyberStorm container monitor. Run from project root: python3 monitor.py [--port N]"""
import argparse
import json
import re
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

DEFAULT_PORT = 8888
REFRESH_SECS = 5
EXEC_TIMEOUT = 5
MAX_WORKERS  = 20


def _read_generate_compose() -> tuple:
    """Return (SUBNET_BASE, NUM_TEAMS) by parsing generate_compose.py."""
    try:
        txt = Path("generate_compose.py").read_text()
        base  = re.search(r'^SUBNET_BASE\s*=\s*"(.+?)"', txt, re.MULTILINE)
        teams = re.search(r'^NUM_TEAMS\s*=\s*(\d+)',      txt, re.MULTILINE)
        return (base.group(1) if base else "10.7"), (int(teams.group(1)) if teams else 1)
    except Exception:
        return "10.7", 1


SUBNET_BASE, NUM_TEAMS = _read_generate_compose()


def _docker_exec(container: str, cmd: list) -> str:
    """Run cmd inside container; return stdout or '' on any error."""
    try:
        r = subprocess.run(
            ["docker", "exec", container] + cmd,
            capture_output=True, text=True, timeout=EXEC_TIMEOUT,
        )
        return r.stdout
    except Exception:
        return ""


def _all_container_statuses() -> dict:
    """Return {container_name: status_string} for every container."""
    try:
        r = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.Names}}\t{{.Status}}"],
            capture_output=True, text=True, timeout=10,
        )
        out = {}
        for line in r.stdout.strip().splitlines():
            if "\t" in line:
                name, status = line.split("\t", 1)
                out[name.strip()] = status.strip()
        return out
    except Exception:
        return {}


def _parse_w_output(raw: str) -> list:
    """Parse `w --no-header` stdout into a list of session dicts.

    w columns: USER TTY FROM LOGIN@ IDLE JCPU PCPU WHAT
    split(None, 7) preserves spaces inside WHAT (e.g. 'ls -la /home/rocky').
    """
    sessions = []
    for line in raw.strip().splitlines():
        parts = line.split(None, 7)
        if len(parts) < 3:
            continue
        sessions.append({
            "user": parts[0],
            "tty":  parts[1],
            "from": parts[2],
            "idle": parts[4] if len(parts) > 4 else "-",
            "what": parts[7].strip() if len(parts) > 7 else "-",
        })
    return sessions


def _parse_proc_net_tcp(raw: str, port: int = 21) -> list:
    """Parse /proc/net/tcp and return peer 'IP:port' strings for ESTABLISHED
    connections where the local port matches `port`.

    /proc/net/tcp encodes addresses in little-endian hex: AABBCCDD:PPPP
    State 01 = ESTABLISHED, 0A = LISTEN.
    """
    peers = []
    for line in raw.strip().splitlines()[1:]:   # skip header row
        fields = line.split()
        if len(fields) < 4:
            continue
        local_port = int(fields[1].split(":")[1], 16)
        state      = fields[3]
        if local_port == port and state == "01":
            ip_hex, port_hex = fields[2].split(":")
            ip_str = ".".join(str(b) for b in bytes.fromhex(ip_hex)[::-1])
            peers.append(f"{ip_str}:{int(port_hex, 16)}")
    return peers


def _fetch_detail(name: str, ctype: str) -> dict:
    """Fetch live session/connection data for one running container."""
    if ctype in ("sol", "eri"):
        return {"sessions": _parse_w_output(_docker_exec(name, ["w", "--no-header"]))}
    if ctype == "tau":
        peers = _parse_proc_net_tcp(_docker_exec(name, ["cat", "/proc/net/tcp"]))
        return {"connections": len(peers), "peers": peers}
    return {}
```

- **IMPORTS**: All stdlib — `argparse json re subprocess sys threading time concurrent.futures datetime http.server pathlib`
- **GOTCHA**: `bytes.fromhex(ip_hex)[::-1]` — the `[::-1]` reversal is critical; without it IPs are wrong
- **GOTCHA**: `split(None, 7)` not `split()` — maxsplit=7 keeps WHAT intact when it contains spaces
- **VALIDATE**: `python3 -c "from monitor import _parse_w_output; s=_parse_w_output('ryland pts/0 10.7.1.100 11:30 0.00s 0.05s 0.00s cat /var/mail/ryland'); assert s[0]['what']=='cat /var/mail/ryland'; print('ok')"` prints `ok`

---

### Task 3: Add `build_status()`, `_Cache`, and background refresh to `monitor.py`

- **ACTION**: Append status assembly, thread-safe cache, and refresh loop to `monitor.py`
- **IMPLEMENT**:

```python
def build_status() -> dict:
    statuses = _all_container_statuses()

    # Only query containers that are actually running
    to_query = [
        (f"team{n:02d}-{s}", ct)
        for n in range(1, NUM_TEAMS + 1)
        for s, ct in [("sol","sol"), ("tau","tau"), ("eri","eri")]
        if statuses.get(f"team{n:02d}-{s}", "").lower().startswith("up")
    ]

    detail: dict = {}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(_fetch_detail, n, ct): n for n, ct in to_query}
        for fut, cname in futures.items():
            try:
                detail[cname] = fut.result()
            except Exception:
                detail[cname] = {}

    total_sessions = 0
    teams = []
    for n in range(1, NUM_TEAMS + 1):
        containers = {}
        for suffix, ctype, ip_last in [("sol","sol",1), ("tau","tau",2), ("eri","eri",3)]:
            cname      = f"team{n:02d}-{suffix}"
            raw_status = statuses.get(cname, "missing")
            is_up      = raw_status.lower().startswith("up")
            entry = {
                "name":       cname,
                "ip":         f"{SUBNET_BASE}.{n}.{ip_last}",
                "status":     "running" if is_up else "stopped",
                "raw_status": raw_status,
            }
            d = detail.get(cname, {})
            if ctype in ("sol", "eri"):
                sessions = d.get("sessions", [])
                entry["sessions"] = sessions
                total_sessions += len(sessions)
            else:
                count = d.get("connections", 0)
                entry["connections"] = count
                entry["peers"]       = d.get("peers", [])
                total_sessions      += count
            containers[ctype] = entry
        teams.append({"team_num": n, "containers": containers})

    running = sum(
        1 for nm, st in statuses.items()
        if st.lower().startswith("up") and re.match(r"^team\d+-(sol|tau|eri)$", nm)
    )
    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
        "summary": {
            "total_teams":        NUM_TEAMS,
            "containers_running": running,
            "active_sessions":    total_sessions,
        },
        "teams": teams,
    }


class _Cache:
    def __init__(self):
        self._data = {}
        self._lock = threading.Lock()

    def set(self, data: dict):
        with self._lock:
            self._data = data

    def get(self) -> dict:
        with self._lock:
            return dict(self._data)


_cache = _Cache()


def _refresh_loop():
    while True:
        try:
            _cache.set(build_status())
        except Exception as e:
            print(f"[refresh] {e}", file=sys.stderr)
        time.sleep(REFRESH_SECS)
```

- **GOTCHA**: `dict(self._data)` returns a shallow copy — sufficient since nested lists/dicts are never mutated after being placed in the cache
- **VALIDATE**: `curl -s localhost:8888/api/status | python3 -m json.tool` returns valid JSON with `generated_at`, `summary`, `teams`

---

### Task 4: Add HTTP handler and `main()` to `monitor.py`

- **ACTION**: Append `Handler`, `main()`, and `__main__` guard to `monitor.py`
- **IMPLEMENT**:

```python
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request stdout noise

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._serve_file("dashboard.html", "text/html; charset=utf-8")
        elif self.path == "/api/status":
            self._send_json(_cache.get())
        else:
            self.send_error(404)

    def do_POST(self):
        m = re.match(r"^/api/reset/(\d+)$", self.path)
        if not m:
            self.send_error(404)
            return
        n   = int(m.group(1))
        sol = f"team{n:02d}-sol"
        tau = f"team{n:02d}-tau"
        eri = f"team{n:02d}-eri"
        try:
            subprocess.run(
                ["docker", "compose", "restart", sol, tau, eri],
                capture_output=True, text=True, timeout=60,
            )
            self._send_json({"ok": True, "team": n})
        except Exception as e:
            self._send_json({"ok": False, "error": str(e)})

    def _serve_file(self, filename: str, content_type: str):
        try:
            data = Path(filename).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self.send_error(404, f"{filename} not found")

    def _send_json(self, obj: dict):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser(description="CyberStorm monitor")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    print(f"[*] {NUM_TEAMS} teams  |  subnet {SUBNET_BASE}.N.0/24")
    print(f"[*] Dashboard -> http://localhost:{args.port}")

    _cache.set(build_status())                              # initial fetch before accepting requests
    threading.Thread(target=_refresh_loop, daemon=True).start()

    server = HTTPServer(("", args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] stopped")


if __name__ == "__main__":
    main()
```

- **GOTCHA**: `Content-Length` must be `str(len(data))` not `len(data)` — `send_header` requires a string value
- **GOTCHA**: `docker compose restart` must find `docker-compose.yml` in CWD — server must be started from the project root
- **VALIDATE**: `python3 monitor.py` prints startup lines; `curl -s -o /dev/null -w "%{http_code}" localhost:8888/` returns `200`

---

### Task 5: Create `dashboard.html`

- **ACTION**: Create `dashboard.html` in project root — dark-themed table, auto-poll, reset button with confirmation
- **IMPLEMENT**:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CyberStorm Monitor</title>
<style>
:root {
  --bg:      #0f1117;
  --surface: #1a1d27;
  --border:  #2a2d3a;
  --green:   #22c55e;
  --yellow:  #eab308;
  --red:     #ef4444;
  --text:    #e2e8f0;
  --muted:   #64748b;
  --mono:    'Consolas', 'Menlo', monospace;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--text); font-family: var(--mono); font-size: 13px; }

header {
  padding: 12px 20px;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  display: flex; align-items: center; gap: 20px; flex-wrap: wrap;
}
header h1 { font-size: 16px; letter-spacing: 1px; color: var(--green); }
.stat { color: var(--muted); }
.stat span { color: var(--text); font-weight: bold; }
#last-updated { margin-left: auto; color: var(--muted); font-size: 11px; }

table { width: 100%; border-collapse: collapse; }
th {
  padding: 8px 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  text-align: left; color: var(--muted);
  font-size: 11px; letter-spacing: 1px; text-transform: uppercase;
}
td { padding: 8px 12px; border: 1px solid var(--border); vertical-align: top; }
tr:hover td { background: rgba(255,255,255,0.02); }
.team-num { font-weight: bold; white-space: nowrap; }

.cell-meta { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; }
.dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.dot.active { background: var(--green); }
.dot.idle   { background: var(--yellow); }
.dot.stopped { background: var(--red); }
.cname { font-weight: bold; font-size: 12px; }
.cip   { color: var(--muted); font-size: 11px; }

.sessions { margin-top: 4px; }
.session {
  background: rgba(255,255,255,0.03);
  border-left: 2px solid var(--green);
  padding: 3px 6px; margin-bottom: 3px;
  border-radius: 0 2px 2px 0;
}
.s-user { color: var(--green); font-weight: bold; }
.s-from { color: var(--muted); }
.s-what { color: var(--text); margin-top: 1px; }

.ftp-count { font-weight: bold; }
.ftp-peer  { color: var(--muted); font-size: 11px; }
.idle-label, .stopped-label { font-size: 11px; }
.idle-label    { color: var(--muted); }
.stopped-label { color: var(--red); }

.reset-btn {
  background: transparent; border: 1px solid #374151;
  color: var(--muted); padding: 4px 10px; border-radius: 4px;
  cursor: pointer; font-family: var(--mono); font-size: 11px; white-space: nowrap;
}
.reset-btn:hover:not(:disabled) { border-color: var(--red); color: var(--red); }
.reset-btn:disabled { opacity: 0.4; cursor: not-allowed; }

#error-bar {
  background: #7f1d1d; color: #fca5a5;
  padding: 8px 20px; font-size: 12px; display: none;
}
</style>
</head>
<body>

<div id="error-bar"></div>

<header>
  <h1>CYBERSTORM MONITOR</h1>
  <div class="stat">Teams: <span id="s-teams">-</span></div>
  <div class="stat">Running: <span id="s-running">-</span></div>
  <div class="stat">Sessions: <span id="s-sessions">-</span></div>
  <div id="last-updated">-</div>
</header>

<table>
  <thead>
    <tr>
      <th>Team</th>
      <th>SOL &middot; ssh :22</th>
      <th>TAU-CETI &middot; ftp :21</th>
      <th>ERIDANI &middot; ssh :22</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody id="tbody"></tbody>
</table>

<script>
const POLL_MS = 5000;

function esc(s) {
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function dotClass(c) {
  if (c.status !== 'running') return 'stopped';
  const n = c.sessions ? c.sessions.length : (c.connections || 0);
  return n > 0 ? 'active' : 'idle';
}

function renderSSH(c) {
  const meta = `<div class="cell-meta">
    <span class="dot ${dotClass(c)}"></span>
    <span class="cname">${esc(c.name)}</span>
  </div>
  <div class="cip">${esc(c.ip)}</div>`;

  if (c.status !== 'running') {
    return meta + '<div class="stopped-label">STOPPED</div>';
  }
  const list = (c.sessions || []).map(s => `
    <div class="session">
      <span class="s-user">${esc(s.user)}</span>
      <span class="s-from"> &larr; ${esc(s.from)}</span>
      <div class="s-what">${esc(s.what)}</div>
    </div>`).join('');
  return meta + '<div class="sessions">'
    + (list || '<span class="idle-label">idle</span>')
    + '</div>';
}

function renderFTP(c) {
  const meta = `<div class="cell-meta">
    <span class="dot ${dotClass(c)}"></span>
    <span class="cname">${esc(c.name)}</span>
  </div>
  <div class="cip">${esc(c.ip)}</div>`;

  if (c.status !== 'running') {
    return meta + '<div class="stopped-label">STOPPED</div>';
  }
  if (!c.connections) {
    return meta + '<span class="idle-label">idle</span>';
  }
  const peers = (c.peers || []).map(p =>
    `<div class="ftp-peer">${esc(p)}</div>`).join('');
  return meta + `<div class="ftp-count">${c.connections} conn</div>${peers}`;
}

function render(data) {
  document.getElementById('error-bar').style.display = 'none';
  const s = data.summary;
  document.getElementById('s-teams').textContent    = s.total_teams;
  document.getElementById('s-running').textContent  = s.containers_running + '/' + (s.total_teams * 3);
  document.getElementById('s-sessions').textContent = s.active_sessions;
  document.getElementById('last-updated').textContent =
    'Updated ' + (data.generated_at || '').split('T')[1];

  document.getElementById('tbody').innerHTML = data.teams.map(team => {
    const { sol, tau, eri } = team.containers;
    const num = String(team.team_num).padStart(2, '0');
    return `<tr>
      <td class="team-num">Team ${num}</td>
      <td>${renderSSH(sol)}</td>
      <td>${renderFTP(tau)}</td>
      <td>${renderSSH(eri)}</td>
      <td><button class="reset-btn" onclick="resetTeam(${team.team_num},this)">Reset</button></td>
    </tr>`;
  }).join('');
}

function showError(msg) {
  const el = document.getElementById('error-bar');
  el.textContent = msg;
  el.style.display = 'block';
}

async function poll() {
  try {
    const r = await fetch('/api/status');
    if (!r.ok) throw new Error('HTTP ' + r.status);
    render(await r.json());
  } catch (e) {
    showError('Connection error: ' + e.message + ' — retrying...');
  }
}

async function resetTeam(num, btn) {
  const label = 'Team ' + String(num).padStart(2,'0');
  if (!confirm('Reset ' + label + '?\n\nThis restarts all 3 containers and kicks all active sessions.')) return;
  btn.disabled = true;
  btn.textContent = 'Resetting…';
  try {
    const r = await fetch('/api/reset/' + num, { method: 'POST' });
    const d = await r.json();
    btn.textContent = d.ok ? 'Done' : 'Error';
  } catch (_) {
    btn.textContent = 'Error';
  }
  setTimeout(() => { btn.disabled = false; btn.textContent = 'Reset'; }, 3000);
}

poll();
setInterval(poll, POLL_MS);
</script>
</body>
</html>
```

- **GOTCHA**: `esc()` must wrap every value rendered into innerHTML — students can run commands containing `<script>` or `&` characters
- **GOTCHA**: `onclick="resetTeam(${team.team_num},this)"` is safe — `team_num` is an integer from the JSON, never a string
- **VALIDATE**: Open `http://localhost:8888`; table renders; Network tab shows `/api/status` fetches firing every 5s; clicking Reset shows browser `confirm()` dialog

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected Output | Edge Case? |
|---|---|---|---|
| `_parse_w_output` normal | `"ryland pts/0 10.7.1.100 11:30 0.00s 0.05s 0.00s cat /var/mail/ryland"` | `[{user:"ryland", from:"10.7.1.100", what:"cat /var/mail/ryland"}]` | No |
| `_parse_w_output` multi-word WHAT | `"rocky pts/1 10.7.1.101 11:35 0.00s 0.01s 0.00s ls -la /home/rocky"` | `what == "ls -la /home/rocky"` | Yes |
| `_parse_w_output` empty | `""` | `[]` | Yes |
| `_parse_proc_net_tcp` ESTAB port 21 | line with local `:0015` and state `01` | one peer entry | No |
| `_parse_proc_net_tcp` LISTEN state | line with state `0A` | `[]` | Yes |
| `_parse_proc_net_tcp` empty | header only | `[]` | Yes |

### Edge Cases Checklist

- [ ] No containers running — `_all_container_statuses()` returns `{}`; all team entries show "stopped"
- [ ] Container up but `w` returns nothing — `_parse_w_output("")` returns `[]`; card shows "idle"
- [ ] `docker exec` times out — `_docker_exec` catches exception, returns `""`; graceful fallback
- [ ] `generate_compose.py` not in CWD — fallback `("10.7", 1)` used
- [ ] Reset for non-existent team — `docker compose restart` fails; response `{"ok": false, "error": ...}`
- [ ] XSS in command output — `esc()` in dashboard sanitises all dynamic values

---

## Validation Commands

### Syntax check
```bash
python3 -m py_compile monitor.py && echo "syntax ok"
```
EXPECT: `syntax ok`

### Parser unit tests
```bash
python3 - <<'EOF'
from monitor import _parse_w_output, _parse_proc_net_tcp

s = _parse_w_output("ryland   pts/0    10.7.1.100   11:30  0.00s  0.05s  0.00s cat /var/mail/ryland")
assert s[0]["user"] == "ryland"
assert s[0]["from"] == "10.7.1.100"
assert s[0]["what"] == "cat /var/mail/ryland"

s2 = _parse_w_output("rocky    pts/1    10.7.1.101   11:35  0.00s  0.01s  0.00s ls -la /home/rocky")
assert s2[0]["what"] == "ls -la /home/rocky", repr(s2[0]["what"])

assert _parse_w_output("") == []
assert _parse_proc_net_tcp("  sl  local_address\n") == []
print("all tests passed")
EOF
```
EXPECT: `all tests passed`

### Full server smoke test
```bash
cd "/home/james/Home/CyberStorm Project"
python3 monitor.py &
sleep 2
curl -s localhost:8888/api/status | python3 -m json.tool | head -15
curl -s -o /dev/null -w "dashboard: %{http_code}\n" localhost:8888/
kill %1
```
EXPECT: Valid JSON with `generated_at`/`summary`/`teams`; dashboard returns `200`

### Browser validation
```
1. python3 monitor.py
2. Open http://localhost:8888
3. Table renders with team rows
4. Network tab: /api/status fires every ~5s
5. Click Reset on any row -> confirm dialog appears
6. Cancel -> nothing happens; Confirm -> button shows "Resetting..."
```

### Post-Dockerfile-change image test
```bash
docker build -t ctf-sol ./docker/sol
docker run --rm ctf-sol w --version
docker build -t ctf-eri ./docker/eri
docker run --rm ctf-eri w --version
```
EXPECT: procps version string, not "not found"

---

## Acceptance Criteria

- [ ] `python3 monitor.py` starts from project root with no errors and no pip installs
- [ ] `http://localhost:8888` renders all teams and containers
- [ ] Each card shows container name, internal IP, and status dot
- [ ] SSH cards show per-session user, source IP, and current command
- [ ] FTP cards show connection count and peer IPs
- [ ] Data auto-refreshes every 5 seconds
- [ ] Reset button shows confirmation dialog; POST fires to `/api/reset/<n>`
- [ ] `procps` added to sol and eri Dockerfiles
- [ ] All dynamic HTML values go through `esc()`

## Completion Checklist

- [ ] `docker/sol/Dockerfile` — `procps` on the apt-get line
- [ ] `docker/eri/Dockerfile` — `procps` on the apt-get line
- [ ] `monitor.py` — four sections (config+parsers, build_status+cache, Handler, main) complete
- [ ] `dashboard.html` — `esc()` on all dynamic values; `confirm()` before reset POST
- [ ] Server reads `NUM_TEAMS` and `SUBNET_BASE` from `generate_compose.py` — no hardcoded values
- [ ] `docker compose restart` called from CWD (project root)

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Images not rebuilt after Dockerfile edit | M | `w` returns "not found" in containers | Task 1 validate step catches this before testing |
| `/proc/net/tcp` absent | L | FTP shows 0 connections always | Path is guaranteed present on any Linux kernel; no mitigation needed |
| `w` FROM shows `-` for loopback | L | IP displays as `-` | Acceptable display; not an error |
| `docker compose restart` exceeds 60s | L | Handler appears to hang | 60s timeout; UI shows "Resetting..." during wait |
| Port 8888 in use | L | Server fails to bind | `--port` arg lets user pick another port |

## Notes

- `monitor.py` must be started from the project root — the same directory containing
  `docker-compose.yml` and `generate_compose.py`. Both files are read relative to CWD.
- After editing the Dockerfiles, images must be rebuilt and containers force-recreated:
  `docker build -t ctf-sol ./docker/sol && docker build -t ctf-eri ./docker/eri`
  `docker compose up -d --force-recreate team01-sol team01-eri` (or all teams)
- `dashboard.html` is a separate file so it can be edited without restarting the server.
- The `/proc/net/tcp` approach for FTP is IPv4-only — correct here since all Docker networks
  are IPv4 only (`ipam.config.subnet` in the compose file).
