#!/data/data/com.termux/files/usr/bin/bash
# scripts/start-ha.sh — 启动 Home Assistant（前台运行，直接看日志）
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux 未找到，请先运行 scripts/install.sh"
    exit 1
fi

cd "$HA_BASE"
source "${HA_BASE}/source.env" 2>/dev/null || {
    echo "[ERROR] 无法加载 source.env，请运行 scripts/install.sh"
    exit 1
}

# ── 已经在运行？ ──────────────────────────────────────────────────────────
if is_port_listening 8123; then
    echo "[INFO] Home Assistant 已在运行（端口 8123 已监听）"
    echo "  访问: http://$(get_lan_ip):8123"
    echo ""
    echo "  查看日志: udocker logs -f home-assistant-core"
    exit 0
fi

# ── 清理旧容器 ────────────────────────────────────────────────────────────
if command -v udocker >/dev/null 2>&1; then
    if udocker ps -a 2>/dev/null | grep -q "$CONTAINER_NAME"; then
        echo "[INFO] 清理旧容器..."
        udocker stop "$CONTAINER_NAME" 2>/dev/null || true
        sleep 1
        udocker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi
fi

# ── 确保容器已建，并打容器内补丁（ifaddr 等）─────────────────────────────
# 首次启动时容器 ROOT 还不存在，先 udocker_create 让 ROOT 落盘再打补丁，
# 否则要等首次失败后再启动才能修好。
if command -v udocker_create >/dev/null 2>&1; then
    if [ ! -d "${HOME}/.udocker/containers/${CONTAINER_NAME}/ROOT" ]; then
        echo "[INFO] 首次启动：预创建容器 $CONTAINER_NAME ..."
        udocker_check || true
        udocker_create "$CONTAINER_NAME" "$IMAGE_NAME" || true
    fi
fi
bash "${SCRIPT_DIR}/patch-container.sh" || log_warn "patch-container.sh 失败，继续启动（HA 可能进 recovery mode）"
bash "${SCRIPT_DIR}/patch-xiaomi-home.sh" || log_warn "patch-xiaomi-home.sh 失败，继续启动（Xiaomi 集成可能崩溃）"
bash "${SCRIPT_DIR}/patch-midea.sh" || log_warn "patch-midea.sh 失败，继续启动（Midea 集成可能发现失败）"

# ── 启动（前台，日志直接输出到终端）───────────────────────────────────────
export PORT="${PORT:-8123}"
mkdir -p "${HA_BASE}/haconfig"

echo ""
echo "========================================="
echo "  启动 Home Assistant ..."
echo "  以下为 HA 实时日志，等待出现 on 0.0.0.0:8123"
echo "  Ctrl+C 可停止"
echo "========================================="
echo ""

cleanup_on_interrupt() {
    echo ""
    log_warn "收到中断信号，正在停止 Home Assistant ..."
    bash "${SCRIPT_DIR}/stop-ha.sh" || true
    exit 130
}

trap cleanup_on_interrupt INT TERM

# 前台运行并保留中断清理逻辑
bash "${HA_BASE}/home-assistant-core.sh" &
HA_BOOT_PID=$!
wait "$HA_BOOT_PID"
EXIT_CODE=$?
trap - INT TERM
exit "$EXIT_CODE"
