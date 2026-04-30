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
MAX_WORKERS = 20


def _read_generate_compose() -> tuple:
    """Return (SUBNET_BASE, NUM_TEAMS, SKIP_SUBNETS) by parsing generate_compose.py."""
    try:
        txt = Path("generate_compose.py").read_text()
        base = re.search(r'^SUBNET_BASE\s*=\s*"(.+?)"', txt, re.MULTILINE)
        teams = re.search(r'^NUM_TEAMS\s*=\s*(\d+)', txt, re.MULTILINE)
        skip_m = re.search(r'^SKIP_SUBNETS\s*=\s*\{([^}]*)\}', txt, re.MULTILINE)
        skip = set()
        if skip_m and skip_m.group(1).strip():
            skip = {int(x.strip()) for x in skip_m.group(1).split(',') if x.strip().isdigit()}
        return (
            base.group(1) if base else "10.7",
            int(teams.group(1)) if teams else 1,
            skip,
        )
    except Exception:
        return "10.7", 1, set()


SUBNET_BASE, NUM_TEAMS, SKIP_SUBNETS = _read_generate_compose()


def _team_subnets() -> list:
    """Return [(team_num, subnet_num), ...] respecting SKIP_SUBNETS."""
    result, octet = [], 0
    for team in range(1, NUM_TEAMS + 1):
        octet += 1
        while octet in SKIP_SUBNETS:
            octet += 1
        result.append((team, octet))
    return result


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


def _all_container_statuses() -> tuple:
    """Return ({short_name: status}, {short_name: full_name}) for every container.

    Docker Compose prefixes the project name and appends an instance number,
    e.g. 'cyberstorm-project-team01-sol-1'. We extract 'team01-sol' as the
    short key for lookups, but keep the full name for docker exec calls.
    """
    try:
        r = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.Names}}\t{{.Status}}"],
            capture_output=True, text=True, timeout=10,
        )
        statuses, full_names = {}, {}
        for line in r.stdout.strip().splitlines():
            if "\t" in line:
                full_name, status = line.split("\t", 1)
                full_name = full_name.strip()
                m = re.search(r"(team\d+-(?:sol|tau|eri))", full_name)
                key = m.group(1) if m else full_name
                statuses[key] = status.strip()
                full_names[key] = full_name
        return statuses, full_names
    except Exception:
        return {}, {}


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
            "tty": parts[1],
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
        state = fields[3]
        if local_port == port and state == "01":
            ip_hex, port_hex = fields[2].split(":")
            ip_str = ".".join(str(b) for b in bytes.fromhex(ip_hex)[::-1])
            peers.append(f"{ip_str}:{int(port_hex, 16)}")
    return peers


def _fetch_detail(name: str, ctype: str) -> dict:
    """Fetch live session/connection data for one running container.

    Docker containers have no utmp, so w/who are empty even with active SSH
    sessions. Use /proc/net/tcp instead for all connection types.
    """
    if ctype in ("sol", "eri"):
        peers = _parse_proc_net_tcp(
            _docker_exec(name, ["cat", "/proc/net/tcp"]), port=22
        )
        sessions = [{"user": "?", "from": p.split(":")[0], "idle": "-", "what": "-"}
                    for p in peers]
        return {"sessions": sessions, "peers": peers}
    if ctype == "tau":
        peers = _parse_proc_net_tcp(
            _docker_exec(name, ["cat", "/proc/net/tcp"]), port=21
        )
        return {"connections": len(peers), "peers": peers}
    return {}


def build_status() -> dict:
    statuses, full_names = _all_container_statuses()
    team_subnets = _team_subnets()

    to_query = [
        (full_names.get(f"team{sn:02d}-{s}", f"team{sn:02d}-{s}"), ct)
        for _, sn in team_subnets
        for s, ct in [("sol", "sol"), ("tau", "tau"), ("eri", "eri")]
        if statuses.get(f"team{sn:02d}-{s}", "").lower().startswith("up")
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
    for team_num, subnet_num in team_subnets:
        containers = {}
        for suffix, ctype, ip_last in [("sol", "sol", 1), ("tau", "tau", 2), ("eri", "eri", 3)]:
            short = f"team{subnet_num:02d}-{suffix}"
            cname = full_names.get(short, short)
            raw_status = statuses.get(short, "missing")
            is_up = raw_status.lower().startswith("up")
            entry = {
                "name": short,
                "ip": f"{SUBNET_BASE}.{subnet_num}.{ip_last}",
                "status": "running" if is_up else "stopped",
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
                entry["peers"] = d.get("peers", [])
                total_sessions += count
            containers[ctype] = entry
        teams.append({"team_num": subnet_num, "containers": containers})

    running = sum(
        1 for nm, st in statuses.items()
        if st.lower().startswith("up") and re.match(r"^team\d+-(sol|tau|eri)$", nm)
    )
    return {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"),
        "summary": {
            "total_teams": NUM_TEAMS,
            "containers_running": running,
            "active_sessions": total_sessions,
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
        n = int(m.group(1))
        mapping = {t: s for t, s in _team_subnets()}
        sn = mapping.get(n, n)
        sol = f"team{sn:02d}-sol"
        tau = f"team{sn:02d}-tau"
        eri = f"team{sn:02d}-eri"
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

    _cache.set(build_status())
    threading.Thread(target=_refresh_loop, daemon=True).start()

    server = HTTPServer(("", args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] stopped")


if __name__ == "__main__":
    main()
