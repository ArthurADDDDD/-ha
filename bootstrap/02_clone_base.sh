#!/data/data/com.termux/files/usr/bin/bash
# bootstrap/02_clone_base.sh — 克隆/更新 HomeAssistant-Termux
set -euo pipefail

BASE_URL="https://github.com/huytungst/HomeAssistant-Termux.git"
HA_BASE_DIR="${HOME}/HomeAssistant-Termux"

echo "========================================="
echo "  ha-phone bootstrap: 基项目同步"
echo "========================================="
echo ""

if [ -d "$HA_BASE_DIR/.git" ]; then
    echo "  ▶ 检测到已有 HomeAssistant-Termux，执行 git pull ..."
    cd "$HA_BASE_DIR"
    if git pull --ff-only 2>&1; then
        echo "  ✓ 已更新到最新版本"
    else
        echo "  ⚠ git pull 失败（网络问题或本地有冲突）"
        echo "  手动修复: cd ~/HomeAssistant-Termux && git pull"
        echo "  如果本地有改动，执行: git stash && git pull"
        exit 1
    fi
else
    echo "  ▶ 克隆 HomeAssistant-Termux ..."
    if [ -d "$HA_BASE_DIR" ]; then
        echo "  ⚠ 目录存在但不是 git 仓库，备份到 .bak/ ..."
        mv "$HA_BASE_DIR" "${HA_BASE_DIR}.old.$(date +%Y%m%d_%H%M%S)"
    fi
    if git clone --depth 1 "$BASE_URL" "$HA_BASE_DIR" 2>&1; then
        echo "  ✓ 克隆完成"
    else
        echo "  ✗ 克隆失败，请检查网络"
        exit 1
    fi
fi

# 确保脚本可执行
chmod +x "$HA_BASE_DIR"/*.sh 2>/dev/null || true

echo ""
echo "基项目同步完毕。"
