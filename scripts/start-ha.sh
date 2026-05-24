#!/data/data/com.termux/files/usr/bin/bash
# scripts/start-ha.sh - start Home Assistant in foreground
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

if is_port_listening 8123; then
    echo "[INFO] Home Assistant is already running on port 8123"
    echo "  URL: http://$(get_lan_ip):8123"
    echo "  Logs: udocker logs -f ${CONTAINER_NAME}"
    exit 0
fi

# If this is the first run and container ROOT is absent, pre-create once.
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
echo "  Press Ctrl+C to stop"
echo "========================================="
echo ""

cleanup_on_interrupt() {
    trap - INT TERM
    echo ""
    log_warn "Interrupt received, stopping Home Assistant ..."
    bash "${SCRIPT_DIR}/stop-ha.sh" || true
    exit 130
}

trap cleanup_on_interrupt INT TERM

bash "${HA_BASE}/home-assistant-core.sh" &
HA_BOOT_PID=$!
wait "$HA_BOOT_PID"
EXIT_CODE=$?
trap - INT TERM
exit "$EXIT_CODE"
