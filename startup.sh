#!/usr/bin/env bash
# startup.sh — bring up the full CyberStorm challenge environment
# Usage: ./startup.sh <num_teams>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }
die()  { echo "[!] $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------
[[ $# -ne 1 ]] && { echo "Usage: $0 <num_teams>"; exit 1; }
NUM_TEAMS="$1"
[[ ! "$NUM_TEAMS" =~ ^[1-9][0-9]*$ ]] && die "num_teams must be a positive integer (got: $NUM_TEAMS)"

cd "$SCRIPT_DIR"
[[ -d docker/sol && -d docker/tau && -d docker/eri ]] \
    || die "Must be run from the project root (docker/ subdirectory not found)"

# ---------------------------------------------------------------------------
# read SUBNET_BASE from generate_compose.py
# ---------------------------------------------------------------------------
SUBNET_BASE=$(python3 - <<'EOF'
import re, sys
txt = open("generate_compose.py").read()
m = re.search(r'^SUBNET_BASE\s*=\s*"(.+?)"', txt, re.MULTILINE)
print(m.group(1) if m else sys.exit(1))
EOF
)
SUBNET_CIDR="${SUBNET_BASE}.0.0/16"

# ---------------------------------------------------------------------------
# detect LAN interface (interface used for the default route)
# ---------------------------------------------------------------------------
LAN_IFACE=$(ip route show default \
    | awk 'NR==1 { for(i=1;i<=NF;i++) if($i=="dev") { print $(i+1); exit } }')
[[ -z "$LAN_IFACE" ]] && die "Could not detect LAN interface from default route"

# ===========================================================================
# Step 1 — update generate_compose.py
# ===========================================================================
info "Step 1/7 — Setting NUM_TEAMS=$NUM_TEAMS in generate_compose.py"
sed -i "s/^NUM_TEAMS = .*/NUM_TEAMS = $NUM_TEAMS/" generate_compose.py
ok "generate_compose.py updated"

# ===========================================================================
# Step 2 — build Docker images
# ===========================================================================
info "Step 2/7 — Building Docker images (this takes 1–3 min)..."
docker build -t ctf-sol ./docker/sol
docker build -t ctf-tau ./docker/tau
docker build -t ctf-eri ./docker/eri
ok "Images built: ctf-sol  ctf-tau  ctf-eri"

# ===========================================================================
# Step 3 — generate docker-compose.yml
# ===========================================================================
info "Step 3/7 — Generating docker-compose.yml for $NUM_TEAMS team(s)"
python3 generate_compose.py
ok "docker-compose.yml written"

# ===========================================================================
# Step 4 — start containers
# ===========================================================================
EXPECTED=$(( NUM_TEAMS * 3 ))
info "Step 4/7 — Starting $EXPECTED containers..."
docker compose up -d

# give Docker a moment to settle, then verify
sleep 3
RUNNING=$(docker compose ps --status running -q 2>/dev/null | wc -l)
if [[ "$RUNNING" -ne "$EXPECTED" ]]; then
    echo ""
    docker compose ps
    die "$RUNNING / $EXPECTED containers running — inspect with: docker compose logs"
fi
ok "$RUNNING / $EXPECTED containers running"

# ===========================================================================
# Step 5 — enable IP forwarding
# ===========================================================================
info "Step 5/7 — Enabling IP forwarding"
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
ok "net.ipv4.ip_forward = 1"

# ===========================================================================
# Step 6 — iptables rules
# ===========================================================================
info "Step 6/7 — Adding iptables rules (iface: $LAN_IFACE, cidr: $SUBNET_CIDR)"
sudo iptables -I DOCKER-USER -i "$LAN_IFACE" -o br-team+ -d "$SUBNET_CIDR" -j ACCEPT
sudo iptables -I DOCKER-USER -i br-team+ -o "$LAN_IFACE" -d "$SUBNET_CIDR" -j ACCEPT
sudo iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -I POSTROUTING -s "$SUBNET_CIDR" -d "$SUBNET_CIDR" ! -o br-team+ -j ACCEPT
ok "iptables rules added"

# ===========================================================================
# Step 7 — start container monitor
# ===========================================================================
info "Step 7/7 — Starting container monitor"
python3 monitor.py &
MONITOR_PID=$!
ok "Monitor running (PID $MONITOR_PID) -> http://localhost:8888"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "======================================================="
echo "  CyberStorm infrastructure is READY"
echo "======================================================="
printf "  Teams: %d  |  Containers: %d  |  Interface: %s\n" \
    "$NUM_TEAMS" "$RUNNING" "$LAN_IFACE"
printf "  Subnet CIDR: %s\n" "$SUBNET_CIDR"
echo ""
echo "  Team network assignments:"
for n in $(seq 1 "$NUM_TEAMS"); do
    printf "    Team %02d:  sol %-14s  tau-ceti %-14s  eridani %s\n" \
        "$n" \
        "${SUBNET_BASE}.${n}.1" \
        "${SUBNET_BASE}.${n}.2" \
        "${SUBNET_BASE}.${n}.3"
done
echo ""
echo "  Student route command (replace <HOST_IP> with this machine's LAN IP):"
echo "    sudo ip route add ${SUBNET_BASE}.<N>.0/24 via <HOST_IP>"
echo ""
echo "  NOTE: If students cannot reach containers, check whether Docker added a"
echo "  drop rule to the nft raw PREROUTING chain: "
echo "    sudo nft -a list chain ip raw PREROUTING"
echo "    sudo nft insert rule ip raw PREROUTING handle <N> ip saddr 10.7.7.0/24 ip daddr 10.7.0.0/16 accept"
echo "    where <N> is before the drop rule "
echo ""
echo "  Tear down:       docker compose down"
echo "  Reset one team:  docker compose restart team<NN>-sol team<NN>-tau team<NN>-eri"
echo "  Reset all teams: docker compose restart"
