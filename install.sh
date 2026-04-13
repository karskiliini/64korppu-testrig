#!/bin/bash
# 64korppu — Test rig one-liner installer
#
# Käyttö:
#   curl -fsSL https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/install.sh | bash
#
# Tai:
#   wget -qO- https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/install.sh | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   64korppu Remote Test Rig Installer   ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
echo ""

# Tarkista root-oikeudet
if [ "$(id -u)" -ne 0 ]; then
    echo "Tarvitaan root-oikeudet. Ajetaan uudelleen sudolla..."
    exec sudo bash "$0" "$@"
fi

ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(eval echo "~$ACTUAL_USER")
REPO_URL="https://github.com/karskiliini/64korppu-testrig.git"
INSTALL_DIR="$ACTUAL_HOME/64korppu-testrig"

# ── 1. Git ──────────────────────────────────────────────────

echo -e "${YELLOW}[1/9]${NC} Asennetaan perustyökalut..."
apt-get update -qq
apt-get install -y -qq git curl > /dev/null
echo -e "${GREEN}[OK]${NC} git + curl"

# ── 2. Kloonaa repo ────────────────────────────────────────

echo -e "${YELLOW}[2/9]${NC} Ladataan testrig-skriptit..."
if [ -d "$INSTALL_DIR/.git" ]; then
    cd "$INSTALL_DIR"
    sudo -u "$ACTUAL_USER" git pull -q
    echo -e "${GREEN}[OK]${NC} Päivitetty: $INSTALL_DIR"
else
    rm -rf "$INSTALL_DIR"
    sudo -u "$ACTUAL_USER" git clone -q "$REPO_URL" "$INSTALL_DIR"
    echo -e "${GREEN}[OK]${NC} Kloonattu: $INSTALL_DIR"
fi

# ── 3. Paketit ──────────────────────────────────────────────

echo -e "${YELLOW}[3/9]${NC} Asennetaan paketit..."
apt-get install -y -qq openssh-server avrdude python3-pip python3-serial udev > /dev/null

if ! python3 -c "import serial" 2>/dev/null; then
    pip3 install pyserial --break-system-packages 2>/dev/null || pip3 install pyserial
fi
echo -e "${GREEN}[OK]${NC} avrdude, pyserial, ssh"

# ── 4. Tailscale ────────────────────────────────────────────

echo -e "${YELLOW}[4/9]${NC} Asennetaan Tailscale..."
if command -v tailscale &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Tailscale jo asennettu"
else
    curl -fsSL https://tailscale.com/install.sh | sh
    echo -e "${GREEN}[OK]${NC} Tailscale asennettu"
fi

# ── 5. Dialout-ryhmä ───────────────────────────────────────

echo -e "${YELLOW}[5/9]${NC} Serial-oikeudet..."
if id -nG "$ACTUAL_USER" | grep -qw dialout; then
    echo -e "${GREEN}[OK]${NC} $ACTUAL_USER jo dialout-ryhmässä"
else
    usermod -aG dialout "$ACTUAL_USER"
    echo -e "${GREEN}[OK]${NC} $ACTUAL_USER lisätty dialout-ryhmään"
fi

# ── 6. Udev-säännöt ────────────────────────────────────────

echo -e "${YELLOW}[6/9]${NC} Arduino udev-säännöt..."
cp "$INSTALL_DIR/99-arduino.rules" /etc/udev/rules.d/99-arduino.rules
udevadm control --reload-rules
udevadm trigger
echo -e "${GREEN}[OK]${NC} /dev/arduino symlink konfiguroitu"

# ── 7. Skriptit + hakemistot ──────────────────────────────

echo -e "${YELLOW}[7/9]${NC} Asennetaan työkalut..."
mkdir -p "$ACTUAL_HOME/tools" "$ACTUAL_HOME/firmware"

for script in flash.sh detect.sh health.sh; do
    cp "$INSTALL_DIR/$script" "$ACTUAL_HOME/tools/$script"
    chmod +x "$ACTUAL_HOME/tools/$script"
done
cp "$INSTALL_DIR/monitor.py" "$ACTUAL_HOME/tools/monitor.py"
chmod +x "$ACTUAL_HOME/tools/monitor.py"

chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/tools" "$ACTUAL_HOME/firmware"
echo -e "${GREEN}[OK]${NC} ~/tools/ ja ~/firmware/ valmiit"

# ── 8. SSH ──────────────────────────────────────────────────

echo -e "${YELLOW}[8/9]${NC} SSH-palvelin..."
mkdir -p "$ACTUAL_HOME/.ssh"
chmod 700 "$ACTUAL_HOME/.ssh"
touch "$ACTUAL_HOME/.ssh/authorized_keys"
chmod 600 "$ACTUAL_HOME/.ssh/authorized_keys"
chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.ssh"

systemctl enable ssh
systemctl start ssh

# Palomuuri
if command -v ufw &>/dev/null; then
    ufw allow in on tailscale0 > /dev/null 2>&1 || true
    ufw allow ssh > /dev/null 2>&1 || true
    ufw --force enable > /dev/null 2>&1
fi
echo -e "${GREEN}[OK]${NC} SSH käynnissä, palomuuri konfiguroitu"

# ── 9. Tailscale-yhteys ────────────────────────────────────

echo ""
echo -e "${YELLOW}[9/9]${NC} Tailscale-kirjautuminen..."
echo ""

# Tarkista onko jo yhdistetty
ts_state=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null || echo "")

if [ "$ts_state" = "Running" ]; then
    echo -e "${GREEN}[OK]${NC} Tailscale jo yhdistetty"
else
    echo -e "${BOLD}Avaa selaimessa näkyvä linkki kirjautuaksesi Tailscaleen:${NC}"
    echo ""
    tailscale up
    echo ""

    # Odota yhteyden muodostumista (max 120s)
    for i in $(seq 1 24); do
        ts_state=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null || echo "")
        if [ "$ts_state" = "Running" ]; then
            break
        fi
        sleep 5
    done

    if [ "$ts_state" = "Running" ]; then
        echo -e "${GREEN}[OK]${NC} Tailscale yhdistetty"
    else
        echo -e "${RED}[FAIL]${NC} Tailscale-yhteys ei muodostunut. Aja myöhemmin: sudo tailscale up"
    fi
fi

# ── Valmis ──────────────────────────────────────────────────

TS_IP=$(tailscale ip -4 2>/dev/null || echo "???")

echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         ASENNUS VALMIS!                ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Lähetä nämä tiedot veljellesi:"
echo ""
echo -e "  ${BOLD}┌─────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}│${NC}  Tailscale IP:   ${GREEN}${TS_IP}${NC}"
echo -e "  ${BOLD}│${NC}  Käyttäjä:       ${GREEN}${ACTUAL_USER}${NC}"
echo -e "  ${BOLD}└─────────────────────────────────────┘${NC}"
echo ""

# SSH-avain puuttuu vielä — ohjeista
if [ ! -s "$ACTUAL_HOME/.ssh/authorized_keys" ]; then
    echo -e "  ${YELLOW}Odota vielä:${NC} veljesi lähettää SSH-avaimen."
    echo -e "  Kun saat sen, aja:"
    echo -e "    echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys"
    echo ""
fi

# Health check
echo -e "  Tarkista asennus: ${BOLD}~/tools/health.sh${NC}"
echo ""

# Dialout-varoitus
if ! id -nG "$ACTUAL_USER" | grep -qw dialout 2>/dev/null; then
    echo -e "  ${YELLOW}HUOM:${NC} Kirjaudu ulos ja takaisin (dialout-ryhmä)."
fi
