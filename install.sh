#!/usr/bin/env bash
# Install this fixed htb-operator so the `htb-operator` command uses the fixes
# (VPN --tcp support, no-hang VPN start, correct machine IP).
#
# Usage:  ./install.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pipx >/dev/null 2>&1; then
    echo "pipx is not installed. Install it first, e.g.:  sudo apt install pipx" >&2
    exit 1
fi

echo "[*] Installing htb-operator (fixed) from: $DIR"
pipx install --force "$DIR"

echo
echo "[+] Done. Try:"
echo "    htb-operator machine start --id <ID> --update-hosts-file --start-vpn --tcp"
