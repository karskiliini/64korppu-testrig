#!/bin/bash
# 64korppu — Test rig diagnostiikka
# Tarkistaa kaiken oleellisen yhdellä komennolla.
# Toimii natiivilla Ubuntulla ja WSL2:lla.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

errors=0

# WSL2-tunnistus
IS_WSL=false
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    IS_WSL=true
fi

echo "=== 64korppu Test Rig Health ==="
if [ "$IS_WSL" = true ]; then
    echo "(WSL2-tila)"
fi
echo ""

# 1. Tailscale
echo -n "Tailscale: "
if [ "$IS_WSL" = true ]; then
    # WSL2: tarkista Windows-puolen Tailscale
    ts_exe="/mnt/c/Program Files/Tailscale/tailscale.exe"
    if [ -f "$ts_exe" ]; then
        ts_ip=$("$ts_exe" ip -4 2>/dev/null | tr -d '\r\n' || echo "?")
        if [[ "$ts_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${GREEN}OK${NC} (Windows, IP: $ts_ip)"
        else
            echo -e "${RED}FAIL${NC} (Windows Tailscale ei yhdistetty)"
            errors=$((errors + 1))
        fi
    else
        echo -e "${RED}FAIL${NC} (Tailscale ei asennettu Windowsiin)"
        errors=$((errors + 1))
    fi
else
    if command -v tailscale &>/dev/null; then
        ts_status=$(tailscale status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState','?'))" 2>/dev/null || echo "?")
        if [ "$ts_status" = "Running" ]; then
            ts_ip=$(tailscale ip -4 2>/dev/null || echo "?")
            echo -e "${GREEN}OK${NC} (IP: $ts_ip)"
        else
            echo -e "${RED}FAIL${NC} (status: $ts_status)"
            errors=$((errors + 1))
        fi
    else
        echo -e "${RED}FAIL${NC} (ei asennettu)"
        errors=$((errors + 1))
    fi
fi

# 2. SSH
echo -n "SSH:       "
if [ "$IS_WSL" = true ]; then
    # WSL2: SSH on Windows-puolella
    if powershell.exe -Command "Get-Service sshd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status" 2>/dev/null | tr -d '\r\n' | grep -qi "running"; then
        echo -e "${GREEN}OK${NC} (Windows OpenSSH)"
    else
        echo -e "${RED}FAIL${NC} (Windows OpenSSH ei käynnissä — aja windows-setup.ps1)"
        errors=$((errors + 1))
    fi
else
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC} (sshd ei käynnissä)"
        errors=$((errors + 1))
    fi
fi

# 3. Arduino
echo -n "Arduino:   "
if [ -e /dev/arduino ]; then
    real_dev=$(readlink -f /dev/arduino)
    echo -e "${GREEN}OK${NC} (/dev/arduino -> $real_dev)"
else
    found=""
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$dev" ] && found="$dev" && break
    done
    if [ -n "$found" ]; then
        echo -e "${YELLOW}WARN${NC} ($found löytyi, mutta /dev/arduino symlink puuttuu)"
    else
        if [ "$IS_WSL" = true ]; then
            echo -e "${RED}FAIL${NC} (ei laitetta — aja Windowsissa: usbipd attach --wsl --busid <ID>)"
        else
            echo -e "${RED}FAIL${NC} (ei laitetta)"
        fi
        errors=$((errors + 1))
    fi
fi

# 4. Serial-oikeudet
echo -n "Dialout:   "
if id -nG | grep -qw dialout; then
    echo -e "${GREEN}OK${NC} (käyttäjä dialout-ryhmässä)"
else
    echo -e "${RED}FAIL${NC} (käyttäjä ei dialout-ryhmässä — aja: sudo usermod -aG dialout \$USER)"
    errors=$((errors + 1))
fi

# 5. avrdude
echo -n "avrdude:   "
if command -v avrdude &>/dev/null; then
    ver=$(avrdude -? 2>&1 | head -1 || echo "?")
    echo -e "${GREEN}OK${NC} ($ver)"
else
    echo -e "${RED}FAIL${NC} (ei asennettu)"
    errors=$((errors + 1))
fi

# 6. pyserial
echo -n "pyserial:  "
ver=$(python3 -c "import serial; print(serial.VERSION)" 2>/dev/null || echo "")
if [ -n "$ver" ]; then
    echo -e "${GREEN}OK${NC} (v$ver)"
else
    echo -e "${RED}FAIL${NC} (pip3 install pyserial)"
    errors=$((errors + 1))
fi

# 7. Skriptit
echo -n "Skriptit:  "
scripts_ok=true
for script in ~/tools/flash.sh ~/tools/monitor.py ~/tools/detect.sh; do
    if [ ! -x "$script" ]; then
        echo -e "${RED}FAIL${NC} ($script puuttuu tai ei suoritettava)"
        scripts_ok=false
        errors=$((errors + 1))
        break
    fi
done
if [ "$scripts_ok" = "true" ]; then
    echo -e "${GREEN}OK${NC}"
fi

# 8. Levytila
echo -n "Levy:      "
avail=$(df -h /home 2>/dev/null | tail -1 | awk '{print $4}')
echo -e "${GREEN}OK${NC} ($avail vapaana)"

# 9. Portin lukitus
echo -n "Portti:    "
if [ -e /dev/arduino ]; then
    lock_pid=$(fuser /dev/arduino 2>/dev/null || true)
    if [ -n "$lock_pid" ]; then
        proc=$(ps -p $lock_pid -o comm= 2>/dev/null || echo "?")
        echo -e "${YELLOW}LUKITTU${NC} (PID $lock_pid: $proc)"
    else
        echo -e "${GREEN}vapaa${NC}"
    fi
else
    echo -e "- (ei laitetta)"
fi

# 10. WSL2: usbipd
if [ "$IS_WSL" = true ]; then
    echo -n "usbipd:    "
    if command -v usbipd.exe &>/dev/null || [ -f "/mnt/c/Program Files/usbipd-win/usbipd.exe" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC} (aja windows-setup.ps1 Windowsissa)"
        errors=$((errors + 1))
    fi
fi

echo ""
if [ "$errors" -eq 0 ]; then
    echo -e "${GREEN}=== Kaikki OK ===${NC}"
else
    echo -e "${RED}=== $errors ongelmaa ===${NC}"
fi

exit "$errors"
