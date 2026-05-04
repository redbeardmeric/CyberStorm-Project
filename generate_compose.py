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

SKIP_SUBNETS lists subnet octets to avoid. startup.sh patches this automatically
from the detected LAN octet so team subnets never collide with the physical network.
Teams whose natural octet is in SKIP_SUBNETS are remapped to the first free octet
above NUM_TEAMS.
"""

# Subnet octets to skip — patched by startup.sh from the detected LAN interface.
SKIP_SUBNETS = {7}

NUM_TEAMS = 15

# Change this if the default subnet conflicts with your physical LAN.
# Must be the first two octets of a private range not used on the LAN.
# Examples: "10.20", "10.100", "172.20"
SUBNET_BASE = "138.47"

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
    """Yield subnet octets, natural teams first then remapped teams at the end.

    Teams in SKIP_SUBNETS are remapped to the first free octet above num_teams
    and yielded last so that team_num == subnet_octet for as many teams as possible.
    """
    remap = num_teams + 1
    remapped = []
    for team in range(1, num_teams + 1):
        if team not in SKIP_SUBNETS:
            yield team
        else:
            while remap in SKIP_SUBNETS:
                remap += 1
            remapped.append(remap)
            remap += 1
    yield from remapped


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
