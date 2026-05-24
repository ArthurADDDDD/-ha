#!/data/data/com.termux/files/usr/bin/bash
# ha-phone shared utilities
# Do not source this file directly — use: source "$(dirname "$0")/../lib/utils.sh"

set -euo pipefail

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
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
OVERLAY_DIR="${REPO_DIR}/overlay"
BAK_ROOT="${HA_BASE}/.bak"

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

# ── retry ───────────────────────────────────────────────────────────────────
# Usage: retry <max_attempts> <delay_seconds> <command...>
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=0
    local cmd="$*"

    while [ $attempt -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        log_info "尝试 $attempt/$max_attempts: $cmd"
        if "$@"; then
            return 0
        fi
        if [ $attempt -lt "$max_attempts" ]; then
            log_warn "失败，${delay} 秒后重试..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    log_error "重试 ${max_attempts} 次后仍然失败: $cmd"
    return 1
}

# ── HA container helpers ─────────────────────────────────────────────────────
is_ha_container_exists() {
    udocker ps -a 2>/dev/null | grep -q "home-assistant-core" && return 0 || return 1
}

is_ha_running() {
    udocker ps 2>/dev/null | grep -q "home-assistant-core" && return 0 || return 1
}

is_port_listening() {
    local port="${1:-8123}"
    ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0 || return 1
}

# ── misc ────────────────────────────────────────────────────────────────────
is_termux() {
    [ -d "/data/data/com.termux" ] && return 0 || return 1
}

get_ha_version() {
    if is_ha_running; then
        udocker run --entrypoint "bash -c" home-assistant-core "python3 -m homeassistant --version" 2>/dev/null || echo "unknown"
    else
        echo "unknown (HA 未运行)"
    fi
}

get_python_version_in_ha() {
    if is_ha_running; then
        udocker run --entrypoint "bash -c" home-assistant-core "python3 --version" 2>/dev/null || echo "unknown"
    else
        echo "unknown (HA 未运行)"
    fi
}
