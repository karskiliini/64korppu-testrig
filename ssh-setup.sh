#!/bin/bash
# 64korppu — SSH-konfiguraatio Macille
#
# Generoi SSH-avainparin ja lisää testrig-entryn SSH configiin.
# Ajetaan kerran omalla koneella.
#
# Käyttö: bash ssh-setup.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/id_testrig"
CONFIG_FILE="$SSH_DIR/config"

echo "=== 64korppu SSH Setup ==="
echo ""

# ── 1. Avainpari ────────────────────────────────────────────

if [ -f "$KEY_FILE" ]; then
    echo -e "${GREEN}[OK]${NC} Avain löytyy: $KEY_FILE"
else
    echo -e "${YELLOW}[1/3]${NC} Generoidaan SSH-avainpari..."
    ssh-keygen -t ed25519 -f "$KEY_FILE" -C "64korppu-testrig" -N ""
    echo -e "${GREEN}[OK]${NC} Avain generoitu"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Julkinen avain (lähetä tämä veljellesi):"
echo "═══════════════════════════════════════════════════"
echo ""
cat "${KEY_FILE}.pub"
echo ""
echo "═══════════════════════════════════════════════════"
echo ""

# ── 2. Tailscale IP ja käyttäjätunnus ──────────────────────

echo -e "${YELLOW}[2/3]${NC} Veljen koneen tiedot"
read -rp "Tailscale IP (esim. 100.64.1.2): " TAILSCALE_IP
read -rp "Käyttäjätunnus (esim. veli): " REMOTE_USER

if [ -z "$TAILSCALE_IP" ] || [ -z "$REMOTE_USER" ]; then
    echo "Virhe: molemmat tarvitaan"
    exit 1
fi

# ── 3. SSH config ───────────────────────────────────────────

echo -e "${YELLOW}[3/3]${NC} SSH config..."

# Varmista .ssh-hakemisto
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Tarkista onko entry jo olemassa
if grep -q "^Host testrig" "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} 'Host testrig' löytyy jo configista, päivitetään..."
    # Poista vanha entry (Host testrig + seuraavat sisennnetyt rivit)
    sed -i.bak '/^Host testrig$/,/^Host \|^$/{ /^Host testrig$/d; /^[[:space:]]/d; }' "$CONFIG_FILE"
    # Siivoa tyhjät rivit
    sed -i.bak '/^$/N;/^\n$/d' "$CONFIG_FILE"
fi

# Lisää uusi entry
cat >> "$CONFIG_FILE" << EOF

Host testrig
  HostName $TAILSCALE_IP
  User $REMOTE_USER
  IdentityFile $KEY_FILE
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ConnectTimeout 10
EOF

# Siivoa backup
rm -f "${CONFIG_FILE}.bak"

echo -e "${GREEN}[OK]${NC} SSH config päivitetty"

echo ""
echo "======================================="
echo -e "${GREEN}  Setup valmis!${NC}"
echo "======================================="
echo ""
echo "Testaa yhteys:"
echo "  ssh testrig 'echo OK'"
echo ""
echo "Testaa test rig:"
echo "  ssh testrig '~/tools/health.sh'"
echo ""
echo "Tunnista Arduino:"
echo "  ssh testrig '~/tools/detect.sh'"
echo ""
