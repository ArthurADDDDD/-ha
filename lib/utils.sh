#!/data/data/com.termux/files/usr/bin/bash
# ha-phone shared utilities
# 使用: source "$(dirname "$0")/../lib/utils.sh"

# ── colors ──────────────────────────────────────────────────────────────────
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_RESET='\033[0m'

# ── logging ─────────────────────────────────────────────────────────────────
log_info()  { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*"; }
log_warn()  { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*"; }
log_error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*"; }
log_ok()    { printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*"; }
log_step()  { printf "\n${C_BLUE}==>${C_RESET} %s\n" "$*"; }

# ── paths ───────────────────────────────────────────────────────────────────
HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
BAK_ROOT="${HA_BASE}/.bak"
CONTAINER_NAME="home-assistant-core"
IMAGE_NAME="homeassistant/home-assistant:stable"

# ── file helpers ────────────────────────────────────────────────────────────
ensure_dir() {
    mkdir -p "$1"
}

backup_file() {
    local src="$1"
    if [ -f "$src" ] || [ -d "$src" ]; then
        local ts
        ts="$(date +%Y%m%d_%H%M%S)"
        ensure_dir "${BAK_ROOT}/${ts}"
        cp -a "$src" "${BAK_ROOT}/${ts}/"
        log_info "已备份: $src → ${BAK_ROOT}/${ts}/"
    fi
}

# ── network helpers ─────────────────────────────────────────────────────────
# Android/Termux 兼容的 IP 获取
get_lan_ip() {
    local ip
    # 每个方法都套 timeout 2s，避免 termux-wifi-connectioninfo 等命令在
    # 缺定位权限时阻塞导致整个 patch 脚本挂起
    local T
    T="$(command -v timeout 2>/dev/null && echo 'timeout 2' || true)"

    # 方法0: ifconfig 不带 timeout（最兼容，SSH 非交互环境也能用）
    ip=$(ifconfig wlan0 2>/dev/null | awk '/inet / {gsub("addr:","",$2); print $2; exit}') && [ -n "$ip" ] && { echo "$ip"; return 0; }

    # 方法1: ip route (Android 7+)
    ip=$(${T:-} ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $NF; exit}') && [ -n "$ip" ] && { echo "$ip"; return 0; }

    # 方法2: ip addr 扫 wlan0
    ip=$(${T:-} ip addr show wlan0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}') && [ -n "$ip" ] && { echo "$ip"; return 0; }

    # 方法3: ifconfig (两种格式兼容)
    ip=$(${T:-} ifconfig wlan0 2>/dev/null | awk '/inet / {gsub("addr:","",$2); print $2; exit}') && [ -n "$ip" ] && { echo "$ip"; return 0; }

    # 方法4: hostname -I
    ip=$(${T:-} hostname -I 2>/dev/null | awk '{print $1}') && [ -n "$ip" ] && { echo "$ip"; return 0; }

    # 方法5: termux-wifi-connectioninfo（放最后，需要定位权限，可能阻塞）
    ip=$(${T:-} termux-wifi-connectioninfo 2>/dev/null | grep 'ip' | awk -F'"' '{print $4}') && [ -n "$ip" ] && { echo "$ip"; return 0; }

    echo "unknown"
}

# ── HA container helpers ─────────────────────────────────────────────────────
# 用端口检测优先，udocker ps 做辅助
is_ha_running() {
    # 端口在监听 → 肯定在运行
    if is_port_listening 8123; then
        return 0
    fi
    # 端口不在但 udocker ps 看到容器 → 可能在启动中
    if command -v udocker >/dev/null 2>&1 && udocker ps 2>/dev/null | grep -q "home-assistant-core"; then
        return 0
    fi
    return 1
}

is_port_listening() {
    local port="${1:-8123}"
    # 方法1: ss (Termux 新版有)
    ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    # 方法2: Python socket (最可靠)
    python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(1)
r = s.connect_ex(('127.0.0.1', ${port}))
s.close()
exit(r)
" 2>/dev/null && return 0
    # 方法3: netstat 兜底
    netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 0
    return 1
}

# ── retry ───────────────────────────────────────────────────────────────────
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=0

    while [ $attempt -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log_info "尝试 $attempt/$max_attempts: $*"
        if "$@"; then
            return 0
        fi
        if [ $attempt -lt "$max_attempts" ]; then
            log_warn "失败，${delay} 秒后重试..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    log_error "重试 ${max_attempts} 次后仍然失败"
    return 1
}

# ── misc ────────────────────────────────────────────────────────────────────
is_termux() {
    [ -d "/data/data/com.termux" ] || [ -d "/data/data/com.termux/files" ]
}
