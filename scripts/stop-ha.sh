#!/data/data/com.termux/files/usr/bin/bash
# scripts/stop-ha.sh — 停止 Home Assistant
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux 未找到"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || true

# 检查是否在运行
RUNNING=false
is_port_listening 8123 && RUNNING=true
if command -v udocker >/dev/null 2>&1 && udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    RUNNING=true
fi

if ! $RUNNING; then
    echo "[INFO] Home Assistant 未在运行"
    exit 0
fi

echo "正在停止 Home Assistant ..."

if command -v udocker >/dev/null 2>&1; then
    udocker stop "$CONTAINER_NAME" 2>/dev/null || true

    # 等待停止
    WAITED=0
    while [ $WAITED -lt 30 ]; do
        if ! udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            echo "[OK] Home Assistant 已停止"
            exit 0
        fi
        sleep 1
        WAITED=$((WAITED + 1))
    done

    # 超时强制
    echo "[WARN] 优雅停止超时，强制清理..."
    udocker rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

echo "[OK] 已停止"
