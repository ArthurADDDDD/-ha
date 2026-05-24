#!/data/data/com.termux/files/usr/bin/bash
# scripts/clean.sh — 清理现有 HA 安装
# 破坏性操作，按级别逐步清理，每步需确认或带 --force
set -euo pipefail

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CONTAINER="home-assistant-core"
IMAGE="homeassistant/home-assistant:stable"
FORCE="${1:-}"

echo ""
echo "========================================="
echo "  ha-phone: 清理现有安装"
echo "========================================="
echo ""

# ── 检查是否有东西可清理 ─────────────────────────────────────────────────────
HAS_ANYTHING=false

if [ -d "$HA_BASE" ]; then
    HAS_ANYTHING=true
fi

if command -v udocker >/dev/null 2>&1; then
    source "${HA_BASE}/source.env" 2>/dev/null || true
    if udocker ps -a 2>/dev/null | grep -q "$CONTAINER"; then
        HAS_ANYTHING=true
    fi
    if udocker images 2>/dev/null | grep -q "homeassistant"; then
        HAS_ANYTHING=true
    fi
fi

if ! $HAS_ANYTHING; then
    echo "没有检测到任何 HA 安装，无需清理。"
    exit 0
fi

# ── 显示待清理内容 ──────────────────────────────────────────────────────────
echo "待清理内容:"
echo ""
[ -d "$HA_BASE" ]     && echo "  • 基项目目录 : $HA_BASE"
[ -d "$HA_CONFIG" ]   && echo "  • HA 配置    : $HA_CONFIG"

if command -v udocker >/dev/null 2>&1; then
    source "${HA_BASE}/source.env" 2>/dev/null || true
    udocker ps -a 2>/dev/null | grep -q "$CONTAINER" && echo "  • 容器       : $CONTAINER"
    udocker images 2>/dev/null | grep -q "homeassistant" && echo "  • Docker 镜像: $IMAGE"
fi

echo ""

if [ "$FORCE" != "--force" ]; then
    echo "========================================="
    echo "  警告: 此操作不可逆！"
    echo "========================================="
    echo ""
    echo "  建议先运行 scripts/check-ha.sh 确认当前状态"
    echo ""
    echo "  运行方式:"
    echo "    sh scripts/clean.sh --force   执行全部清理"
    echo ""
    echo "  或者分步执行:"
    echo "    sh scripts/clean.sh --stop     仅停止容器"
    echo "    sh scripts/clean.sh --container 停止+删除容器"
    echo "    sh scripts/clean.sh --image    停止+删除容器+删除镜像"
    echo "    sh scripts/clean.sh --all      停止+删除容器+删除镜像+备份并清空基项目"
    echo "    sh scripts/clean.sh --full     以上全部+删除 haconfig（保留备份）"
    exit 0
fi

# ── 执行清理 ─────────────────────────────────────────────────────────────────

# 确保 source.env 可用
if [ -f "${HA_BASE}/source.env" ]; then
    cd "$HA_BASE"
    source "${HA_BASE}/source.env" 2>/dev/null || true
fi

# 1. 停止容器
echo "[1/4] 停止容器 ..."
if command -v udocker >/dev/null 2>&1; then
    if udocker ps 2>/dev/null | grep -q "$CONTAINER"; then
        udocker stop "$CONTAINER" 2>/dev/null || true
        sleep 2
        echo "  ✓ 已停止"
    else
        echo "  - 容器未运行"
    fi
else
    echo "  - udocker 不可用，跳过"
fi

# 2. 删除容器
echo "[2/4] 删除容器 ..."
if command -v udocker >/dev/null 2>&1; then
    if udocker ps -a 2>/dev/null | grep -q "$CONTAINER"; then
        udocker rm -f "$CONTAINER" 2>/dev/null || true
        echo "  ✓ 已删除容器"
    else
        echo "  - 容器不存在"
    fi
else
    echo "  - udocker 不可用，跳过"
fi

# 3. 删除镜像
echo "[3/4] 删除镜像 ..."
if command -v udocker >/dev/null 2>&1; then
    if udocker images 2>/dev/null | grep -q "homeassistant"; then
        udocker rmi "$IMAGE" 2>/dev/null || true
        echo "  ✓ 已删除镜像"
    else
        echo "  - 镜像不存在"
    fi
else
    echo "  - udocker 不可用，跳过"
fi

# 4. 备份并清空基项目
echo "[4/4] 处理基项目 ..."
if [ -d "$HA_BASE" ]; then
    BAK="${HOME}/HomeAssistant-Termux.bak.$(date +%Y%m%d_%H%M%S)"

    if [ "$FORCE" = "--full" ]; then
        # 全量备份后删除
        echo "  备份整个目录 → ${BAK} ..."
        cp -a "$HA_BASE" "$BAK"
        rm -rf "$HA_BASE"
        echo "  ✓ 已备份并删除: $HA_BASE"
        echo "  备份保留在: ${BAK}"
    else
        # 保留 haconfig，只删除其他
        if [ -d "$HA_CONFIG" ]; then
            echo "  保留 haconfig（如需同时清理请用 --full）"
        fi
        # 删除除 haconfig 外的所有内容
        find "$HA_BASE" -mindepth 1 -maxdepth 1 ! -name 'haconfig' ! -name '.bak' -exec rm -rf {} + 2>/dev/null || true
        echo "  ✓ 已清理基项目（haconfig 已保留）"
    fi
else
    echo "  - 基项目目录不存在"
fi

# ── 完成 ─────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  清理完成"
echo "========================================="
echo ""
echo "  备份位置: ${HA_BASE}.bak.*"
echo ""
echo "  重新安装:"
echo "    sh scripts/install.sh"
echo ""
