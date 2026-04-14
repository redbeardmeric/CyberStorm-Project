# Docker Container Ping Troubleshooting — Summary

**Environment:**
- Windows Device: `10.7.7.105`
- Linux Host (Raspberry Pi): `10.7.7.100`
- Docker Bridge Interface: `10.7.1.254`
- Docker Containers: `10.7.1.1`, `10.7.1.2`, `10.7.1.3`

**Symptom:** Could ping the Pi (`10.7.7.100`) and the Docker bridge interface (`10.7.1.254`) from Windows, but could not ping any containers (`10.7.1.1-3`).

---

## Steps Investigated (All Ruled Out)

### 1. Windows Static Route
Verified that Windows had a route sending `10.7.1.0/24` traffic via the Linux host:
```cmd
route add 10.7.1.0 mask 255.255.255.0 10.7.7.100 -p
```
**Result:** Route existed and was correct. Not the problem.

---

### 2. IP Forwarding on the Pi
```bash
cat /proc/sys/net/ipv4/ip_forward
```
**Result:** Was already set to `1`. Not the problem.

---

### 3. iptables FORWARD Rules
```bash
sudo iptables -L FORWARD -v -n
sudo iptables -L DOCKER-USER -v -n
```
**Result:** FORWARD policy was `ACCEPT` with no rules. DOCKER-USER had the two rules added but irrelevant. Not the problem.

---

### 4. UFW / Firewalld
```bash
sudo ufw status
sudo firewall-cmd --state
```
**Result:** Not active. Not the problem.

---

### 5. Reverse Path Filter (rp_filter)
```bash
cat /proc/sys/net/ipv4/conf/all/rp_filter
```
**Result:** Already `0` (disabled). Not the problem.

---

### 6. nftables Ruleset
```bash
sudo nft flush ruleset
```
**Result:** Flushed, then Docker rules restored after `sudo systemctl restart docker`. Still not working.

---

### 7. br_netfilter Module
```bash
lsmod | grep br_netfilter
sudo modprobe br_netfilter
```
**Result:** Loaded, but did not resolve the issue.

---

### 8. tcpdump Analysis
```bash
sudo tcpdump -i eth0 icmp
sudo tcpdump -i br-2efde1515264 icmp
```
**Result:** Packets visible on `eth0` but **not** on the bridge interface. Confirmed packets were being dropped somewhere between the two interfaces.

---

### 9. Docker Network / Container Health
```bash
ping -c3 10.7.1.1   # from the Pi itself
```
**Result:** Pi could ping its own containers successfully. Docker networking itself was healthy.

---

## Root Cause — Identified via nftables TRACE

Added an nftables trace rule to follow packets in real time:
```bash
sudo nft add table ip trace_table
sudo nft add chain ip trace_table trace_chain '{ type filter hook prerouting priority -310; }'
sudo nft add rule ip trace_table trace_chain ip saddr 10.7.7.105 meta nftrace set 1
sudo nft monitor trace
```

The trace output revealed the exact drop rule:
```
ip raw PREROUTING rule iifname != "br-2efde1515264" ip daddr 10.7.1.1 counter packets 692 bytes 58128 drop (verdict drop)
```

**Docker itself added an nftables rule in the `raw` PREROUTING chain that drops any packet destined for a container IP (`10.7.1.x`) if it did not arrive on the Docker bridge interface.** Since packets from Windows arrive on `eth0`, they were dropped every time before ever reaching the bridge.

This rule is invisible to `iptables` commands because it lives in the **nftables native backend**, while `iptables` was checking the legacy backend.

---

## The Fix

Find the handle number of Docker's drop rule:
```bash
sudo nft -a list chain ip raw PREROUTING
```

Look for the line:
```
iifname != "br-2efde1515264" ip daddr 10.7.1.x ... drop   # handle <N>
```

Insert an accept rule **before** Docker's drop rule using that handle number:
```bash
sudo nft insert rule ip raw PREROUTING position <N> ip saddr 10.7.7.0/24 ip daddr 10.7.1.0/24 accept
```

Verify the accept rule appears before the drop rule:
```bash
sudo nft list chain ip raw PREROUTING
```

### Make It Persistent
```bash
sudo nft list ruleset > /etc/nftables.conf
sudo systemctl enable nftables
```

> **Important:** Docker rewrites its nftables rules on restart. After any `docker restart` or system reboot you must re-insert this rule, OR add it to a startup script that runs after Docker starts.

---

## Key Takeaways

- **`iptables` commands are blind to nftables rules.** On modern Linux (especially Raspberry Pi OS Bullseye+), Docker uses nftables natively. Always check `sudo nft list ruleset` alongside `iptables`.
- **Docker's raw PREROUTING drop rule** is intentional — it prevents external traffic from directly reaching container IPs. You must explicitly allow your trusted subnet before that rule runs.
- **`nft monitor trace` is the most powerful diagnostic tool** for this class of problem. It shows every chain and rule a packet touches and exactly where it is dropped.
- The fact that `10.7.1.254` (the bridge interface IP) was reachable but `10.7.1.1-3` (container IPs) were not is a reliable indicator of this exact Docker nftables drop rule pattern.



# Add an accept rule at higher priority than Docker's drop (-310 to beat its -300)
sudo nft add table ip docker_forward
sudo nft add chain ip docker_forward prerouting '{ type filter hook prerouting priority -350; }'
sudo nft add rule ip docker_forward prerouting ip saddr 10.7.7.0/24 ip daddr 10.7.1.0/24 accept

# First find the handle number of Docker's drop rule
sudo nft -a list chain ip raw PREROUTING