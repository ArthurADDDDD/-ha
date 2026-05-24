#!/data/data/com.termux/files/usr/bin/bash
# scripts/patch-xiaomi-home.sh — 给 haconfig/custom_components/xiaomi_home 打补丁
#
# Patch B: miot/miot_network.py — psutil.net_if_addrs() 在 Android/Termux udocker
#   下会因 getifaddrs() EACCES 抛 PermissionError，导致配置向导直接 "unknown error"。
#   try/except 后返回空 dict，让 HA 走 fallback 路径。
#
# Patch C: miot/miot_mdns.py — MipsService 通过 AsyncServiceBrowser 监听 mDNS 多播，
#   Android proot 对多播套接字会 SIGSEGV(11)，造成 HA 进程整体崩溃。
#   中国区 cloud_polling 不依赖 MIPS 局域网发现，短路 init_async/deinit_async。
#
# Patch D: miot/miot_network.py — __ping_async 用 subprocess 调 ping 二进制，ping
#   会创建 ICMP raw socket，Android proot 同样 SIGSEGV(11)；短路直接返回 TIMEOUT，
#   http 探测（普通 TCP）保留可用。
#
# 幂等：按各自标记独立判断；已打过的直接跳过。
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

backup_once() {
    local f="$1"
    cp "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"
}

# ── Patch B: miot_network.py psutil ──────────────────────────────────────────
if [ -f "$NET_FILE" ]; then
    if grep -q 'ha-phone patch B' "$NET_FILE" || grep -q 'ha-phone patch: Android getifaddrs' "$NET_FILE"; then
        log_info "Patch B (miot_network psutil) 已存在，跳过"
    else
        log_step "Patch B: miot_network.py — 容忍 psutil.net_if_addrs EACCES"
        backup_once "$NET_FILE"
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
    "        # ha-phone patch B: Android getifaddrs EACCES\n"
    "        try:\n"
    "            interfaces = psutil.net_if_addrs()\n"
    "        except (PermissionError, OSError) as _err:\n"
    "            _LOGGER.warning('psutil.net_if_addrs failed (%s), returning empty', _err)\n"
    "            return {}\n"
)
if needle not in s:
    print("PATTERN NOT FOUND — miot_network.py 版本可能不兼容 (Patch B)", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched B:", p)
PY
        log_ok "Patch B 打好"
    fi
fi

# ── Patch D: miot_network.py __ping_async ────────────────────────────────────
if [ -f "$NET_FILE" ]; then
    if grep -q 'ha-phone patch D' "$NET_FILE"; then
        log_info "Patch D (miot_network ping) 已存在，跳过"
    else
        log_step "Patch D: miot_network.py — 短路 __ping_async（Android proot ICMP SIGSEGV）"
        backup_once "$NET_FILE"
        python3 - "$NET_FILE" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
needle = "    async def __ping_async(self, address: Optional[str] = None) -> float:\n"
if needle not in s:
    print("PATTERN NOT FOUND — miot_network.py __ping_async signature 不匹配", file=sys.stderr)
    sys.exit(2)
repl = (
    "    async def __ping_async(self, address: Optional[str] = None) -> float:\n"
    "        # ha-phone patch D: skip ping subprocess (Android proot SIGSEGVs on ICMP raw sockets)\n"
    "        return self._DETECT_TIMEOUT\n"
)
# 只替换函数签名行：保留原函数体作为死代码（return 已提前 return）
open(p, "w").write(s.replace(needle, repl, 1))
print("patched D:", p)
PY
        log_ok "Patch D 打好"
    fi
fi

# ── Patch E: miot_network.py init_async ──────────────────────────────────────
# 完全跳过启动期网络探测（http_multi + get_network_info）。Android proot 下：
#   - aiohttp HTTPS 偶发崩在 TLS/解析底层
#   - psutil C 扩展在 getifaddrs EACCES 路径上可能直接段错（绕过 Python 层 try/except）
# 中国区 cloud_polling 不依赖启动期探测，置 network_status=True 即可。
if [ -f "$NET_FILE" ]; then
    if grep -q 'ha-phone patch E' "$NET_FILE"; then
        log_info "Patch E (miot_network init_async) 已存在，跳过"
    else
        log_step "Patch E: miot_network.py — 短路 init_async（跳过启动期网络探测）"
        backup_once "$NET_FILE"
        python3 - "$NET_FILE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = (
    "    async def init_async(self) -> bool:\n"
    "        self.__refresh_timer_handler()\n"
    "        # MUST get network info before starting\n"
    "        return await self._done_event.wait()\n"
)
repl = (
    "    async def init_async(self) -> bool:\n"
    "        # ha-phone patch E: skip network detection (Android proot incompatible\n"
    "        # with psutil getifaddrs / aiohttp HTTPS in init path; trust network up)\n"
    "        self._network_status = True\n"
    "        if not self._done_event.is_set():\n"
    "            self._done_event.set()\n"
    "        return True\n"
)
if needle not in s:
    print("PATTERN NOT FOUND — miot_network.py init_async 不匹配 (Patch E)", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched E:", p)
PY
        log_ok "Patch E 打好"
    fi
fi

# ── Patch C: miot_mdns.py MipsService ────────────────────────────────────────
if [ -f "$MDNS_FILE" ]; then
    if grep -q 'ha-phone patch C' "$MDNS_FILE" || grep -q 'ha-phone patch: skip mDNS' "$MDNS_FILE"; then
        log_info "Patch C (miot_mdns) 已存在，跳过"
    else
        log_step "Patch C: miot_mdns.py — 短路 MIPS mDNS（Android proot 多播 SIGSEGV）"
        backup_once "$MDNS_FILE"
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
    "        # ha-phone patch C: skip mDNS multicast (Android proot SIGSEGVs on multicast sockets)\n"
    "        self._aio_browser = None\n"
    "\n"
    "    async def deinit_async(self) -> None:\n"
    "        if self._aio_browser is None:\n"
    "            return  # ha-phone patch C\n"
    "        await self._aio_browser.async_cancel()\n"
)
if needle not in s:
    print("PATTERN NOT FOUND — miot_mdns.py 版本可能不兼容 (Patch C)", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched C:", p)
PY
        log_ok "Patch C 打好"
    fi
fi

# 清理 pyc 缓存，避免旧字节码生效
find "$XIAOMI_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$XIAOMI_DIR" -name "*.pyc" -delete 2>/dev/null || true
