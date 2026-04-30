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
"""

NUM_TEAMS = 2

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


def main():
    lines = ["services:\n"]

    for n in range(1, NUM_TEAMS + 1):
        lines.append(SERVICE_BLOCK.format(n=n, base=SUBNET_BASE))

    lines.append("networks:\n")
    for n in range(1, NUM_TEAMS + 1):
        lines.append(NETWORK_BLOCK.format(n=n, base=SUBNET_BASE))

    output = "".join(lines)

    with open("docker-compose.yml", "w") as f:
        f.write(output)

    print(f"Generated docker-compose.yml")
    print(f"  {NUM_TEAMS} teams, {NUM_TEAMS * 3} containers, {NUM_TEAMS} networks")
    print(f"  Networks: {SUBNET_BASE}.1.0/24 through {SUBNET_BASE}.{NUM_TEAMS}.0/24")


if __name__ == "__main__":
    main()
