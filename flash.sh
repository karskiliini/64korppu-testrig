#!/bin/bash
# 64korppu — Flash .hex Arduino Nanoon
# Käyttö: flash.sh <hexfile> [--port /dev/arduino] [--baud 115200]

set -euo pipefail

# Oletukset
PORT="/dev/arduino"
BAUD=115200
MCU="atmega328p"
PROGRAMMER="arduino"
HEX=""

# Parsitaan argumentit
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --baud) BAUD="$2"; shift 2 ;;
        *) HEX="$1"; shift ;;
    esac
done

if [ -z "$HEX" ]; then
    echo "FLASH_FAIL: Ei hex-tiedostoa"
    echo "Käyttö: flash.sh <hexfile> [--port /dev/arduino] [--baud 115200]"
    exit 1
fi

if [ ! -f "$HEX" ]; then
    echo "FLASH_FAIL: Tiedostoa ei löydy: $HEX"
    exit 1
fi

hex_size=$(stat -c%s "$HEX" 2>/dev/null || stat -f%z "$HEX" 2>/dev/null)
if [ "$hex_size" -eq 0 ]; then
    echo "FLASH_FAIL: Hex-tiedosto on tyhjä"
    exit 1
fi

# Jos /dev/arduino ei löydy, yritä fallback
if [ ! -e "$PORT" ]; then
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        if [ -e "$dev" ]; then
            echo "WARN: $PORT ei löydy, käytetään $dev"
            PORT="$dev"
            break
        fi
    done
fi

if [ ! -e "$PORT" ]; then
    echo "FLASH_FAIL: Sarjaporttia ei löydy ($PORT)"
    exit 1
fi

# Tapa mahdollinen käynnissä oleva monitor.py
PID_FILE="$HOME/.testrig-monitor.pid"
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Tapetaan käynnissä oleva monitor (PID $old_pid)..."
        kill "$old_pid" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$PID_FILE"
fi

# Vapauta portti varmuudeksi
if command -v fuser &>/dev/null; then
    fuser -k "$PORT" 2>/dev/null || true
    sleep 0.3
fi

# Flash
echo "Flashataan: $HEX -> $PORT @ ${BAUD} baud"
start_time=$(date +%s%N)

avrdude_output=$(avrdude -c "$PROGRAMMER" -p "$MCU" -P "$PORT" -b "$BAUD" \
    -U "flash:w:${HEX}:i" 2>&1) && flash_ok=true || flash_ok=false

if [ "$flash_ok" = "false" ] && [ "$BAUD" -eq 115200 ]; then
    # Yritä vanhaa bootloaderia (57600)
    echo "WARN: 115200 epäonnistui, yritetään 57600 (vanha bootloader)..."
    sleep 1
    avrdude_output=$(avrdude -c "$PROGRAMMER" -p "$MCU" -P "$PORT" -b 57600 \
        -U "flash:w:${HEX}:i" 2>&1) && flash_ok=true || flash_ok=false
    if [ "$flash_ok" = "true" ]; then
        BAUD=57600
    fi
fi

end_time=$(date +%s%N)
elapsed=$(( (end_time - start_time) / 1000000 ))

if [ "$flash_ok" = "true" ]; then
    echo "FLASH_OK: $PORT ($hex_size bytes, ${elapsed}ms, baud=$BAUD)"
    # Odota Nanon uudelleenkäynnistys (bootloader ~1s + firmware start)
    # WSL2 + usbipd: USB-laite katoaa ja palaa takaisin resetissä,
    # auto-attach tarvitsee enemmän aikaa
    if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
        echo "WSL2: odotetaan USB-laitteen uudelleenliitäntää..."
        sleep 4
        # Odota portin ilmestymistä (usbipd auto-attach)
        for i in $(seq 1 10); do
            [ -e "$PORT" ] && break
            sleep 1
        done
        if [ ! -e "$PORT" ]; then
            echo "WARN: $PORT ei ilmestynyt takaisin — tarkista usbipd auto-attach"
        fi
    else
        sleep 2
    fi
    echo "Nano käynnistynyt uudelleen"
    exit 0
else
    echo "FLASH_FAIL: avrdude epäonnistui"
    echo "$avrdude_output"
    exit 1
fi
