#!/bin/bash
# 64korppu — Ubuntu test rig -asennusskripti
#
# Ajetaan kerran veljen koneella Ubuntun asennuksen jälkeen.
# Skripti on idempotent — turvallista ajaa uudelleen.
#
# Käyttö:
#   sudo bash setup.sh [SSH_PUBLIC_KEY]
#
# Esimerkki:
#   sudo bash setup.sh "ssh-ed25519 AAAA... 64korppu-testrig"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SSH_PUBKEY="${1:-}"
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(eval echo "~$ACTUAL_USER")

echo "=== 64korppu Test Rig Setup ==="
echo "Käyttäjä: $ACTUAL_USER"
echo "Home:     $ACTUAL_HOME"
echo ""

# ── 1. Paketit ──────────────────────────────────────────────

echo -e "${YELLOW}[1/7]${NC} Asennetaan paketit..."
apt-get update -qq
apt-get install -y -qq openssh-server avrdude python3-pip python3-serial curl udev > /dev/null

# Varmista pip-asennus pyserialille (jos python3-serial ei riitä)
if ! python3 -c "import serial" 2>/dev/null; then
    pip3 install pyserial --break-system-packages 2>/dev/null || pip3 install pyserial
fi

echo -e "${GREEN}[OK]${NC} Paketit asennettu"

# ── 2. Tailscale ────────────────────────────────────────────

echo -e "${YELLOW}[2/7]${NC} Asennetaan Tailscale..."
if command -v tailscale &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Tailscale jo asennettu"
else
    curl -fsSL https://tailscale.com/install.sh | sh
    echo -e "${GREEN}[OK]${NC} Tailscale asennettu"
fi

# ── 3. Dialout-ryhmä ───────────────────────────────────────

echo -e "${YELLOW}[3/7]${NC} Serial-oikeudet..."
if id -nG "$ACTUAL_USER" | grep -qw dialout; then
    echo -e "${GREEN}[OK]${NC} $ACTUAL_USER on jo dialout-ryhmässä"
else
    usermod -aG dialout "$ACTUAL_USER"
    echo -e "${GREEN}[OK]${NC} $ACTUAL_USER lisätty dialout-ryhmään (vaatii uudelleenkirjautumisen)"
fi

# ── 4. Udev-säännöt ────────────────────────────────────────

echo -e "${YELLOW}[4/7]${NC} Udev-säännöt..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="$SCRIPT_DIR/99-arduino.rules"

if [ -f "$RULES_SRC" ]; then
    cp "$RULES_SRC" /etc/udev/rules.d/99-arduino.rules
else
    # Inline fallback jos ajetaan ilman muita tiedostoja
    cat > /etc/udev/rules.d/99-arduino.rules << 'RULES'
# CH340
SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", SYMLINK+="arduino", MODE="0666"
# FTDI
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="arduino", MODE="0666"
# ATmega16U2
SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0043", SYMLINK+="arduino", MODE="0666"
# Nano Every
SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0058", SYMLINK+="arduino", MODE="0666"
RULES
fi

udevadm control --reload-rules
udevadm trigger
echo -e "${GREEN}[OK]${NC} Udev-säännöt asennettu (/dev/arduino)"

# ── 5. Helper-skriptit ─────────────────────────────────────

echo -e "${YELLOW}[5/7]${NC} Kopioidaan skriptit..."
mkdir -p "$ACTUAL_HOME/tools" "$ACTUAL_HOME/firmware"

for script in flash.sh detect.sh health.sh; do
    src="$SCRIPT_DIR/$script"
    if [ -f "$src" ]; then
        cp "$src" "$ACTUAL_HOME/tools/$script"
        chmod +x "$ACTUAL_HOME/tools/$script"
    fi
done

# monitor.py erikseen
if [ -f "$SCRIPT_DIR/monitor.py" ]; then
    cp "$SCRIPT_DIR/monitor.py" "$ACTUAL_HOME/tools/monitor.py"
    chmod +x "$ACTUAL_HOME/tools/monitor.py"
fi

chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/tools" "$ACTUAL_HOME/firmware"
echo -e "${GREEN}[OK]${NC} Skriptit asennettu: $ACTUAL_HOME/tools/"

# ── 6. SSH-avain ────────────────────────────────────────────

echo -e "${YELLOW}[6/7]${NC} SSH-konfiguraatio..."
mkdir -p "$ACTUAL_HOME/.ssh"
chmod 700 "$ACTUAL_HOME/.ssh"

AUTH_KEYS="$ACTUAL_HOME/.ssh/authorized_keys"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
chown "$ACTUAL_USER:$ACTUAL_USER" "$AUTH_KEYS"

if [ -n "$SSH_PUBKEY" ]; then
    if ! grep -qF "$SSH_PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
        echo "$SSH_PUBKEY" >> "$AUTH_KEYS"
        echo -e "${GREEN}[OK]${NC} SSH-avain lisätty"
    else
        echo -e "${GREEN}[OK]${NC} SSH-avain oli jo lisätty"
    fi
else
    echo -e "${YELLOW}[INFO]${NC} SSH-avainta ei annettu parametrina"
    echo "  Lisää myöhemmin: echo 'ssh-ed25519 AAAA...' >> $AUTH_KEYS"
fi

chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.ssh"

# Varmista SSH-palvelu
systemctl enable ssh
systemctl start ssh

echo -e "${GREEN}[OK]${NC} SSH-palvelu käynnissä"

# ── 7. Palomuuri (UFW) ─────────────────────────────────────

echo -e "${YELLOW}[7/7]${NC} Palomuuri..."
if command -v ufw &>/dev/null; then
    # Salli Tailscale-liikenne
    ufw allow in on tailscale0 > /dev/null 2>&1 || true
    # Salli SSH myös suoraan (varmuudeksi ennen Tailscalen konfigurointia)
    ufw allow ssh > /dev/null 2>&1 || true
    ufw --force enable > /dev/null 2>&1
    echo -e "${GREEN}[OK]${NC} UFW käytössä (Tailscale + SSH sallittu)"
else
    echo -e "${YELLOW}[INFO]${NC} UFW ei asennettu, ohitetaan"
fi

# ── Valmis ──────────────────────────────────────────────────

echo ""
echo "======================================="
echo -e "${GREEN}  Setup valmis!${NC}"
echo "======================================="
echo ""
echo "Seuraavat askeleet:"
echo ""
echo "  1. Käynnistä Tailscale:"
echo "     sudo tailscale up"
echo ""
echo "  2. Tarkista Tailscale IP:"
echo "     tailscale ip -4"
echo ""
echo "  3. Jaa nämä tiedot:"
echo "     - Tailscale IP"
echo "     - Käyttäjätunnus: $ACTUAL_USER"
echo ""
if [ -z "$SSH_PUBKEY" ]; then
    echo "  4. Lisää SSH-avain:"
    echo "     echo 'ssh-ed25519 AAAA...' >> $AUTH_KEYS"
    echo ""
fi
echo "  Testaa: ~/tools/health.sh"
echo ""

# Varoita uudelleenkirjautumisesta jos dialout lisättiin
if ! id -nG "$ACTUAL_USER" | grep -qw dialout; then
    echo -e "${YELLOW}HUOM:${NC} Kirjaudu ulos ja takaisin dialout-ryhmän aktivoimiseksi!"
fi
