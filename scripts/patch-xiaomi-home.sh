#!/data/data/com.termux/files/usr/bin/bash
# scripts/patch-xiaomi-home.sh — 给 haconfig/custom_components/xiaomi_home 打补丁
#
# Patch B: miot/miot_network.py — psutil.net_if_addrs() 在 Android/Termux udocker
#   下会因 getifaddrs() EACCES 抛 PermissionError，导致配置向导直接 "unknown error"。
#   这里 try/except 后返回空 dict，让 HA 走 fallback 路径。
#
# Patch C: miot/miot_mdns.py — MipsService 通过 AsyncServiceBrowser 监听 mDNS 多播，
#   Android proot 对多播/原始套接字会 SIGSEGV(11)，造成 HA 进程整体崩溃。
#   中国区 cloud_polling 模式不依赖 MIPS 局域网发现，这里短路 init_async/deinit_async。
#
# 幂等：已打过的补丁会直接跳过。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

XIAOMI_DIR="${HA_BASE}/haconfig/custom_components/xiaomi_home"
NET_FILE="${XIAOMI_DIR}/miot/miot_network.py"
MDNS_FILE="${XIAOMI_DIR}/miot/miot_mdns.py"

if [ ! -d "$XIAOMI_DIR" ]; then
    log_warn "xiaomi_home 未安装，跳过补丁"
    exit 0
fi

# ── Patch B: miot_network.py ─────────────────────────────────────────────────
if [ -f "$NET_FILE" ]; then
    if grep -q 'ha-phone patch' "$NET_FILE"; then
        log_info "Patch B (miot_network) 已存在，跳过"
    else
        log_step "Patch B: miot_network.py — 容忍 psutil.net_if_addrs EACCES"
        cp "$NET_FILE" "${NET_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        python3 - "$NET_FILE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = (
    "    def __get_network_info(self) -> dict[str, NetworkInfo]:\n"
    "        interfaces = psutil.net_if_addrs()\n"
)
repl = (
    "    def __get_network_info(self) -> dict[str, NetworkInfo]:\n"
    "        # ha-phone patch: Android getifaddrs EACCES\n"
    "        try:\n"
    "            interfaces = psutil.net_if_addrs()\n"
    "        except (PermissionError, OSError) as _err:\n"
    "            _LOGGER.warning('psutil.net_if_addrs failed (%s), returning empty', _err)\n"
    "            return {}\n"
)
if needle not in s:
    print("PATTERN NOT FOUND — miot_network.py 版本可能不兼容", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched:", p)
PY
        log_ok "Patch B 打好"
    fi
else
    log_warn "未找到 $NET_FILE，跳过 Patch B"
fi

# ── Patch C: miot_mdns.py ────────────────────────────────────────────────────
if [ -f "$MDNS_FILE" ]; then
    if grep -q 'ha-phone patch' "$MDNS_FILE"; then
        log_info "Patch C (miot_mdns) 已存在，跳过"
    else
        log_step "Patch C: miot_mdns.py — 短路 MIPS mDNS（Android proot 多播 SIGSEGV）"
        cp "$MDNS_FILE" "${MDNS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        python3 - "$MDNS_FILE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = (
    "    async def init_async(self) -> None:\n"
    "        await self._aiozc.zeroconf.async_wait_for_start()\n"
    "\n"
    "        self._aio_browser = AsyncServiceBrowser(\n"
    "            zeroconf=self._aiozc.zeroconf,\n"
    "            type_=MIPS_MDNS_TYPE,\n"
    "            handlers=[self.__on_service_state_change],\n"
    "            question_type=DNSQuestionType.QM)\n"
    "\n"
    "    async def deinit_async(self) -> None:\n"
    "        await self._aio_browser.async_cancel()\n"
)
repl = (
    "    async def init_async(self) -> None:\n"
    "        # ha-phone patch: skip mDNS multicast (Android proot SIGSEGVs on multicast sockets)\n"
    "        self._aio_browser = None\n"
    "\n"
    "    async def deinit_async(self) -> None:\n"
    "        if self._aio_browser is None:\n"
    "            return  # ha-phone patch\n"
    "        await self._aio_browser.async_cancel()\n"
)
if needle not in s:
    print("PATTERN NOT FOUND — miot_mdns.py 版本可能不兼容", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched:", p)
PY
        log_ok "Patch C 打好"
    fi
else
    log_warn "未找到 $MDNS_FILE，跳过 Patch C"
fi

# 清理 pyc 缓存，避免旧字节码生效
find "$XIAOMI_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$XIAOMI_DIR" -name "*.pyc" -delete 2>/dev/null || true
