#!/usr/bin/env python3
"""Generate docker-compose.yml for 15 isolated CTF team networks.

Each team gets subnet 10.7.{n}.0/24 with:
  sol      10.7.{n}.1  (SSH :22)
  tau-ceti 10.7.{n}.2  (FTP :21)
  eridani  10.7.{n}.3  (SSH :22, MaxAuthTries 3)

Students reach containers directly via a static route on their machine:
  sudo ip route add 10.7.<N>.0/24 via <host-ip>
"""

NUM_TEAMS = 15

SERVICE_BLOCK = """\
  team{n:02d}-sol:
    image: ctf-sol
    hostname: sol
    networks:
      team{n:02d}-net:
        ipv4_address: 10.7.{n}.1

  team{n:02d}-tau:
    image: ctf-tau
    hostname: tau-ceti
    networks:
      team{n:02d}-net:
        ipv4_address: 10.7.{n}.2

  team{n:02d}-eri:
    image: ctf-eri
    hostname: eridani
    networks:
      team{n:02d}-net:
        ipv4_address: 10.7.{n}.3

"""

NETWORK_BLOCK = """\
  team{n:02d}-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.7.{n}.0/24
          gateway: 10.7.{n}.254
"""


def main():
    lines = ["services:\n"]

    for n in range(1, NUM_TEAMS + 1):
        lines.append(SERVICE_BLOCK.format(n=n))

    lines.append("networks:\n")
    for n in range(1, NUM_TEAMS + 1):
        lines.append(NETWORK_BLOCK.format(n=n))

    output = "".join(lines)

    with open("docker-compose.yml", "w") as f:
        f.write(output)

    print(f"Generated docker-compose.yml")
    print(f"  {NUM_TEAMS} teams, {NUM_TEAMS * 3} containers, {NUM_TEAMS} networks")
    print(f"  Networks: 10.7.1.0/24 through 10.7.{NUM_TEAMS}.0/24")


if __name__ == "__main__":
    main()
