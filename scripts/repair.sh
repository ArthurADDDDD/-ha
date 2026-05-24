#!/data/data/com.termux/files/usr/bin/bash
# scripts/repair.sh — 修复 HA 安装
# 使用场景: 镜像丢/容器坏/补丁丢/集成丢
# 非破坏：不清空配置，不做全量重装
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"

echo ""
echo "========================================="
echo "  ha-phone: 修复模式"
echo "========================================="
echo ""

# ── 0. 环境检查 ─────────────────────────────────────────────────────────────
if [ ! -d "/data/data/com.termux" ]; then
    echo "[ERROR] 请在 Termux 中运行此脚本"
    exit 1
fi

# ── 1. 基项目存在性 ─────────────────────────────────────────────────────────
echo "── 1. 检查基项目 ──"
if [ ! -d "$HA_BASE" ]; then
    echo "  [WARN] HomeAssistant-Termux 不存在，重新克隆..."
    "$REPO_DIR/bootstrap/02_clone_base.sh"
fi

# ── 2. 补丁完整性 ───────────────────────────────────────────────────────────
echo ""
echo "── 2. 检查补丁 ──"
"$REPO_DIR/bootstrap/03_patch_base.sh"

# ── 3. udocker 可用性 ───────────────────────────────────────────────────────
echo ""
echo "── 3. 检查 udocker ──"
cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || {
    echo "  [ERROR] 无法 source source.env"
    exit 1
}

if command -v udocker >/dev/null 2>&1; then
    echo "  ✓ udocker 可用"
    fix_udocker 2>/dev/null || true
else
    echo "  [WARN] udocker 不可用，重新安装..."
    install_udocker
    fix_udocker
    echo "  ✓ udocker 已修复"
fi

# ── 4. 镜像检查 ─────────────────────────────────────────────────────────────
echo ""
echo "── 4. 检查 Docker 镜像 ──"
IMAGE="homeassistant/home-assistant:stable"
if udocker images 2>/dev/null | grep -q "homeassistant/home-assistant"; then
    echo "  ✓ 镜像已存在"
else
    echo "  [WARN] 镜像丢失，重新拉取..."
    for i in 1 2 3; do
        echo "  尝试 $i/3 ..."
        if udocker pull --platform=linux/arm64 "$IMAGE" 2>&1; then
            echo "  ✓ 镜像拉取成功"
            break
        else
            if [ $i -eq 3 ]; then
                echo "  [ERROR] 镜像拉取失败，请检查网络后重试"
                exit 1
            fi
            sleep $((i * 10))
        fi
    done
fi

# ── 5. 容器检查 ─────────────────────────────────────────────────────────────
echo ""
echo "── 5. 检查容器 ──"
CONTAINER="home-assistant-core"
if udocker ps -a 2>/dev/null | grep -q "$CONTAINER"; then
    echo "  ✓ 容器存在"
    if udocker ps 2>/dev/null | grep -q "$CONTAINER"; then
        echo "  ✓ 容器正在运行"
    else
        echo "  (容器存在但未运行)"
    fi
else
    echo "  [WARN] 容器不存在，重新创建..."
    udocker_create "$CONTAINER" "$IMAGE" || {
        echo "  [ERROR] 容器创建失败"
        echo "  尝试清理残留后重建..."
        udocker rm -f "$CONTAINER" 2>/dev/null || true
        udocker_create "$CONTAINER" "$IMAGE" || {
            echo "  [ERROR] 仍失败，请检查 udocker 状态"
            exit 1
        }
    }
    echo "  ✓ 容器已重建（haconfig 未受影响）"
fi

# ── 6. haconfig ──────────────────────────────────────────────────────────────
echo ""
echo "── 6. 检查配置 ──"
mkdir -p "$HA_CONFIG"
if [ -f "$HA_CONFIG/configuration.yaml" ]; then
    echo "  ✓ configuration.yaml 存在"
else
    echo "  [WARN] configuration.yaml 丢失，重新部署..."
    cp "$REPO_DIR/config/configuration.yaml" "$HA_CONFIG/configuration.yaml"
    echo "  ✓ 已恢复"
fi

# ── 7. Xiaomi Home ──────────────────────────────────────────────────────────
echo ""
echo "── 7. 检查 Xiaomi Home ──"
XIAOMI_DIR="${HA_CONFIG}/custom_components/xiaomi_home"
if [ -d "$XIAOMI_DIR" ] && [ -f "${XIAOMI_DIR}/manifest.json" ]; then
    echo "  ✓ Xiaomi Home 已安装"
else
    echo "  [WARN] Xiaomi Home 缺失，重新部署..."
    "$REPO_DIR/scripts/reinstall-xiaomi-home.sh"
fi

# ── 完成 ─────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  修复完成"
echo "========================================="
echo ""
echo "  运行 scripts/start-ha.sh 启动 HA"
echo "  运行 scripts/check-ha.sh 确认状态"
echo ""
