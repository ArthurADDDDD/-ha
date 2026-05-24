#!/data/data/com.termux/files/usr/bin/bash
# scripts/stop-ha.sh — 停止 Home Assistant
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

HA_BASE="${HOME}/HomeAssistant-Termux"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux 未找到"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || true

if ! is_ha_running 2>/dev/null; then
    echo "[INFO] Home Assistant 未在运行"
    exit 0
fi

echo "正在停止 Home Assistant ..."

# 优雅停止
CONTAINER="home-assistant-core"
udocker stop "$CONTAINER" 2>/dev/null || true

# 等待停止
WAITED=0
while [ $WAITED -lt 30 ]; do
    if ! udocker ps 2>/dev/null | grep -q "$CONTAINER"; then
        echo "[OK] Home Assistant 已停止"
        exit 0
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

# 超时强制清理
echo "[WARN] 优雅停止超时，强制清理容器..."
udocker rm -f "$CONTAINER" 2>/dev/null || true
echo "[OK] 已强制停止"
