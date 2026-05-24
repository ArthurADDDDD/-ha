#!/data/data/com.termux/files/usr/bin/bash
# scripts/start-ha.sh — 启动 Home Assistant
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

HA_BASE="${HOME}/HomeAssistant-Termux"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux 未找到，请先运行 scripts/install.sh"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env"

if is_ha_running 2>/dev/null; then
    echo "[INFO] Home Assistant 已在运行中"
    echo ""
    echo "  访问: http://$(hostname -I 2>/dev/null | awk '{print $1}'):8123"
    exit 0
fi

echo "正在启动 Home Assistant ..."

# 设置端口
export PORT="${PORT:-8123}"

# 确保 haconfig 存在
mkdir -p "${HA_BASE}/haconfig"

# 启动
bash "${HA_BASE}/home-assistant-core.sh" &
HA_PID=$!

# 等待端口就绪
echo "等待 HA 启动（端口 8123）..."
WAITED=0
while [ $WAITED -lt 120 ]; do
    if ss -tlnp 2>/dev/null | grep -q ":8123 "; then
        echo ""
        echo "[OK] Home Assistant 已启动！"
        echo ""
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo "  访问: http://${IP}:8123"
        echo "  PID:   ${HA_PID}"
        exit 0
    fi
    sleep 2
    WAITED=$((WAITED + 2))
    printf "."
done

echo ""
echo "[WARN] 等待超时（120s），8123 端口仍未监听"
echo "  请手动检查: udocker ps"
echo "  查看日志:   udocker logs home-assistant-core"
echo "  HA 可能仍在启动中（大镜像首次启动较慢）"
exit 1
