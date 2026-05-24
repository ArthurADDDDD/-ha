#!/data/data/com.termux/files/usr/bin/bash
# bootstrap/03_patch_base.sh — 给 HomeAssistant-Termux 打补丁
# Patch 1: source.env 添加 --platform=linux/arm64
# Patch 2: home-assistant-core.sh 固定 IMAGE_NAME 为 Docker Hub
set -euo pipefail

HA_BASE_DIR="${HOME}/HomeAssistant-Termux"
SOURCE_ENV="${HA_BASE_DIR}/source.env"
HA_CORE_SH="${HA_BASE_DIR}/home-assistant-core.sh"
BAK_DIR="${HA_BASE_DIR}/.bak/$(date +%Y%m%d_%H%M%S)"

echo "========================================="
echo "  ha-phone bootstrap: 打补丁"
echo "========================================="
echo ""

# ── 备份函数 ─────────────────────────────────────────────────────────────────
backup() {
    local src="$1"
    if [ -f "$src" ]; then
        mkdir -p "$BAK_DIR"
        cp "$src" "${BAK_DIR}/"
        echo "  ▶ 已备份: $src → ${BAK_DIR}/"
    fi
}

# ── Patch 1: source.env — udocker pull 添加 --platform=linux/arm64 ─────────
if [ ! -f "$SOURCE_ENV" ]; then
    echo "  ✗ 找不到 source.env: $SOURCE_ENV"
    echo "  请先运行 bootstrap/02_clone_base.sh"
    exit 1
fi

if grep -q '--platform=linux/arm64' "$SOURCE_ENV"; then
    echo "  ✓ Patch 1 (--platform) 已存在，跳过"
else
    echo "  ▶ Patch 1: 给 udocker pull 添加 --platform=linux/arm64 ..."
    backup "$SOURCE_ENV"
    sed -i 's|udocker pull "$2"|udocker pull --platform=linux/arm64 "$2"|g' "$SOURCE_ENV"
    if grep -q 'udocker pull --platform=linux/arm64 "$2"' "$SOURCE_ENV"; then
        echo "  ✓ Patch 1 打好"
    else
        echo "  ⚠ Patch 1 可能未生效，请手动检查: $SOURCE_ENV"
        echo "  目标行: udocker pull --platform=linux/arm64 "'"$2"'
    fi
fi

# ── Patch 2: home-assistant-core.sh — 修正 IMAGE_NAME ──────────────────────
if [ ! -f "$HA_CORE_SH" ]; then
    echo "  ✗ 找不到 home-assistant-core.sh: $HA_CORE_SH"
    exit 1
fi

CURRENT_IMAGE=$(grep '^IMAGE_NAME=' "$HA_CORE_SH" 2>/dev/null || echo "")
EXPECTED_IMAGE='IMAGE_NAME="homeassistant/home-assistant:stable"'

if echo "$CURRENT_IMAGE" | grep -q 'homeassistant/home-assistant:stable'; then
    echo "  ✓ Patch 2 (IMAGE_NAME) 已是正确值，跳过"
else
    echo "  ▶ Patch 2: 修正 IMAGE_NAME → homeassistant/home-assistant:stable ..."
    backup "$HA_CORE_SH"
    sed -i 's|^IMAGE_NAME=.*|IMAGE_NAME="homeassistant/home-assistant:stable"|' "$HA_CORE_SH"
    echo "  ✓ Patch 2 打好"
fi

echo ""
echo "补丁全部检查完毕。"
