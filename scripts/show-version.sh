#!/data/data/com.termux/files/usr/bin/bash
# scripts/show-version.sh — 显示版本信息
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

echo ""
echo "========================================="
echo "  ha-phone 版本信息"
echo "========================================="
echo ""

# HA 版本（从日志读取）
LOG_FILE="${HA_CONFIG}/home-assistant.log"
if [ -f "$LOG_FILE" ]; then
    HA_VER=$(sed -n 's/.*Home Assistant \([0-9.]*\).*/\1/p' "$LOG_FILE" 2>/dev/null | tail -1)
    PY_VER=$(sed -n 's/.*Python \([0-9.]*\).*/\1/p' "$LOG_FILE" 2>/dev/null | tail -1)
    [ -n "$HA_VER" ] && echo "  HA 版本       : ${HA_VER}" || echo "  HA 版本       : 未知"
    [ -n "$PY_VER" ] && echo "  Python 版本   : ${PY_VER}" || echo "  Python 版本   : 未知"
else
    echo "  HA 版本       : 未知（日志文件不存在）"
    echo "  Python 版本   : 未知"
fi

# 镜像标签
if command -v udocker >/dev/null 2>&1; then
    source "${HA_BASE}/source.env" 2>/dev/null || true
    IMG_TAG=$(udocker images 2>/dev/null | grep homeassistant | awk '{print $2}' | head -1)
    [ -n "$IMG_TAG" ] && echo "  Docker 镜像   : ${IMG_TAG}"
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

# Midea
if [ -d "${HA_CONFIG}/custom_components/midea_ac" ]; then
    MIDEA_DIR="${HA_CONFIG}/custom_components/midea_ac"
elif [ -d "${HA_CONFIG}/custom_components/midea_ac_lan" ]; then
    MIDEA_DIR="${HA_CONFIG}/custom_components/midea_ac_lan"
elif [ -d "${HA_CONFIG}/custom_components/midea_lan" ]; then
    MIDEA_DIR="${HA_CONFIG}/custom_components/midea_lan"
else
    MIDEA_DIR=""
fi

if [ -n "$MIDEA_DIR" ] && [ -f "${MIDEA_DIR}/manifest.json" ]; then
    MIDEA_VER=$(python3 -c "
import json
with open('${MIDEA_DIR}/manifest.json') as f:
    d = json.load(f)
print(d.get('version', 'unknown'))
" 2>/dev/null || echo "parse_error")
    echo "  Midea LAN     : ${MIDEA_VER} ($(basename "$MIDEA_DIR"))"
else
    echo "  Midea LAN     : 未安装"
fi

# 系统
echo "  Termux        : $(termux-info 2>/dev/null | grep 'TERMUX_VERSION' | cut -d= -f2 || echo 'unknown')"
echo "  Android       : $(getprop ro.build.version.release 2>/dev/null || echo 'unknown')"
echo "  宿主          : $(getprop ro.product.model 2>/dev/null || echo 'unknown')"
echo "  IP            : $(get_lan_ip)"

# 仓库版本
if [ -d "${SCRIPT_DIR}/../.git" ]; then
    echo "  ha-phone repo : $(cd "${SCRIPT_DIR}/.." && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
fi

echo ""
