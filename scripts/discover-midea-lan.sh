#!/data/data/com.termux/files/usr/bin/bash
# scripts/discover-midea-lan.sh - targeted Midea device discovery from Termux
# Usage: bash scripts/discover-midea-lan.sh <IP_ADDRESS>
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: bash scripts/discover-midea-lan.sh <IP_ADDRESS>"
    echo "Example: bash scripts/discover-midea-lan.sh 192.168.50.100"
    exit 1
fi

TARGET_IP="$1"

python3 - "$TARGET_IP" <<'PY'
import socket
import sys
import struct

TARGET = sys.argv[1]
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

print(f"==> Targeted Midea discovery to {TARGET}")
print()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(5)

try:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
except OSError:
    pass

for port in PORTS:
    try:
        sock.sendto(BROADCAST_MSG, (TARGET, port))
        print(f"  [SEND] {TARGET}:{port}")
    except OSError as e:
        print(f"  [FAIL] sendto {TARGET}:{port}: {e}")

print()
print("  Waiting for response (5s timeout)...")
print()

found = False
while True:
    try:
        data, addr = sock.recvfrom(1024)
        found = True
        print(f"--- Response from {addr[0]}:{addr[1]} ({len(data)} bytes) ---")
        print(f"  hex: {data.hex()}")

        header = data[:2]
        if header == b'\x5a\x5a':
            version = 2
        elif header == b'\x83\x70':
            version = 3
        else:
            version = "unknown"

        print(f"  version: {version}")

        # Try to extract device_id from unencrypted header
        if version == 2:
            device_id_raw = data[20:26]
            device_id = int.from_bytes(device_id_raw, 'little')
            print(f"  device_id (from header): {device_id}")
        elif version == 3:
            inner = data[8:]
            if inner[:2] == b'\x5a\x5a':
                device_id_raw = inner[20:26]
                device_id = int.from_bytes(device_id_raw, 'little')
                print(f"  device_id (from V3 inner header): {device_id}")
                print(f"  inner hex: {inner.hex()}")

        # Try to extract SN from unencrypted portion
        if version in (2, 3):
            payload = data if version == 2 else data[8:]
            sn_bytes = payload[8:40]
            sn = sn_bytes.decode('ascii', errors='replace').strip('\x00').strip()
            print(f"  SN: {sn}")

        print()
    except socket.timeout:
        break
    except OSError as e:
        print(f"  recv error: {e}")
        break

if not found:
    print("  No response received. Device may be offline or on a different subnet.")
else:
    print("==> Done. Use device_id above with Configure Manually.")
    print("    For V3 devices, token/key can be left empty — config flow will fetch from cloud.")
PY
