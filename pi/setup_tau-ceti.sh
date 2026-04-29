#!/bin/bash
# Setup script for tau-ceti (Pi 2) — FTP server
# Run as root: sudo bash setup_tau-ceti.sh
set -e

echo "[tau-ceti] Installing vsftpd..."
apt-get update -q
apt-get install -y vsftpd

echo "[tau-ceti] Creating user stratt..."
id stratt &>/dev/null || useradd -m -s /bin/bash stratt
echo 'stratt:petrova' | chpasswd

echo "[tau-ceti] Writing shadow file..."
cat > /home/stratt/shadow << 'EOF'
rocky:$1$hailmary$ahx9IaEq7304SRR3akXGK.:19000:0:99999:7:::
EOF
chown stratt:stratt /home/stratt/shadow
chmod 644 /home/stratt/shadow

echo "[tau-ceti] Configuring vsftpd..."
cat > /etc/vsftpd.conf << 'EOF'
listen=YES
local_enable=YES
write_enable=NO
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
idle_session_timeout=180
pasv_enable=YES
pasv_min_port=60000
pasv_max_port=60010
seccomp_sandbox=NO
EOF

mkdir -p /var/run/vsftpd/empty

systemctl enable vsftpd
systemctl restart vsftpd

echo "[tau-ceti] Setup complete."
