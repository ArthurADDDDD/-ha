#!/data/data/com.termux/files/usr/bin/bash
# scripts/start-ha.sh — 启动 Home Assistant
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux 未找到，请先运行 scripts/install.sh"
    exit 1
fi

cd "$HA_BASE"

# 先检查端口（最可靠）
if is_port_listening 8123; then
    echo "[INFO] Home Assistant 已在运行中（端口 8123 已监听）"
    echo ""
    echo "  访问: http://$(get_lan_ip):8123"
    exit 0
fi

# 再检查 udocker 容器
if command -v udocker >/dev/null 2>&1; then
    source "${HA_BASE}/source.env" 2>/dev/null || true
    if udocker ps 2>/dev/null | grep -q "home-assistant-core"; then
        echo "[INFO] 容器存在但端口未监听，可能在启动中..."
        echo "  稍后访问: http://$(get_lan_ip):8123"
        exit 0
    fi
fi

echo "正在启动 Home Assistant ..."

# 加载 udocker 环境
source "${HA_BASE}/source.env" 2>/dev/null || {
    echo "[ERROR] 无法加载 source.env，请运行 scripts/install.sh"
    exit 1
}

export PORT="${PORT:-8123}"
mkdir -p "${HA_BASE}/haconfig"

# 检查容器是否存在
if ! udocker ps -a 2>/dev/null | grep -q "home-assistant-core"; then
    echo "[INFO] 容器不存在，正在创建..."
    udocker_create "$CONTAINER_NAME" "$IMAGE_NAME" || {
        echo "[ERROR] 容器创建失败，运行 scripts/repair.sh"
        exit 1
    }
fi

# 启动
bash "${HA_BASE}/home-assistant-core.sh" &
HA_PID=$!

echo "等待 HA 启动（端口 8123）..."
WAITED=0
while [ $WAITED -lt 180 ]; do
    if is_port_listening 8123; then
        echo ""
        echo "[OK] Home Assistant 已启动！"
        echo ""
        echo "  访问: http://$(get_lan_ip):8123"
        exit 0
    fi
    sleep 3
    WAITED=$((WAITED + 3))
    printf "."
done

echo ""
echo "[WARN] 等待超时（180s）"
echo "  检查容器日志: udocker logs home-assistant-core"
echo "  修复:            sh scripts/repair.sh"
exit 1
