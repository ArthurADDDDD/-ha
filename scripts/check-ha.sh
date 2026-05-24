#!/data/data/com.termux/files/usr/bin/bash
# scripts/check-ha.sh — 健康检查
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

echo ""
echo "========================================="
echo "  ha-phone 健康检查"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="

# ── 1. 运行环境 ──────────────────────────────────────────────────────────
echo ""
echo "── 1. 运行环境 ──"
echo "   Termux       : $(termux-info 2>/dev/null | grep 'TERMUX_VERSION' | cut -d= -f2 || echo 'unknown')"
echo "   宿主          : $(getprop ro.product.model 2>/dev/null || echo 'unknown')"
echo "   Android      : $(getprop ro.build.version.release 2>/dev/null || echo 'unknown')"

# ── 2. udocker ────────────────────────────────────────────────────────────
echo ""
echo "── 2. udocker ──"
if command -v udocker >/dev/null 2>&1; then
    echo "   udocker       : $(udocker version 2>/dev/null | head -1 || echo 'installed')"
else
    echo "   udocker       : NOT FOUND"
fi

# ── 3. 容器 + 镜像 ────────────────────────────────────────────────────────
echo ""
echo "── 3. 容器状态 ──"
if [ -d "$HA_BASE" ]; then
    cd "$HA_BASE"
    source "${HA_BASE}/source.env" 2>/dev/null || true

    # 运行中的容器
    if command -v udocker >/dev/null 2>&1; then
        if udocker ps 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            echo "   容器状态      : RUNNING"
        elif udocker ps -a 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            echo "   容器状态      : STOPPED"
        else
            echo "   容器状态      : 不存在"
        fi

        if udocker images 2>/dev/null | grep -q "homeassistant/home-assistant"; then
            echo "   镜像          : 已拉取"
        else
            echo "   镜像          : 未拉取"
        fi
    else
        echo "   容器状态      : udocker 不可用"
    fi
else
    echo "   基项目        : 未安装"
fi

# ── 4. 网络 ───────────────────────────────────────────────────────────────
echo ""
echo "── 4. 网络 ──"
IP=$(get_lan_ip)
echo "   手机 IP       : ${IP}"

if is_port_listening 8123; then
    echo "   8123 端口     : LISTENING"
    echo "   访问地址      : http://${IP}:8123"
else
    echo "   8123 端口     : CLOSED"
fi

# ── 5. 日志（尝试多种方式）────────────────────────────────────────────────
echo ""
echo "── 5. 最近日志（最后 15 行）──"

LOG_FOUND=false

# 方法1: udocker logs（容器存在时可用）
if command -v udocker >/dev/null 2>&1 && udocker ps -a 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    udocker logs --tail 15 "$CONTAINER_NAME" 2>/dev/null && LOG_FOUND=true
fi

# 方法2: home-assistant.log 文件
if ! $LOG_FOUND && [ -f "${HA_CONFIG}/home-assistant.log" ]; then
    tail -15 "${HA_CONFIG}/home-assistant.log" 2>/dev/null && LOG_FOUND=true
fi

if ! $LOG_FOUND; then
    echo "   (日志不可用)"
fi

# ── 6. Xiaomi Home ────────────────────────────────────────────────────────
echo ""
echo "── 6. Xiaomi Home 集成 ──"
XIAOMI_DIR="${HA_CONFIG}/custom_components/xiaomi_home"
if [ -d "$XIAOMI_DIR" ]; then
    echo "   目录          : 存在"
    MANIFEST="${XIAOMI_DIR}/manifest.json"
    if [ -f "$MANIFEST" ]; then
        VER=$(python3 -c "
import json
with open('$MANIFEST') as f:
    d = json.load(f)
print(d.get('version', 'unknown'))
" 2>/dev/null || echo "parse_error")
        echo "   版本          : ${VER}"

        python3 -c "import json; json.load(open('$MANIFEST'))" 2>/dev/null && \
            echo "   manifest.json : 合法" || \
            echo "   manifest.json : 损坏！运行 reinstall-xiaomi-home.sh"
    else
        echo "   状态          : 目录存在但无 manifest.json（损坏）"
    fi
else
    echo "   状态          : 未安装"
fi

# ── 7. 版本（从 home-assistant.log 读取，不创建容器）────────────────────
echo ""
echo "── 7. 版本信息 ──"

# 从启动日志解析版本（不创建容器）
LOG_FILE="${HA_CONFIG}/home-assistant.log"
if [ -f "$LOG_FILE" ]; then
    HA_VER=$(sed -n 's/.*Home Assistant \([0-9.]*\).*/\1/p' "$LOG_FILE" 2>/dev/null | tail -1)
    PY_VER=$(sed -n 's/.*Python \([0-9.]*\).*/\1/p' "$LOG_FILE" 2>/dev/null | tail -1)
    [ -n "$HA_VER" ] && echo "   HA 版本       : ${HA_VER}" || echo "   HA 版本       : (无法从日志解析)"
    [ -n "$PY_VER" ] && echo "   Python 版本   : ${PY_VER}" || echo "   Python 版本   : (无法从日志解析)"
else
    # 备选：从容器镜像标签推断
    if command -v udocker >/dev/null 2>&1; then
        IMG_TAG=$(udocker images 2>/dev/null | grep homeassistant | awk '{print $2}' | head -1)
        [ -n "$IMG_TAG" ] && echo "   Docker 镜像   : ${IMG_TAG}" || echo "   Docker 镜像   : 未知"
    fi
    echo "   日志文件      : 不存在（HA 可能从未成功启动过）"
fi

# ── 汇总 ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  检查完毕"
echo "─────────────────────────────────────────"

PORT_OK=$(is_port_listening 8123 && echo 1 || echo 0)
XIAOMI_OK=$([ -d "$XIAOMI_DIR" ] && [ -f "${XIAOMI_DIR}/manifest.json" ] && echo 1 || echo 0)

if [ "$PORT_OK" = "1" ] && [ "$XIAOMI_OK" = "1" ]; then
    echo "  状态: 一切正常"
elif [ "$PORT_OK" = "1" ]; then
    echo "  状态: HA 运行中，Xiaomi Home 未安装"
elif [ "$XIAOMI_OK" = "1" ]; then
    echo "  状态: HA 未运行，Xiaomi Home 已部署 → 运行 scripts/start-ha.sh"
else
    echo "  状态: 需要运行 scripts/install.sh"
fi
echo ""
