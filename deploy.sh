#!/bin/bash
# 64korppu — Build + deploy + flash + monitor
#
# Kääntää firmwaren, kopioi veljen koneelle, flashaa ja (valinnaisesti)
# monitoroi serial-outputin. Suunniteltu Claude Code -käyttöön.
#
# Käyttö:
#   deploy.sh [--monitor] [--timeout 30] [--stop-on "Ready."] [--no-reset] [--no-build]
#
# Esimerkkejä:
#   deploy.sh                                    # Käännä + flashaa
#   deploy.sh --monitor                          # + monitoroi 30s
#   deploy.sh --monitor --stop-on "Ready."       # + lopeta kun Ready.
#   deploy.sh --monitor --timeout 120 --no-reset # Pitkä monitorointi

set -euo pipefail

# Oletus-arvot
MONITOR=false
TIMEOUT=30
STOP_ON=""
NO_RESET=false
NO_BUILD=false

# Projektin juurihakemisto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FW_DIR="$PROJECT_ROOT/firmware/E-IEC-Nano-SRAM"
HEX_FILE="$FW_DIR/64korppu_nano.hex"

# Parsitaan argumentit
while [[ $# -gt 0 ]]; do
    case "$1" in
        --monitor)   MONITOR=true; shift ;;
        --timeout)   TIMEOUT="$2"; shift 2 ;;
        --stop-on)   STOP_ON="$2"; shift 2 ;;
        --no-reset)  NO_RESET=true; shift ;;
        --no-build)  NO_BUILD=true; shift ;;
        *) echo "Tuntematon argumentti: $1"; exit 1 ;;
    esac
done

echo "=== 64korppu Deploy ==="

# ── 1. Käännä ───────────────────────────────────────────────

if [ "$NO_BUILD" = "false" ]; then
    echo "[1/4] Käännetään firmware..."
    make -C "$FW_DIR" clean all
    if [ ! -f "$HEX_FILE" ]; then
        echo "DEPLOY_FAIL: Hex-tiedostoa ei löydy: $HEX_FILE"
        exit 1
    fi
    hex_size=$(stat -f%z "$HEX_FILE" 2>/dev/null || stat -c%s "$HEX_FILE" 2>/dev/null)
    echo "[OK] $HEX_FILE ($hex_size bytes)"
else
    echo "[1/4] Ohitetaan build (--no-build)"
    if [ ! -f "$HEX_FILE" ]; then
        echo "DEPLOY_FAIL: Hex-tiedostoa ei löydy: $HEX_FILE"
        exit 1
    fi
fi

# ── 2. Kopioi ───────────────────────────────────────────────

echo "[2/4] Kopioidaan testrigille..."
scp "$HEX_FILE" testrig:~/firmware/latest.hex
echo "[OK] Kopioitu"

# ── 3. Flashaa ──────────────────────────────────────────────

echo "[3/4] Flashataan..."
ssh testrig "~/tools/flash.sh ~/firmware/latest.hex"

# ── 4. Monitoroi (valinnainen) ──────────────────────────────

if [ "$MONITOR" = "true" ]; then
    echo "[4/4] Monitoroidaan serial ($TIMEOUT s)..."

    monitor_args="--timeout $TIMEOUT"
    [ -n "$STOP_ON" ] && monitor_args="$monitor_args --stop-on '$STOP_ON'"
    [ "$NO_RESET" = "true" ] && monitor_args="$monitor_args --no-reset"

    ssh testrig "~/tools/monitor.py $monitor_args"
    monitor_exit=$?

    if [ $monitor_exit -eq 0 ]; then
        echo "DEPLOY_OK: Monitorointi päättyi onnistuneesti"
    elif [ $monitor_exit -eq 2 ]; then
        echo "DEPLOY_TIMEOUT: Monitorointi timeout ($TIMEOUT s)"
    else
        echo "DEPLOY_FAIL: Monitorointi epäonnistui (exit $monitor_exit)"
        exit 1
    fi
else
    echo "[4/4] Monitorointi ohitettu (käytä --monitor)"
    echo "DEPLOY_OK: Flash valmis"
fi
