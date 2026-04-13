#!/bin/bash
# 64korppu — Arduino-tunnistus
# Etsii kytketyn Arduino Nanon ja raportoi tiedot.
# Exit 0 = löytyi, Exit 1 = ei löytynyt

set -euo pipefail

# Värit
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

found=0

# Tarkista udev-symlink ensin
if [ -e /dev/arduino ]; then
    real_dev=$(readlink -f /dev/arduino)
    echo -e "${GREEN}[OK]${NC} /dev/arduino -> $real_dev"

    # Lue USB-tiedot
    if command -v udevadm &>/dev/null; then
        vendor=$(udevadm info -q property -n /dev/arduino 2>/dev/null | grep "ID_VENDOR=" | cut -d= -f2 || echo "?")
        model=$(udevadm info -q property -n /dev/arduino 2>/dev/null | grep "ID_MODEL=" | cut -d= -f2 || echo "?")
        serial=$(udevadm info -q property -n /dev/arduino 2>/dev/null | grep "ID_SERIAL_SHORT=" | cut -d= -f2 || echo "?")
        echo "  Vendor: $vendor"
        echo "  Model:  $model"
        echo "  Serial: $serial"
    fi

    # Tarkista ettei portti ole lukittu
    if command -v fuser &>/dev/null; then
        lock_pid=$(fuser "$real_dev" 2>/dev/null || true)
        if [ -n "$lock_pid" ]; then
            echo -e "${RED}[WARN]${NC} Portti lukittu prosessilla: $lock_pid"
            ps -p $lock_pid -o pid,comm= 2>/dev/null || true
        else
            echo -e "${GREEN}[OK]${NC} Portti vapaa"
        fi
    fi

    found=1
fi

# Fallback: etsi /dev/ttyUSB* ja /dev/ttyACM*
if [ "$found" -eq 0 ]; then
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$dev" ] || continue
        echo -e "${GREEN}[FOUND]${NC} $dev (ei udev-symlinkkiä)"
        if command -v udevadm &>/dev/null; then
            vendor=$(udevadm info -q property -n "$dev" 2>/dev/null | grep "ID_VENDOR=" | cut -d= -f2 || echo "?")
            model=$(udevadm info -q property -n "$dev" 2>/dev/null | grep "ID_MODEL=" | cut -d= -f2 || echo "?")
            echo "  Vendor: $vendor  Model: $model"
        fi
        found=1
    done
fi

if [ "$found" -eq 0 ]; then
    echo -e "${RED}[FAIL]${NC} Arduino ei löytynyt"
    echo "  Tarkista USB-kaapeli ja että laite on kytketty"
    exit 1
fi

exit 0
