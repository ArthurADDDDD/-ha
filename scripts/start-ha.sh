#!/data/data/com.termux/files/usr/bin/bash
# scripts/start-ha.sh - start Home Assistant in foreground (simple mode)
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux not found, run scripts/install.sh first"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || {
    echo "[ERROR] Cannot load source.env, run scripts/install.sh first"
    exit 1
}

# Restart mode: if a stale/running instance exists, kill it first then continue startup.
if command -v udocker >/dev/null 2>&1; then
    if is_port_listening 8123 || udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
        echo "[INFO] Existing HA instance detected, stopping it before start ..."
        timeout 12 udocker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        if udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            echo "[WARN] Graceful stop did not finish, force-removing container ..."
            udocker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi
        sleep 1
    fi
fi

if command -v udocker_create >/dev/null 2>&1; then
    if [ ! -d "${HOME}/.udocker/containers/${CONTAINER_NAME}/ROOT" ]; then
        echo "[INFO] First start: pre-creating container ${CONTAINER_NAME} ..."
        udocker_check || true
        udocker_create "${CONTAINER_NAME}" "${IMAGE_NAME}" || true
    fi
fi

bash "${SCRIPT_DIR}/patch-container.sh" || log_warn "patch-container.sh failed, continue"
bash "${SCRIPT_DIR}/patch-xiaomi-home.sh" || log_warn "patch-xiaomi-home.sh failed, continue"
bash "${SCRIPT_DIR}/patch-midea.sh" || log_warn "patch-midea.sh failed, continue"

echo ""
echo "========================================="
echo "  Starting Home Assistant ..."
echo "  Waiting for log line: on 0.0.0.0:8123"
echo "  Press Ctrl+C to interrupt foreground logs"
echo "========================================="
echo ""

exec bash "${HA_BASE}/home-assistant-core.sh"
