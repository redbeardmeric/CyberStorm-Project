#!/bin/bash
# Setup script for sol (Pi 1) — SSH server
# Run as root: sudo bash setup_sol.sh
set -e

echo "[sol] Installing OpenSSH..."
apt-get update -q
apt-get install -y openssh-server

echo "[sol] Creating user ryland..."
id ryland &>/dev/null || useradd -m -s /bin/bash ryland
echo 'ryland:astrophage' | chpasswd

echo "[sol] Writing mail file..."
mkdir -p /var/mail
cat > /var/mail/ryland << 'EOF'
From: ryland.grace@astrophage-project.net
To: stratt@astrophage-project.net
Date: Mon, 14 Nov 2022 09:12:44 +0000
Subject: FTP access to tau-ceti relay

Stratt,

The spectrometer logs from the Tau Ceti observation window are ready.
I pushed them to the relay server (tau-ceti) under your account.

FTP credentials (don't share these — I'm serious):
  user: stratt
  pass: petrova

The shadow archive is in your home directory. Cross-ref against the
Eridani dataset and let me know if you see the same Astrophage bloom
signature we detected at 40 Eridani last cycle.

– Ryland
EOF
chown ryland:ryland /var/mail/ryland
chmod 640 /var/mail/ryland

echo "[sol] Configuring sshd..."
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
PasswordAuthentication yes
PermitRootLogin no
ClientAliveInterval 30
ClientAliveCountMax 6
UsePAM yes
EOF

systemctl enable ssh
systemctl restart ssh

echo "[sol] Setup complete."
