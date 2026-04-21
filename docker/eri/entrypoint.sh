#!/bin/bash
set -e

TEAM=${TEAM_NUM:-00}

cat > /home/rocky/.astrophage_data.txt <<EOF
[CLASSIFIED — HAIL MARY PROJECT — RESTRICTED DISTRIBUTION]

ASTROPHAGE CONFIRMED: 40 ERIDANI SYSTEM
Observation cycle 7, solar flux anomaly +3.1% above baseline.
Spectrometer readings consistent with Astrophage microorganism absorption
signature at 25.984 THz. Bloom density estimated 2.4x Tau Ceti reference levels.

This system is further along than we thought. Rocky's numbers don't lie.

>> FLAG{astrophage_confirmed_tau_ceti_e_t${TEAM}} <<
EOF

chown rocky:rocky /home/rocky/.astrophage_data.txt
chmod 640 /home/rocky/.astrophage_data.txt

exec /usr/sbin/sshd -D
