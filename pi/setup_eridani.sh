#!/bin/bash
# Setup script for eridani (Pi 3) — SSH server (rate-limited)
# Run as root: sudo bash setup_eridani.sh
set -e

echo "[eridani] Installing OpenSSH..."
apt-get update -q
apt-get install -y openssh-server

echo "[eridani] Creating user rocky..."
id rocky &>/dev/null || useradd -m -s /bin/bash rocky
echo 'rocky:bluemoon' | chpasswd

echo "[eridani] Writing challenge files..."
cat > /home/rocky/astrophage_data.txt << 'EOF'
Nice try. Look closer.
EOF

cat > /home/rocky/.astrophage_data.txt << 'EOF'
[CLASSIFIED — HAIL MARY PROJECT — RESTRICTED DISTRIBUTION]

ASTROPHAGE CONFIRMED: 40 ERIDANI SYSTEM
Observation cycle 7, solar flux anomaly +3.1% above baseline.
Spectrometer readings consistent with Astrophage microorganism absorption
signature at 25.984 THz. Bloom density estimated 2.4x Tau Ceti reference levels.

This system is further along than we thought. Rocky's numbers don't lie.

>> FLAG{astrophage_confirmed_tau_ceti_e} <<
EOF

chown rocky:rocky /home/rocky/astrophage_data.txt /home/rocky/.astrophage_data.txt
chmod 640 /home/rocky/astrophage_data.txt /home/rocky/.astrophage_data.txt

echo "[eridani] Configuring sshd..."
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
PasswordAuthentication yes
PermitRootLogin no
MaxAuthTries 3
ClientAliveInterval 30
ClientAliveCountMax 6
UsePAM yes
EOF

systemctl enable ssh
systemctl restart ssh

echo "[eridani] Setup complete."
