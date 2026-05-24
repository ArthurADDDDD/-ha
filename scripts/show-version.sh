#!/data/data/com.termux/files/usr/bin/bash
# scripts/show-version.sh — 显示版本信息
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CONTAINER="home-assistant-core"

echo ""
echo "========================================="
echo "  ha-phone 版本信息"
echo "========================================="
echo ""

# HA 版本
if [ -d "$HA_BASE" ]; then
    cd "$HA_BASE"
    source "${HA_BASE}/source.env" 2>/dev/null || true

    if is_ha_running 2>/dev/null; then
        echo "  HA 版本       : $(udocker run --entrypoint 'bash -c' "$CONTAINER" 'python3 -m homeassistant --version' 2>/dev/null || echo 'unknown')"
        echo "  Python 版本   : $(udocker run --entrypoint 'bash -c' "$CONTAINER" 'python3 --version' 2>/dev/null || echo 'unknown')"
    else
        echo "  HA 版本       : (HA 未运行)"
        echo "  Python 版本   : (HA 未运行)"
    fi

    echo "  Docker 镜像   : $(udocker images 2>/dev/null | grep homeassistant | awk '{print $2}' || echo 'unknown')"
else
    echo "  HA 版本       : 未安装"
fi

# udocker
if command -v udocker >/dev/null 2>&1; then
    echo "  udocker       : $(udocker version 2>/dev/null | head -1 || echo 'installed')"
else
    echo "  udocker       : 未安装"
fi

# Xiaomi Home
XIAOMI_DIR="${HA_CONFIG}/custom_components/xiaomi_home"
if [ -f "${XIAOMI_DIR}/manifest.json" ]; then
    XIAOMI_VER=$(python3 -c "
import json
with open('${XIAOMI_DIR}/manifest.json') as f:
    d = json.load(f)
print(d.get('version', 'unknown'))
" 2>/dev/null || echo "parse_error")
    echo "  Xiaomi Home   : ${XIAOMI_VER}"
else
    echo "  Xiaomi Home   : 未安装"
fi

# 系统
echo "  Termux        : $(termux-info 2>/dev/null | grep 'TERMUX_VERSION' | cut -d= -f2 || echo 'unknown')"
echo "  Android       : $(getprop ro.build.version.release 2>/dev/null || echo 'unknown')"
echo "  宿主          : $(getprop ro.product.model 2>/dev/null || echo 'unknown')"

# 仓库版本
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -d "${REPO_DIR}/.git" ]; then
    echo "  ha-phone repo : $(cd "$REPO_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
fi

echo ""
