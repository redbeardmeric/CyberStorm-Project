#!/usr/bin/env bash
# install.sh — build CyberStorm Docker images and save to images.tar.gz
# Usage: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }
die()  { echo "[!] $*" >&2; exit 1; }

cd "$SCRIPT_DIR"
[[ -d docker/sol && -d docker/tau && -d docker/eri ]] \
    || die "Must be run from the project root (docker/ subdirectory not found)"

IMAGES=(ctf-sol ctf-tau ctf-eri)

# Remove any existing images before reinstalling
for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
        info "Removing existing image: $img"
        docker image rm -f "$img"
    fi
done

info "Building Docker images (this takes 1–3 min)..."
docker build -t ctf-sol ./docker/sol
docker build -t ctf-tau ./docker/tau
docker build -t ctf-eri ./docker/eri
ok "Images built: ctf-sol  ctf-tau  ctf-eri"
info "Saving images to images.tar.gz..."
docker save "${IMAGES[@]}" | gzip > "$SCRIPT_DIR/images.tar.gz"
ok "Saved to images.tar.gz ($(du -sh "$SCRIPT_DIR/images.tar.gz" | cut -f1))"

echo ""
echo "Installation complete. Run ./startup.sh <num_teams> to start the environment."
