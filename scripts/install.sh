#!/data/data/com.termux/files/usr/bin/bash
# scripts/install.sh — 一键安装 / 初始化 ha-phone
# 幂等：可安全重复执行
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 环境检查 ─────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  ha-phone: Home Assistant 手机部署"
echo "  主机: Sony Xperia 1 III / Termux"
echo "  目标: HA + Xiaomi Home 集成"
echo "========================================="
echo ""

if [ ! -d "/data/data/com.termux" ]; then
    echo "[ERROR] 请在 Termux 中运行此脚本"
    exit 1
fi

# ── 使脚本可执行 ─────────────────────────────────────────────────────────────
chmod +x "$REPO_DIR"/bootstrap/*.sh 2>/dev/null || true
chmod +x "$REPO_DIR"/scripts/*.sh 2>/dev/null || true

# ── Step 1: 基础包 ───────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Step 1/6: 安装基础包"
echo "─────────────────────────────────────────"
"$REPO_DIR/bootstrap/01_termux_pkgs.sh" || {
    echo "[WARN] 部分包安装失败，继续后续步骤..."
}

# ── Step 2: 拉取/更新基项目 ──────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Step 2/6: 同步 HomeAssistant-Termux"
echo "─────────────────────────────────────────"
"$REPO_DIR/bootstrap/02_clone_base.sh" || {
    echo "[ERROR] 基项目同步失败"
    exit 1
}

# ── Step 3: 打补丁 ───────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Step 3/6: 打补丁"
echo "─────────────────────────────────────────"
"$REPO_DIR/bootstrap/03_patch_base.sh" || {
    echo "[ERROR] 打补丁失败"
    exit 1
}

# ── Step 4: 配置 haconfig ────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Step 4/6: 准备 haconfig"
echo "─────────────────────────────────────────"
HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
mkdir -p "$HA_CONFIG"

# configuration.yaml
if [ -f "$HA_CONFIG/configuration.yaml" ]; then
    echo "  ▶ configuration.yaml 已存在，跳过（如需覆盖请手动删除）"
else
    cp "$REPO_DIR/config/configuration.yaml" "$HA_CONFIG/configuration.yaml"
    echo "  ✓ configuration.yaml 已部署"
fi

# ── Step 5: Xiaomi Home 集成 ─────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Step 5/6: 部署 Xiaomi Home 集成"
echo "─────────────────────────────────────────"
"$REPO_DIR/scripts/reinstall-xiaomi-home.sh" || {
    echo "[WARN] Xiaomi Home 部署失败（HA 启动后仍可手动重装）"
}

# ── Step 6: 初始化 udocker + 拉取镜像 ────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Step 6/6: 初始化 udocker 环境"
echo "─────────────────────────────────────────"

cd "$HA_BASE"

# 加载 source.env
source "${HA_BASE}/source.env" 2>/dev/null || {
    echo "[ERROR] 无法 source source.env"
    exit 1
}

# 安装/修复 udocker
echo "  ▶ 检查 udocker ..."
if command -v udocker >/dev/null 2>&1; then
    echo "  ✓ udocker 已安装"
    fix_udocker 2>/dev/null || true
else
    echo "  ▶ 安装 udocker ..."
    install_udocker
    fix_udocker
fi

# 拉取 HA 镜像（带重试）
echo "  ▶ 拉取 Home Assistant 镜像 ..."
IMAGE_NAME="homeassistant/home-assistant:stable"
for i in 1 2 3; do
    echo "  尝试 $i/3 ..."
    if udocker pull --platform=linux/arm64 "$IMAGE_NAME" 2>&1; then
        echo "  ✓ 镜像拉取成功"
        break
    else
        if [ $i -eq 3 ]; then
            echo "  [ERROR] 镜像拉取失败，请稍后运行 scripts/repair.sh"
            exit 1
        fi
        echo "  [WARN] 拉取失败，等待 $((i * 10)) 秒后重试..."
        sleep $((i * 10))
    fi
done

# 创建容器（如不存在）
CONTAINER_NAME="home-assistant-core"
if udocker ps -a 2>/dev/null | grep -q "$CONTAINER_NAME"; then
    echo "  ▶ 容器 $CONTAINER_NAME 已存在，跳过创建"
else
    echo "  ▶ 创建容器 $CONTAINER_NAME ..."
    udocker_create "$CONTAINER_NAME" "$IMAGE_NAME" || {
        echo "[ERROR] 容器创建失败"
        exit 1
    }
    echo "  ✓ 容器创建完毕"
fi

# ── 完成 ─────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  安装完成！"
echo "========================================="
echo ""
echo "  下一步:"
echo "    sh scripts/start-ha.sh       启动 Home Assistant"
echo "    sh scripts/check-ha.sh       检查系统状态"
echo ""
echo "  启动后访问: http://<手机IP>:8123"
echo ""
