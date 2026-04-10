#!/bin/bash
# Reset script for sol (Pi 1) — restores challenge files between heats
# Run as root: sudo bash reset_sol.sh
set -e

echo "[sol] Resetting mail file..."
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

echo "[sol] Kicking active SSH sessions for ryland..."
pkill -u ryland sshd 2>/dev/null || true

echo "[sol] Reset complete."
