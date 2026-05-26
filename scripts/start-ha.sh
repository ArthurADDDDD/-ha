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

# Kill all HA-related processes and remove the lock file
_kill_ha() {
    pkill -f "home-assistant-core.sh" 2>/dev/null || true
    pkill -f "udocker.*${CONTAINER_NAME}" 2>/dev/null || true
    pkill -f "python3 -m homeassistant" 2>/dev/null || true
    rm -f "${HA_CONFIG}/.ha_run.lock"
}

if is_port_listening 8123 || pgrep -f "home-assistant-core.sh" >/dev/null 2>&1 || \
   pgrep -f "udocker.*${CONTAINER_NAME}" >/dev/null 2>&1 || \
   pgrep -f "python3 -m homeassistant" >/dev/null 2>&1; then
    echo "[INFO] Existing HA instance detected, killing old process before start ..."
    _kill_ha

    for _ in {1..12}; do
        if ! is_port_listening 8123; then
            break
        fi
        sleep 1
    done

    if is_port_listening 8123; then
        echo "[WARN] Port 8123 still busy, sending SIGKILL ..."
        pkill -9 -f "home-assistant-core.sh" 2>/dev/null || true
        pkill -9 -f "udocker.*${CONTAINER_NAME}" 2>/dev/null || true
        pkill -9 -f "python3 -m homeassistant" 2>/dev/null || true
        rm -f "${HA_CONFIG}/.ha_run.lock"
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

# patch-xiaomi-home always runs: it self-checks Patch F IP on every start.
# Warn if configuration.yaml still has template placeholders
if grep -q 'YOUR_PROJECT_ID' "${HA_CONFIG}/configuration.yaml" 2>/dev/null; then
    log_warn "configuration.yaml has unreplaced placeholders, Google Home bridge will fail"
fi

bash "${SCRIPT_DIR}/patch-xiaomi-home.sh" || log_warn "patch-xiaomi-home.sh failed, continue"

# patch-container + patch-midea are gated by a stamp file to avoid
# re-scanning the container lib on every start.
PATCH_STAMP="${HA_BASE}/.ha_patch_stamp"
_patches_need_run() {
    [ -f "$PATCH_STAMP" ] || return 0
    for f in "${SCRIPT_DIR}/patch-container.sh" "${SCRIPT_DIR}/patch-midea.sh"; do
        [ "$f" -nt "$PATCH_STAMP" ] && return 0
    done
    for d in "${HA_CONFIG}/custom_components/midea_ac_lan" \
             "${HA_CONFIG}/custom_components/midea_lan"; do
        [ -d "$d" ] && [ "$d" -nt "$PATCH_STAMP" ] && return 0
    done
    return 1
}
if _patches_need_run; then
    bash "${SCRIPT_DIR}/patch-container.sh" || log_warn "patch-container.sh failed, continue"
    bash "${SCRIPT_DIR}/patch-midea.sh"     || log_warn "patch-midea.sh failed, continue"
    touch "$PATCH_STAMP"
else
    log_info "Container/midea patches up to date, skipping"
fi

echo ""
echo "========================================="
echo "  Starting Home Assistant ..."
echo "  Waiting for log line: on 0.0.0.0:8123"
echo "  Press Ctrl+C to stop Home Assistant"
echo "========================================="
echo ""

# Termux/proot often forbids hardlink in uv build cache; force copy mode to avoid
# "Operation not permitted (os error 1)" when HA installs integration requirements.
export UV_LINK_MODE=copy
export UV_NO_CACHE=1

_stop_ha() {
    echo ""
    log_info "Stopping Home Assistant ..."
    _kill_ha
}
trap _stop_ha INT TERM

bash "${HA_BASE}/home-assistant-core.sh"
trap - INT TERM
