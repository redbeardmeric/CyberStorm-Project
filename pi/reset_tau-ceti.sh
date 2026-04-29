#!/bin/bash
# Reset script for tau-ceti (Pi 2) — restores challenge files between heats
# Run as root: sudo bash reset_tau-ceti.sh
set -e

echo "[tau-ceti] Restoring shadow file..."
cat > /home/stratt/shadow << 'EOF'
rocky:$1$hailmary$ahx9IaEq7304SRR3akXGK.:19000:0:99999:7:::
EOF
chown stratt:stratt /home/stratt/shadow
chmod 644 /home/stratt/shadow

echo "[tau-ceti] Kicking active FTP sessions for stratt..."
pkill -u stratt vsftpd 2>/dev/null || true

echo "[tau-ceti] Reset complete."
