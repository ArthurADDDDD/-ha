#!/data/data/com.termux/files/usr/bin/bash
# scripts/check-ha.sh — 健康检查
# 输出: 容器状态 | 端口 | 日志尾部 | Xiaomi Home 状态
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CONTAINER="home-assistant-core"

echo ""
echo "========================================="
echo "  ha-phone 健康检查"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# ── 1. Termux 环境 ───────────────────────────────────────────────────────────
echo ""
echo "── 1. 运行环境 ──"
echo "   Termux       : $(termux-info 2>/dev/null | grep 'TERMUX_VERSION' | cut -d= -f2 || echo 'unknown')"
echo "   宿主          : $(getprop ro.product.model 2>/dev/null || echo 'unknown')"
echo "   Android      : $(getprop ro.build.version.release 2>/dev/null || echo 'unknown')"

# ── 2. udocker ───────────────────────────────────────────────────────────────
echo ""
echo "── 2. udocker ──"
if command -v udocker >/dev/null 2>&1; then
    echo "   udocker       : $(udocker version 2>/dev/null | head -1 || echo 'installed')"
else
    echo "   udocker       : NOT FOUND"
fi

# ── 3. 容器状态 ──────────────────────────────────────────────────────────────
echo ""
echo "── 3. 容器状态 ──"
if [ -d "$HA_BASE" ]; then
    cd "$HA_BASE"
    source "${HA_BASE}/source.env" 2>/dev/null || true

    if udocker ps -a 2>/dev/null | grep -q "$CONTAINER"; then
        CONTAINER_STATE=$(udocker ps -a 2>/dev/null | grep "$CONTAINER" | awk '{print $2}' | head -1)
        echo "   容器          : EXISTS ($CONTAINER_STATE)"
    else
        echo "   容器          : 不存在"
    fi

    # 镜像
    IMAGE="homeassistant/home-assistant:stable"
    if udocker images 2>/dev/null | grep -q "homeassistant/home-assistant"; then
        echo "   镜像          : 已拉取"
    else
        echo "   镜像          : 未拉取"
    fi
else
    echo "   基项目        : 未安装 (~/HomeAssistant-Termux 不存在)"
fi

# ── 4. 端口 ──────────────────────────────────────────────────────────────────
echo ""
echo "── 4. 网络 ──"

# 使用 Python 检查端口（Termux ss 可能不可靠）
PORT_CHECK=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
r = s.connect_ex(('127.0.0.1', 8123))
s.close()
print('LISTENING' if r == 0 else 'CLOSED')
" 2>/dev/null || echo "unknown")

echo "   8123 端口     : $PORT_CHECK"

IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
echo "   手机 IP       : ${IP}"

if [ "$PORT_CHECK" = "LISTENING" ]; then
    echo "   访问地址      : http://${IP}:8123"
fi

# ── 5. HA 最近日志 ───────────────────────────────────────────────────────────
echo ""
echo "── 5. 最近日志（最后 15 行）──"
if is_ha_running 2>/dev/null; then
    udocker logs --tail 15 "$CONTAINER" 2>/dev/null || echo "   (无法获取日志)"
else
    echo "   (HA 未运行，跳过)"
fi

# ── 6. Xiaomi Home 集成 ──────────────────────────────────────────────────────
echo ""
echo "── 6. Xiaomi Home 集成 ──"
XIAOMI_DIR="${HA_CONFIG}/custom_components/xiaomi_home"
if [ -d "$XIAOMI_DIR" ]; then
    echo "   目录          : 存在"
    MANIFEST="${XIAOMI_DIR}/manifest.json"
    if [ -f "$MANIFEST" ]; then
        # 用 python3 解析 JSON 获取版本
        VER=$(python3 -c "
import json
with open('$MANIFEST') as f:
    d = json.load(f)
print(d.get('version', 'unknown'))
" 2>/dev/null || echo "parse_error")
        echo "   版本          : ${VER}"

        # 检查 manifest.json 是否合法
        python3 -c "import json; json.load(open('$MANIFEST'))" 2>/dev/null && \
            echo "   manifest.json : 合法" || \
            echo "   manifest.json : 损坏！运行 reinstall-xiaomi-home.sh"
    else
        echo "   状态          : 目录存在但无 manifest.json（损坏）"
    fi
else
    echo "   状态          : 未安装"
fi

# ── 7. HA 版本 ───────────────────────────────────────────────────────────────
echo ""
echo "── 7. 版本信息 ──"
if is_ha_running 2>/dev/null; then
    HA_VER=$(udocker run --entrypoint "bash -c" "$CONTAINER" "python3 -m homeassistant --version" 2>/dev/null || echo "unknown")
    PY_VER=$(udocker run --entrypoint "bash -c" "$CONTAINER" "python3 --version" 2>/dev/null || echo "unknown")
    echo "   HA 版本       : ${HA_VER}"
    echo "   Python 版本   : ${PY_VER}"
else
    echo "   (HA 未运行，无法获取版本)"
fi

# ── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  检查完毕"
echo "─────────────────────────────────────────"

# 快速状态总结
if [ "$PORT_CHECK" = "LISTENING" ] && [ -d "$XIAOMI_DIR" ]; then
    echo "  状态: 一切正常 ✓"
elif [ "$PORT_CHECK" = "LISTENING" ]; then
    echo "  状态: HA 运行中，但 Xiaomi Home 未安装"
elif [ -d "$XIAOMI_DIR" ]; then
    echo "  状态: HA 未运行，但 Xiaomi Home 已部署"
else
    echo "  状态: 需要运行 scripts/install.sh"
fi
echo ""
