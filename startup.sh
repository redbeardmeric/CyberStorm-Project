#!/usr/bin/env bash
# startup.sh — bring up the full CyberStorm challenge environment
# Usage: ./startup.sh <num_teams>
#
# Run ./install.sh first to build or load Docker images.
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
# detect LAN interface, then derive SUBNET_BASE from the host's IP
# ---------------------------------------------------------------------------
LAN_IFACE=$(ip route show default \
    | awk 'NR==1 { for(i=1;i<=NF;i++) if($i=="dev") { print $(i+1); exit } }')
[[ -z "$LAN_IFACE" ]] && die "Could not detect LAN interface from default route"
HOST_IP=$(ip -4 addr show "$LAN_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
[[ -z "$HOST_IP" ]] && die "Could not detect IP address for interface $LAN_IFACE"

# First two octets of the host IP become the subnet base (e.g. 10.7.7.100 → "10.7").
# The third octet is the LAN's own /24 — skip it so team subnets don't collide with it.
SUBNET_BASE=$(echo "$HOST_IP" | cut -d. -f1,2)
LAN_OCTET=$(echo "$HOST_IP"   | cut -d. -f3)
SUBNET_CIDR="${SUBNET_BASE}.0.0/16"

# ===========================================================================
# Step 1 — update generate_compose.py
# ===========================================================================
info "Step 1/6 — Updating generate_compose.py (teams=$NUM_TEAMS, subnet=$SUBNET_BASE, skip octet $LAN_OCTET)"
sed -i "s/^NUM_TEAMS = .*/NUM_TEAMS = $NUM_TEAMS/" generate_compose.py
sed -i "s/^SUBNET_BASE = .*/SUBNET_BASE = \"$SUBNET_BASE\"/" generate_compose.py
sed -i "s/^SKIP_SUBNETS = .*/SKIP_SUBNETS = {$LAN_OCTET}/" generate_compose.py
ok "generate_compose.py updated"

# ===========================================================================
# Step 2 — verify Docker images are present
# ===========================================================================
IMAGES=(ctf-sol ctf-tau ctf-eri)
IMAGES_MISSING=()
for img in "${IMAGES[@]}"; do
    docker image inspect "$img" &>/dev/null || IMAGES_MISSING+=("$img")
done

if [[ ${#IMAGES_MISSING[@]} -gt 0 ]]; then
    die "Step 2/6 — Missing images: ${IMAGES_MISSING[*]}. Run ./install.sh first."
fi
ok "Step 2/6 — Images present: ${IMAGES[*]}"

# ===========================================================================
# Step 3 — generate docker-compose.yml
# ===========================================================================
info "Step 3/6 — Generating docker-compose.yml for $NUM_TEAMS team(s)"
python3 generate_compose.py
ok "docker-compose.yml written"

# ===========================================================================
# Step 4 — start containers
# ===========================================================================
EXPECTED=$(( NUM_TEAMS * 3 ))
info "Step 4/6 — Starting $EXPECTED containers..."
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
# Step 4b — nft raw PREROUTING accept (Docker drop-rule workaround)
# ===========================================================================
# Docker (nftables backend) inserts per-container drop rules into ip raw PREROUTING:
#   iifname != "br-teamXX" ip daddr <container-ip> drop
# These fire before iptables and silently discard routed student traffic arriving
# on the LAN interface. Insert a broad accept for the whole team subnet FIRST so
# it wins before those drops.
# Remove any stale accept rules we may have added in a previous run
while sudo nft list chain ip raw PREROUTING 2>/dev/null \
      | grep -q "iifname \"$LAN_IFACE\".*ip daddr $SUBNET_CIDR accept"; do
    HANDLE=$(sudo nft -a list chain ip raw PREROUTING 2>/dev/null \
              | grep -F "iifname \"$LAN_IFACE\"" | grep -F "ip daddr $SUBNET_CIDR accept" \
              | grep -o 'handle [0-9]*' | awk '{print $2}' | head -1)
    [[ -n "$HANDLE" ]] && sudo nft delete rule ip raw PREROUTING handle "$HANDLE" || break
done
sudo nft insert rule ip raw PREROUTING iifname "$LAN_IFACE" ip daddr "$SUBNET_CIDR" accept
ok "nft raw PREROUTING: accept $LAN_IFACE -> $SUBNET_CIDR inserted before Docker drop rules"

# ===========================================================================
# Step 5 — enable IP forwarding
# ===========================================================================
info "Step 5/6 — Enabling IP forwarding"
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
ok "net.ipv4.ip_forward = 1"

# ===========================================================================
# Step 6 — iptables rules
# ===========================================================================
info "Step 6/6 — Adding iptables rules (iface: $LAN_IFACE, cidr: $SUBNET_CIDR)"
# Remove any copies left from previous runs before re-inserting (idempotent).
while sudo iptables -D DOCKER-USER -i "$LAN_IFACE" -o br-team+ -d "$SUBNET_CIDR" -j ACCEPT 2>/dev/null; do :; done
while sudo iptables -D DOCKER-USER -i br-team+ -o "$LAN_IFACE" -d "$SUBNET_CIDR" -j ACCEPT 2>/dev/null; do :; done
while sudo iptables -D DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do :; done
while sudo iptables -t nat -D POSTROUTING -s "$SUBNET_CIDR" -d "$SUBNET_CIDR" ! -o br-team+ -j ACCEPT 2>/dev/null; do :; done
sudo iptables -I DOCKER-USER -i "$LAN_IFACE" -o br-team+ -d "$SUBNET_CIDR" -j ACCEPT
sudo iptables -I DOCKER-USER -i br-team+ -o "$LAN_IFACE" -d "$SUBNET_CIDR" -j ACCEPT
sudo iptables -I DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -t nat -I POSTROUTING -s "$SUBNET_CIDR" -d "$SUBNET_CIDR" ! -o br-team+ -j ACCEPT
ok "iptables rules added"

# ===========================================================================
# Step 7 — start container monitor
# ===========================================================================
info "Starting container monitor"
EXISTING_PID=$(pgrep -f "python3 monitor.py" | head -1 || true)
if [[ -n "$EXISTING_PID" ]]; then
    info "Monitor already running (PID $EXISTING_PID) — restarting"
    kill "$EXISTING_PID" 2>/dev/null; sleep 1
fi
python3 monitor.py &
MONITOR_PID=$!
echo "$MONITOR_PID" > "$SCRIPT_DIR/monitor.pid"
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
_remap=$((NUM_TEAMS + 1))
for n in $(seq 1 "$NUM_TEAMS"); do
    if [[ "$n" -eq "$LAN_OCTET" ]]; then
        while [[ "$_remap" -eq "$LAN_OCTET" ]]; do (( _remap++ )); done
        _sn="$_remap"
        (( _remap++ ))
    else
        _sn="$n"
    fi
    printf "    Team %02d:  sol %-14s  tau-ceti %-14s  eridani %s\n" \
        "$n" \
        "${SUBNET_BASE}.${_sn}.1" \
        "${SUBNET_BASE}.${_sn}.2" \
        "${SUBNET_BASE}.${_sn}.3"
done
echo ""
echo "  Student route commands:"
_remap2=$((NUM_TEAMS + 1))
for n in $(seq 1 "$NUM_TEAMS"); do
    if [[ "$n" -eq "$LAN_OCTET" ]]; then
        while [[ "$_remap2" -eq "$LAN_OCTET" ]]; do (( _remap2++ )); done
        _sn2="$_remap2"
        (( _remap2++ ))
    else
        _sn2="$n"
    fi
    printf "    Team %02d:  sudo ip route add %s.%s.0/24 via %s\n" \
        "$n" "$SUBNET_BASE" "$_sn2" "$HOST_IP"
done
echo ""
echo "  Stop monitor:    kill \$(cat monitor.pid)"
echo "  Tear down:       docker compose down"
echo "  Reset one team:  docker compose restart team<NN>-sol team<NN>-tau team<NN>-eri"
echo "  Reset all teams: docker compose restart"
