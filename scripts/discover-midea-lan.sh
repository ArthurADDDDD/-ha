#!/data/data/com.termux/files/usr/bin/bash
# scripts/discover-midea-lan.sh - Midea device discovery from Termux
# Usage: bash scripts/discover-midea-lan.sh [IP_ADDRESS]
set -euo pipefail

TARGET_IP="${1:-}"

python3 - "$TARGET_IP" <<'PY'
import socket
import sys
import struct
import time

TARGET = sys.argv[1] if sys.argv[1] else None
PORTS = [6445, 20086]

BROADCAST_MSG = bytearray([
    0x5A, 0x5A, 0x01, 0x11, 0x48, 0x00, 0x92, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x7F, 0x75, 0xBD, 0x6B, 0x3E, 0x4F, 0x8B, 0x76,
    0x2E, 0x84, 0x9C, 0x6E, 0x57, 0x8D, 0x65, 0x90,
    0x03, 0x6E, 0x9D, 0x43, 0x42, 0xA5, 0x0F, 0x1F,
    0x56, 0x9E, 0xB8, 0xEC, 0x91, 0x8E, 0x92, 0xE5,
])

# Build target list
targets = []
if TARGET:
    targets.append(TARGET)
    # Also send to the subnet broadcast
    parts = TARGET.rsplit('.', 1)
    if len(parts) == 2:
        targets.append(f"{parts[0]}.255")

print(f"==> Midea LAN Discovery")
if TARGET:
    print(f"  Targets: {', '.join(targets)}")
else:
    print(f"  Broadcast to: 255.255.255.255")
    targets.append("255.255.255.255")
print()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(8)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

try:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
except OSError:
    pass

for target in targets:
    for port in PORTS:
        try:
            sock.sendto(BROADCAST_MSG, (target, port))
            print(f"  [SEND] {target}:{port}")
        except OSError as e:
            print(f"  [FAIL] {target}:{port}: {e}")

print()
print("  Waiting for responses (8s timeout)...")
print()

found = set()
while True:
    try:
        data, addr = sock.recvfrom(1024)
        key = f"{addr[0]}:{addr[1]}"
        if key in found:
            continue
        found.add(key)

        print(f"--- Device at {addr[0]}:{addr[1]} ({len(data)} bytes) ---")
        print(f"  hex: {data.hex()}")

        header = data[:2]
        if header == b'\x5a\x5a':
            version = 2
            inner = data
        elif header == b'\x83\x70':
            version = 3
            inner = data[8:]
        else:
            version = "unknown"
            inner = data

        print(f"  protocol version: {version}")

        if version in (2, 3) and len(inner) >= 40:
            # Extract device_id from unencrypted header (bytes 20-26, little-endian)
            device_id_raw = inner[20:26]
            device_id = int.from_bytes(device_id_raw, 'little')
            print(f"  device_id: {device_id}")

            # Extract SN (bytes 8-40)
            sn_raw = inner[8:40]
            sn = sn_raw.split(b'\x00')[0].decode('ascii', errors='replace').strip()
            print(f"  SN: {sn}")

            # Extract model hint from SSID
            if len(inner) > 41:
                ssid_raw = inner[41:]
                ssid = ssid_raw.split(b'\x00')[0].decode('ascii', errors='replace').strip()
                if ssid:
                    print(f"  SSID: {ssid}")
                    parts = ssid.split('_')
                    if len(parts) >= 2:
                        try:
                            dtype = int(parts[1], 16)
                            print(f"  device_type: 0x{dtype:02X} (AC)" if dtype == 0xAC else f"  device_type: 0x{dtype:02X}")
                        except ValueError:
                            pass

            # Print port from header (bytes 4-8)
            port_raw = inner[4:8]
            dev_port = struct.unpack('<I', port_raw)[0]
            print(f"  port: {dev_port}")

        print()
    except socket.timeout:
        break
    except OSError as e:
        print(f"  recv error: {e}")
        break

if not found:
    print("  No devices found.")
    print()
    print("  Troubleshooting:")
    print("  1. Verify the AC is powered on and connected to WiFi")
    print("  2. Check the IP in your router's DHCP client list")
    print("  3. Try: bash scripts/discover-midea-lan.sh (without IP)")
else:
    print("==> Done. Use device_id with 'Configure Manually' in HA.")
    print("    For V3 devices, leave token/key empty to fetch from cloud.")
PY
