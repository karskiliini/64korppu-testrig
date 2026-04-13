#!/bin/bash
# 64korppu — Test rig one-liner installer
#
# Natiivi Ubuntu:
#   curl -fsSL https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/install.sh | bash
#
# WSL2 Ubuntu (Windows 10/11):
#   1. Avaa PowerShell järjestelmänvalvojana, aja:
#      Invoke-WebRequest -Uri "https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/windows-setup.ps1" -OutFile "$env:TEMP\windows-setup.ps1"; & "$env:TEMP\windows-setup.ps1"
#   2. Avaa WSL-terminaali, aja:
#      curl -fsSL https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/install.sh | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── WSL2-tunnistus ──────────────────────────────────────────

IS_WSL=false
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    IS_WSL=true
fi

echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   64korppu Remote Test Rig Installer   ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
if [ "$IS_WSL" = true ]; then
    echo -e "${BOLD}║          WSL2-tila tunnistettu         ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
fi
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

# Laske vaiheet ympäristön mukaan
if [ "$IS_WSL" = true ]; then
    TOTAL_STEPS=9
else
    TOTAL_STEPS=9
fi
STEP=0
next_step() { STEP=$((STEP + 1)); }

# ── WSL2: varmista systemd ──────────────────────────────────

if [ "$IS_WSL" = true ]; then
    next_step
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} WSL2: tarkistetaan systemd..."

    WSL_CONF="/etc/wsl.conf"
    NEED_RESTART=false

    if ! grep -q "^\[boot\]" "$WSL_CONF" 2>/dev/null || ! grep -q "^systemd=true" "$WSL_CONF" 2>/dev/null; then
        # Lisää [boot] systemd=true
        if grep -q "^\[boot\]" "$WSL_CONF" 2>/dev/null; then
            # [boot] osio on olemassa, lisää systemd=true
            sed -i '/^\[boot\]/a systemd=true' "$WSL_CONF"
        else
            # Luo [boot] osio
            echo -e "\n[boot]\nsystemd=true" >> "$WSL_CONF"
        fi
        NEED_RESTART=true
        echo -e "${GREEN}[OK]${NC} systemd otettu käyttöön /etc/wsl.conf"
    else
        echo -e "${GREEN}[OK]${NC} systemd jo käytössä"
    fi

    # Tarkista onko systemd oikeasti käynnissä
    if [ ! -d /run/systemd/system ]; then
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  WSL täytyy käynnistää uudelleen!                ║${NC}"
        echo -e "${RED}║                                                   ║${NC}"
        echo -e "${RED}║  1. Sulje tämä WSL-ikkuna                        ║${NC}"
        echo -e "${RED}║  2. Avaa PowerShell ja aja: wsl --shutdown        ║${NC}"
        echo -e "${RED}║  3. Avaa WSL uudelleen                           ║${NC}"
        echo -e "${RED}║  4. Aja tämä skripti uudelleen                   ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
        echo ""
        exit 1
    fi
fi

# ── 1. Git + perustyökalut ──────────────────────────────────

next_step
echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Asennetaan perustyökalut..."
apt-get update -qq
apt-get install -y -qq git curl > /dev/null
echo -e "${GREEN}[OK]${NC} git + curl"

# ── 2. Kloonaa repo ────────────────────────────────────────

next_step
echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Ladataan testrig-skriptit..."
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

next_step
echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Asennetaan paketit..."
apt-get install -y -qq avrdude python3-pip python3-serial udev > /dev/null

# WSL2: ei tarvita openssh-serveriä (SSH on Windows-puolella)
if [ "$IS_WSL" = false ]; then
    apt-get install -y -qq openssh-server > /dev/null
fi

if ! python3 -c "import serial" 2>/dev/null; then
    pip3 install pyserial --break-system-packages 2>/dev/null || pip3 install pyserial
fi
echo -e "${GREEN}[OK]${NC} avrdude, pyserial"

# ── 4. Tailscale ────────────────────────────────────────────

next_step
if [ "$IS_WSL" = true ]; then
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Tailscale..."
    echo -e "${GREEN}[OK]${NC} WSL2: Tailscale ajetaan Windows-puolella (windows-setup.ps1 hoitaa)"
else
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Asennetaan Tailscale..."
    if command -v tailscale &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Tailscale jo asennettu"
    else
        curl -fsSL https://tailscale.com/install.sh | sh
        echo -e "${GREEN}[OK]${NC} Tailscale asennettu"
    fi
fi

# ── 5. Dialout-ryhmä ───────────────────────────────────────

next_step
echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Serial-oikeudet..."
if id -nG "$ACTUAL_USER" | grep -qw dialout; then
    echo -e "${GREEN}[OK]${NC} $ACTUAL_USER jo dialout-ryhmässä"
else
    usermod -aG dialout "$ACTUAL_USER"
    echo -e "${GREEN}[OK]${NC} $ACTUAL_USER lisätty dialout-ryhmään"
fi

# ── 6. Udev-säännöt ────────────────────────────────────────

next_step
echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Arduino udev-säännöt..."
cp "$INSTALL_DIR/99-arduino.rules" /etc/udev/rules.d/99-arduino.rules

if [ -d /run/systemd/system ]; then
    udevadm control --reload-rules
    udevadm trigger
else
    # Fallback: käynnistä udev manuaalisesti
    service udev restart 2>/dev/null || true
fi

if [ "$IS_WSL" = true ]; then
    echo -e "${GREEN}[OK]${NC} udev-säännöt (USB-laite pitää liittää usbipd:llä)"
else
    echo -e "${GREEN}[OK]${NC} /dev/arduino symlink konfiguroitu"
fi

# ── 7. Skriptit + hakemistot ──────────────────────────────

next_step
echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Asennetaan työkalut..."
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

next_step
if [ "$IS_WSL" = true ]; then
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} SSH..."
    # WSL2: SSH on Windows-puolella, mutta tarvitaan authorized_keys
    # koska Windows OpenSSH:n default shell asetetaan wsl bashiksi
    mkdir -p "$ACTUAL_HOME/.ssh"
    chmod 700 "$ACTUAL_HOME/.ssh"
    touch "$ACTUAL_HOME/.ssh/authorized_keys"
    chmod 600 "$ACTUAL_HOME/.ssh/authorized_keys"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.ssh"

    # Hae Windows-käyttäjän kotihakemisto authorized_keys:ille
    WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")
    WIN_HOME="/mnt/c/Users/$WIN_USER"

    if [ -n "$WIN_USER" ] && [ -d "$WIN_HOME" ]; then
        mkdir -p "$WIN_HOME/.ssh"
        # Linkitä tai kopioi — Windows OpenSSH lukee tästä
        if [ ! -f "$WIN_HOME/.ssh/authorized_keys" ]; then
            touch "$WIN_HOME/.ssh/authorized_keys"
        fi
        echo -e "${GREEN}[OK]${NC} SSH: Windows OpenSSH hoitaa (windows-setup.ps1)"
        echo -e "         authorized_keys: $WIN_HOME/.ssh/authorized_keys"
    else
        echo -e "${GREEN}[OK]${NC} SSH: Windows OpenSSH hoitaa (windows-setup.ps1)"
    fi
else
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} SSH-palvelin..."
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
fi

# ── 9. Tailscale-yhteys (vain natiivi) ─────────────────────

next_step
if [ "$IS_WSL" = true ]; then
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Yhteys..."
    echo -e "${GREEN}[OK]${NC} WSL2: Tailscale-yhteys muodostetaan Windows-puolella"
else
    echo ""
    echo -e "${YELLOW}[$STEP/$TOTAL_STEPS]${NC} Tailscale-kirjautuminen..."
    echo ""

    ts_state=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null || echo "")

    if [ "$ts_state" = "Running" ]; then
        echo -e "${GREEN}[OK]${NC} Tailscale jo yhdistetty"
    else
        echo -e "${BOLD}Avaa selaimessa näkyvä linkki kirjautuaksesi Tailscaleen:${NC}"
        echo ""
        tailscale up
        echo ""

        for i in $(seq 1 24); do
            ts_state=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('BackendState',''))" 2>/dev/null || echo "")
            [ "$ts_state" = "Running" ] && break
            sleep 5
        done

        if [ "$ts_state" = "Running" ]; then
            echo -e "${GREEN}[OK]${NC} Tailscale yhdistetty"
        else
            echo -e "${RED}[FAIL]${NC} Tailscale-yhteys ei muodostunut. Aja myöhemmin: sudo tailscale up"
        fi
    fi
fi

# ── Valmis ──────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         ASENNUS VALMIS!                ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"
echo ""

if [ "$IS_WSL" = true ]; then
    # WSL2: ohjeista Windows-puolen setup
    WIN_USER=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "")

    echo -e "  ${BOLD}WSL2-puoli asennettu.${NC}"
    echo ""

    # Tarkista onko Windows-setup jo ajettu
    WIN_TS_RUNNING=false
    if command -v tailscale.exe &>/dev/null 2>/dev/null; then
        WIN_TS_RUNNING=true
    elif [ -f "/mnt/c/Program Files/Tailscale/tailscale.exe" ]; then
        WIN_TS_RUNNING=true
    fi

    if [ "$WIN_TS_RUNNING" = false ]; then
        echo -e "  ${YELLOW}Seuraava vaihe:${NC} Aja Windows-puolen setup."
        echo -e "  Avaa ${BOLD}PowerShell järjestelmänvalvojana${NC} ja aja:"
        echo ""
        echo -e "  ${BOLD}Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/karskiliini/64korppu-testrig/main/windows-setup.ps1' -OutFile \"\$env:TEMP\\windows-setup.ps1\"; & \"\$env:TEMP\\windows-setup.ps1\"${NC}"
        echo ""
        echo -e "  Se asentaa: Tailscale, usbipd-win, OpenSSH-palvelin"
        echo -e "  ja konfiguroi SSH:n käyttämään WSL:ää automaattisesti."
        echo ""
    else
        # Windows-setup on jo ajettu, näytä yhteyden tiedot
        TS_IP=$("/mnt/c/Program Files/Tailscale/tailscale.exe" ip -4 2>/dev/null | tr -d '\r\n' || echo "???")
        echo -e "  Lähetä nämä tiedot veljellesi:"
        echo ""
        echo -e "  ${BOLD}┌─────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}│${NC}  Tailscale IP:   ${GREEN}${TS_IP}${NC}"
        echo -e "  ${BOLD}│${NC}  Käyttäjä:       ${GREEN}${WIN_USER:-$ACTUAL_USER}${NC}"
        echo -e "  ${BOLD}└─────────────────────────────────────┘${NC}"
        echo ""
    fi

    echo -e "  ${YELLOW}Muista:${NC} Arduino Nano liitetään WSL:ään komennolla:"
    echo -e "    usbipd attach --wsl --auto-attach --busid <BUS-ID>"
    echo -e "    (aja PowerShellissä, BUS-ID löytyy: usbipd list)"
    echo ""
else
    # Natiivi Ubuntu
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "???")

    echo -e "  Lähetä nämä tiedot veljellesi:"
    echo ""
    echo -e "  ${BOLD}┌─────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}│${NC}  Tailscale IP:   ${GREEN}${TS_IP}${NC}"
    echo -e "  ${BOLD}│${NC}  Käyttäjä:       ${GREEN}${ACTUAL_USER}${NC}"
    echo -e "  ${BOLD}└─────────────────────────────────────┘${NC}"
    echo ""

    if [ ! -s "$ACTUAL_HOME/.ssh/authorized_keys" ]; then
        echo -e "  ${YELLOW}Odota vielä:${NC} veljesi lähettää SSH-avaimen."
        echo -e "  Kun saat sen, aja:"
        echo -e "    echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys"
        echo ""
    fi
fi

echo -e "  Tarkista asennus: ${BOLD}~/tools/health.sh${NC}"
echo ""

if ! id -nG "$ACTUAL_USER" | grep -qw dialout 2>/dev/null; then
    echo -e "  ${YELLOW}HUOM:${NC} Kirjaudu ulos ja takaisin (dialout-ryhmä)."
fi
