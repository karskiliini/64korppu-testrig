#!/usr/bin/env python3
"""64korppu — Serial monitor automaattista testausta varten.

Lukee Arduino Nanon sarjaporttioutputin ja raportoi tulokset.
Suunniteltu Claude Code -käyttöön SSH:n yli.

Käyttö:
    monitor.py [--port /dev/arduino] [--baud 9600] [--timeout 30]
               [--stop-on "Ready."] [--no-reset]

Exit-koodit:
    0 = --stop-on pattern löydetty (tai normaali lopetus)
    1 = virhe (portti ei löydy, oikeudet jne.)
    2 = timeout ilman --stop-on patternia
    3 = laite irtosi USB:sta
"""

import argparse
import os
import signal
import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("MONITOR_FAIL: pyserial ei asennettu (pip3 install pyserial)", file=sys.stderr)
    sys.exit(1)

PID_FILE = os.path.expanduser("~/.testrig-monitor.pid")


def find_arduino_port():
    """Etsi Arduino-portti. Palauttaa polun tai None."""
    # Udev-symlink ensin
    if os.path.exists("/dev/arduino"):
        return "/dev/arduino"

    # Fallback: etsi USB-serial-laitteet
    for pattern in ["/dev/ttyUSB*", "/dev/ttyACM*"]:
        import glob
        ports = glob.glob(pattern)
        if ports:
            return ports[0]

    return None


def write_pid():
    """Kirjoita PID-tiedosto."""
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))


def remove_pid():
    """Poista PID-tiedosto."""
    try:
        os.unlink(PID_FILE)
    except OSError:
        pass


def open_serial(port, baud, no_reset, retries=6, retry_delay=0.5):
    """Avaa sarjaportti retry-logiikalla.

    avrdude saattaa vielä pitää porttia hetken flashauksen jälkeen,
    joten yritetään muutaman kerran.
    """
    for attempt in range(retries):
        try:
            ser = serial.Serial()
            ser.port = port
            ser.baudrate = baud
            ser.bytesize = serial.EIGHTBITS
            ser.parity = serial.PARITY_NONE
            ser.stopbits = serial.STOPBITS_ONE
            ser.timeout = 0.5  # read timeout
            ser.write_timeout = 1

            if no_reset:
                # Älä resetoi — monitoroi käynnissä olevaa laitetta
                ser.dtr = False
                ser.rts = False

            ser.open()

            if not no_reset:
                # DTR-reset: kaappaa koko boot-sekvenssi
                ser.dtr = False
                time.sleep(0.1)
                ser.dtr = True
                time.sleep(0.1)
                ser.dtr = False
                # Tyhjennä puskuri resetin jälkeen
                time.sleep(0.2)
                ser.reset_input_buffer()

            return ser
        except (serial.SerialException, OSError) as e:
            if attempt < retries - 1:
                time.sleep(retry_delay)
            else:
                raise


def main():
    parser = argparse.ArgumentParser(description="64korppu serial monitor")
    parser.add_argument("--port", default=None, help="Sarjaportti (oletus: autodetect)")
    parser.add_argument("--baud", type=int, default=9600, help="Baudinopeus (oletus: 9600)")
    parser.add_argument("--timeout", type=int, default=30, help="Timeout sekunteina (oletus: 30)")
    parser.add_argument("--stop-on", dest="stop_on", default=None, help="Lopeta kun rivi sisältää tämän")
    parser.add_argument("--no-reset", dest="no_reset", action="store_true", help="Älä resetoi Arduinoa")
    args = parser.parse_args()

    # Etsi portti
    port = args.port or find_arduino_port()
    if port is None:
        print("MONITOR_FAIL: Arduinoa ei löydy", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(port):
        print(f"MONITOR_FAIL: Porttia {port} ei ole olemassa", file=sys.stderr)
        sys.exit(1)

    # PID-tiedosto
    write_pid()

    # Siivoa SIGTERM/SIGINT:lla
    ser = None

    def cleanup(signum=None, frame=None):
        remove_pid()
        if ser and ser.is_open:
            ser.close()
        if signum is not None:
            sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    exit_code = 0

    try:
        ser = open_serial(port, args.baud, args.no_reset)
        print(f"MONITOR: {port} @ {args.baud} baud (timeout={args.timeout}s"
              f"{', stop-on=' + repr(args.stop_on) if args.stop_on else ''}"
              f"{', no-reset' if args.no_reset else ''})")
        sys.stdout.flush()

        start_time = time.time()
        line_buf = b""

        while True:
            # Timeout-tarkistus
            elapsed = time.time() - start_time
            if elapsed >= args.timeout:
                if args.stop_on:
                    print(f"\nMONITOR_TIMEOUT: {args.timeout}s ('{args.stop_on}' ei löytynyt)")
                    exit_code = 2
                else:
                    print(f"\nMONITOR_DONE: {args.timeout}s timeout")
                    exit_code = 0
                break

            # Lue dataa
            try:
                data = ser.read(256)
            except serial.SerialException:
                print("\nMONITOR_DISCONNECT: Laite irtosi", file=sys.stderr)
                exit_code = 3
                break

            if not data:
                continue

            # Käsittele rivi kerrallaan
            line_buf += data
            while b"\n" in line_buf:
                line, line_buf = line_buf.split(b"\n", 1)
                line_str = line.decode("ascii", errors="replace").rstrip("\r")

                # Tulosta heti (flush SSH:n yli)
                print(line_str)
                sys.stdout.flush()

                # Stop-on tarkistus
                if args.stop_on and args.stop_on in line_str:
                    print(f"\nMONITOR_MATCH: '{args.stop_on}' löytyi")
                    exit_code = 0
                    cleanup()
                    sys.exit(0)

    except serial.SerialException as e:
        print(f"MONITOR_FAIL: {e}", file=sys.stderr)
        exit_code = 1
    except Exception as e:
        print(f"MONITOR_FAIL: {e}", file=sys.stderr)
        exit_code = 1
    finally:
        cleanup()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
