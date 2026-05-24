#!/data/data/com.termux/files/usr/bin/bash
# scripts/stop-ha.sh - stop Home Assistant gracefully
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

FORCE_REMOVE=0
if [ "${1:-}" = "--force" ]; then
    FORCE_REMOVE=1
fi

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux not found"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || true

RUNNING=false
is_port_listening 8123 && RUNNING=true
if command -v udocker >/dev/null 2>&1 && udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    RUNNING=true
fi

if ! $RUNNING; then
    echo "[INFO] Home Assistant is not running"
    exit 0
fi

echo "[INFO] Stopping Home Assistant ..."

if command -v udocker >/dev/null 2>&1; then
    udocker stop "$CONTAINER_NAME" 2>/dev/null || true

    WAITED=0
    while [ "$WAITED" -lt 30 ]; do
        if ! udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            echo "[OK] Home Assistant stopped"
            exit 0
        fi
        sleep 1
        WAITED=$((WAITED + 1))
    done

    echo "[WARN] Graceful stop timed out; container may still be running"
    if [ "$FORCE_REMOVE" -eq 1 ]; then
        echo "[WARN] --force enabled, removing container ${CONTAINER_NAME} ..."
        udocker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    else
        echo "[INFO] To force-remove container, run: bash scripts/stop-ha.sh --force"
    fi
fi

if command -v udocker >/dev/null 2>&1 && udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    echo "[WARN] Home Assistant is still running"
    exit 2
fi

echo "[OK] Home Assistant stopped"
