#!/data/data/com.termux/files/usr/bin/bash
# scripts/stop-ha.sh - best-effort stop without blocking
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux not found"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || true

if ! is_port_listening 8123 && ! pgrep -f "home-assistant-core.sh" >/dev/null 2>&1 && ! pgrep -f "udocker.*${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "[INFO] Home Assistant is not running"
    exit 0
fi

echo "[INFO] Stopping Home Assistant process ..."
pkill -f "home-assistant-core.sh" >/dev/null 2>&1 || true
pkill -f "udocker.*${CONTAINER_NAME}" >/dev/null 2>&1 || true

for _ in {1..12}; do
    if ! is_port_listening 8123; then
        echo "[OK] Home Assistant stopped"
        exit 0
    fi
    sleep 1
done

echo "[WARN] Graceful stop timed out, forcing kill ..."
pkill -9 -f "home-assistant-core.sh" >/dev/null 2>&1 || true
pkill -9 -f "udocker.*${CONTAINER_NAME}" >/dev/null 2>&1 || true
sleep 1

if is_port_listening 8123; then
    echo "[WARN] Port 8123 is still busy. Please run:"
    echo "       ps -ef | grep -E 'home-assistant-core|udocker' | grep -v grep"
    exit 2
fi

echo "[OK] Home Assistant stopped"
