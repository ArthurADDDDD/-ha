#!/data/data/com.termux/files/usr/bin/bash
# bootstrap/01_termux_pkgs.sh — 安装 Termux 基础包
# 每个包独立安装，失败不阻塞后续，最后汇总报告

set -euo pipefail

PKGS=(
    python
    python-pip
    proot
    patch
    git
    curl
    openssl-tool
    termux-api
)

FAILED=""
OK_COUNT=0

echo "========================================="
echo "  ha-phone bootstrap: 基础包安装"
echo "========================================="
echo ""

for pkg in "${PKGS[@]}"; do
    printf "  ▶ 安装 %-20s ... " "$pkg"
    if pkg install -y "$pkg" >/dev/null 2>&1; then
        echo "OK"
        OK_COUNT=$((OK_COUNT + 1))
    else
        echo "FAILED"
        FAILED="${FAILED}  - ${pkg}\n"
    fi
done

echo ""
echo "─────────────────────────────────────────"
echo "  结果: ${OK_COUNT}/${#PKGS[@]} 个包安装成功"
echo "─────────────────────────────────────────"

if [ -n "$FAILED" ]; then
    printf "\n以下包安装失败:\n%b" "$FAILED"
    echo ""
    echo "请手动运行: pkg install -y <包名>"
    echo "然后重新执行本脚本。"
    exit 1
fi

echo ""
echo "基础包安装完毕。"
