#!/data/data/com.termux/files/usr/bin/bash
# scripts/patch-container.sh — 对容器 ROOT 内的 Python 库做兼容补丁
#
# Patch A: ifaddr/_posix.py — Android/Termux 下 udocker 容器调用 getifaddrs()
#   会返回 EACCES(13)，导致 HA 的 http 组件在 async_get_source_ip 阶段崩溃，
#   连带 frontend/auth/api/... 全部 Setup failed，最终进入 recovery mode。
#   这里把 raise OSError 改为返回空 adapters，HA 会回退到用目标 IP 探测源 IP，
#   不影响监听 0.0.0.0:8123。
#
# 幂等：已打过的补丁会直接跳过。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

CONTAINER_ROOT="${HOME}/.udocker/containers/${CONTAINER_NAME}/ROOT"

if [ ! -d "$CONTAINER_ROOT" ]; then
    log_warn "容器 ROOT 不存在，跳过补丁：$CONTAINER_ROOT"
    log_warn "（首次启动会先由 home-assistant-core.sh 创建容器，再次启动时会自动打补丁）"
    exit 0
fi

# 找到 ifaddr/_posix.py（Python 版本可能变）
IFADDR_FILE="$(find "${CONTAINER_ROOT}/usr/local/lib" -path '*/ifaddr/_posix.py' 2>/dev/null | head -1)"

if [ -z "$IFADDR_FILE" ] || [ ! -f "$IFADDR_FILE" ]; then
    log_warn "未找到 ifaddr/_posix.py，跳过 Patch A"
    exit 0
fi

if grep -q 'ha-phone' "$IFADDR_FILE"; then
    log_info "Patch A (ifaddr) 已存在，跳过"
    exit 0
fi

log_step "Patch A: ifaddr/_posix.py — 容忍 Android getifaddrs EACCES"
cp "$IFADDR_FILE" "${IFADDR_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

python3 - "$IFADDR_FILE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = (
    "if retval != 0:\n"
    "        eno = ctypes.get_errno()\n"
    "        raise OSError(eno, os.strerror(eno))"
)
repl = (
    "if retval != 0:\n"
    "        eno = ctypes.get_errno()\n"
    "        import sys  # ha-phone patch: Android/Termux getifaddrs EACCES\n"
    "        print(f\"[ha-phone] ifaddr getifaddrs failed errno={eno}, returning empty adapters\", file=sys.stderr)\n"
    "        return []"
)
if needle not in s:
    print("PATTERN NOT FOUND — ifaddr 版本可能不兼容，请手动检查", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched:", p)
PY

log_ok "Patch A 打好"
