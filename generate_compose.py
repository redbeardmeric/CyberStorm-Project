#!/usr/bin/env python3
"""Generate docker-compose.yml for isolated CTF team networks.

Each team gets subnet {BASE}.{n}.0/24 with:
  sol      {BASE}.{n}.1  (SSH :22)
  tau-ceti {BASE}.{n}.2  (FTP :21)
  eridani  {BASE}.{n}.3  (SSH :22, MaxAuthTries 3)

Students reach containers via a static route on their machine:
  sudo ip route add {BASE}.<N>.0/24 via <host-ip>

IMPORTANT: SUBNET_BASE must not overlap with the physical LAN.
  e.g. if the LAN uses 10.7.x.x, do not use "10.7" here.
  The default "10.7" assumes the classroom LAN uses a different range (e.g. 192.168.x.x).
  Change SUBNET_BASE if there is any overlap.

NOTE: Team 7 is assigned TEAM7_SUBNET (default 16) instead of subnet 7, because
10.7.7.0/24 conflicts with the physical router and makes containers unreachable.
All other teams use their team number as the subnet octet directly.
"""

# Team 7's subnet octet. All other teams use their team number as-is.
TEAM7_SUBNET = 16

NUM_TEAMS = 15

# Change this if the default subnet conflicts with your physical LAN.
# Must be the first two octets of a private range not used on the LAN.
# Examples: "10.20", "10.100", "172.20"
SUBNET_BASE = "10.7"

SERVICE_BLOCK = """\
  team{n:02d}-sol:
    image: ctf-sol
    hostname: sol
    networks:
      team{n:02d}-net:
        ipv4_address: {base}.{n}.1

  team{n:02d}-tau:
    image: ctf-tau
    hostname: tau-ceti
    networks:
      team{n:02d}-net:
        ipv4_address: {base}.{n}.2

  team{n:02d}-eri:
    image: ctf-eri
    hostname: eridani
    environment:
      TEAM_NUM: "{n:02d}"
    networks:
      team{n:02d}-net:
        ipv4_address: {base}.{n}.3

"""

NETWORK_BLOCK = """\
  team{n:02d}-net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-team{n:02d}
      com.docker.network.bridge.icc: "true"
    ipam:
      config:
        - subnet: {base}.{n}.0/24
          gateway: {base}.{n}.254
"""


def subnet_numbers(num_teams):
    """Yield subnet octets for each team. Team 7 uses TEAM7_SUBNET."""
    for team in range(1, num_teams + 1):
        yield TEAM7_SUBNET if team == 7 else team


def main():
    subnets = list(subnet_numbers(NUM_TEAMS))

    lines = ["services:\n"]
    for n in subnets:
        lines.append(SERVICE_BLOCK.format(n=n, base=SUBNET_BASE))

    lines.append("networks:\n")
    for n in subnets:
        lines.append(NETWORK_BLOCK.format(n=n, base=SUBNET_BASE))

    output = "".join(lines)

    with open("docker-compose.yml", "w") as f:
        f.write(output)

    print(f"Generated docker-compose.yml")
    print(f"  {NUM_TEAMS} teams, {NUM_TEAMS * 3} containers, {NUM_TEAMS} networks")
    print(f"  Subnets: {', '.join(f'{SUBNET_BASE}.{n}.0/24' for n in subnets)}")


if __name__ == "__main__":
    main()
