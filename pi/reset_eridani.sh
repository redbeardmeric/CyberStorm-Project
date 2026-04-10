#!/bin/bash
# Reset script for eridani (Pi 3) — restores challenge files between heats
# Run as root: sudo bash reset_eridani.sh
set -e

echo "[eridani] Restoring challenge files..."
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

echo "[eridani] Kicking active SSH sessions for rocky..."
pkill -u rocky sshd 2>/dev/null || true

echo "[eridani] Reset complete."
