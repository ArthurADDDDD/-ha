#!/data/data/com.termux/files/usr/bin/bash
# scripts/patch-xiaomi-home.sh — 给 haconfig/custom_components/xiaomi_home 打补丁
#
# Patch B: miot/miot_network.py — psutil.net_if_addrs() EACCES → try/except
# Patch C: miot/miot_mdns.py — 短路 MipsService init_async/deinit_async（多播 SIGSEGV）
# Patch D: miot/miot_network.py — 短路 __ping_async（ICMP raw socket SIGSEGV）
# Patch E: miot/miot_network.py — 短路 init_async 全部网络探测
# Patch F: miot/const.py — OAUTH_REDIRECT_URL 改成手机 LAN IP（homeassistant.local 不可解析）
#
# 幂等：按各自标记独立判断；已打过的直接跳过。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

XIAOMI_DIR="${HA_BASE}/haconfig/custom_components/xiaomi_home"
NET_FILE="${XIAOMI_DIR}/miot/miot_network.py"
MDNS_FILE="${XIAOMI_DIR}/miot/miot_mdns.py"
CONST_FILE="${XIAOMI_DIR}/miot/const.py"

if [ ! -d "$XIAOMI_DIR" ]; then
    log_warn "xiaomi_home 未安装，跳过补丁"
    exit 0
fi

backup_once() {
    cp "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)"
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
    print("PATTERN NOT FOUND (Patch B)", file=sys.stderr); sys.exit(2)
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
        log_step "Patch D: miot_network.py — 短路 __ping_async（ICMP raw socket SIGSEGV）"
        backup_once "$NET_FILE"
        python3 - "$NET_FILE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "    async def __ping_async(self, address: Optional[str] = None) -> float:\n"
if needle not in s:
    print("PATTERN NOT FOUND (Patch D)", file=sys.stderr); sys.exit(2)
repl = (
    "    async def __ping_async(self, address: Optional[str] = None) -> float:\n"
    "        # ha-phone patch D: skip ping subprocess (Android proot SIGSEGVs on ICMP raw sockets)\n"
    "        return self._DETECT_TIMEOUT\n"
)
open(p, "w").write(s.replace(needle, repl, 1))
print("patched D:", p)
PY
        log_ok "Patch D 打好"
    fi
fi

# ── Patch E: miot_network.py init_async ──────────────────────────────────────
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
    "        # ha-phone patch E: skip network detection (Android proot incompatible)\n"
    "        self._network_status = True\n"
    "        if not self._done_event.is_set():\n"
    "            self._done_event.set()\n"
    "        return True\n"
)
if needle not in s:
    print("PATTERN NOT FOUND (Patch E)", file=sys.stderr); sys.exit(2)
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
        log_step "Patch C: miot_mdns.py — 短路 MIPS mDNS（多播 SIGSEGV）"
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
    print("PATTERN NOT FOUND (Patch C)", file=sys.stderr); sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched C:", p)
PY
        log_ok "Patch C 打好"
    fi
fi

# ── Patch F: const.py OAUTH_REDIRECT_URL ─────────────────────────────────────
# 默认 'http://homeassistant.local:8123' 在普通浏览器无法 mDNS 解析，OAuth 回调失败。
# 改成手机 LAN IP，下次配置向导生成的 redirect_uri 就是可访问的。
if [ -f "$CONST_FILE" ]; then
    # 解析 LAN_IP：优先环境变量 HA_LAN_IP，其次 get_lan_ip
    LAN_IP="${HA_LAN_IP:-$(get_lan_ip 2>/dev/null || true)}"
    LAN_IP_VALID=1
    case "$LAN_IP" in
        ""|"unknown"|"127.0.0.1"|"0.0.0.0") LAN_IP_VALID=0 ;;
        *[!0-9.]*) LAN_IP_VALID=0 ;;
    esac

    # 已 patch 但 IP 是 unknown / 与当前 LAN_IP 不一致 → 从备份恢复后重新打
    if grep -q 'ha-phone patch F' "$CONST_FILE"; then
        CUR_IP="$(grep -oE "OAUTH_REDIRECT_URL: str = 'http://[^:]+:" "$CONST_FILE" | sed -E "s|.*'http://([^:]+):.*|\1|")"
        if [ "$LAN_IP_VALID" = "1" ] && [ -n "$CUR_IP" ] && [ "$CUR_IP" != "$LAN_IP" ]; then
            log_warn "Patch F 已存在但 IP=${CUR_IP}，将从备份恢复并改写为 ${LAN_IP}"
            BAK="$(ls -t "${CONST_FILE}".bak.* 2>/dev/null | head -1)"
            if [ -n "$BAK" ]; then
                cp "$BAK" "$CONST_FILE"
            else
                log_warn "找不到 const.py 备份，跳过 Patch F 重写"
                LAN_IP_VALID=0
            fi
        else
            log_info "Patch F (const OAUTH_REDIRECT_URL=${CUR_IP}) 已存在，跳过"
            LAN_IP_VALID=0  # 不再重打
        fi
    fi

    if [ "$LAN_IP_VALID" = "1" ]; then
        if [ -z "$LAN_IP" ] || [ "$LAN_IP" = "unknown" ]; then
            log_warn "未能拿到手机 LAN IP，跳过 Patch F（用 HA_LAN_IP=x.x.x.x 覆盖）"
        else
            log_step "Patch F: const.py — OAUTH_REDIRECT_URL → http://${LAN_IP}:8123"
            backup_once "$CONST_FILE"
            python3 - "$CONST_FILE" "$LAN_IP" <<'PY'
import sys
p, ip = sys.argv[1], sys.argv[2]
s = open(p).read()
needle = "OAUTH_REDIRECT_URL: str = 'http://homeassistant.local:8123'\n"
repl = (
    f"# ha-phone patch F: replace homeassistant.local with phone LAN IP\n"
    f"OAUTH_REDIRECT_URL: str = 'http://{ip}:8123'\n"
)
if needle not in s:
    print("PATTERN NOT FOUND (Patch F)", file=sys.stderr); sys.exit(2)
open(p, "w").write(s.replace(needle, repl))
print("patched F:", p)
PY
            log_ok "Patch F 打好"
        fi
    fi
fi

# 清理 pyc 缓存
find "$XIAOMI_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$XIAOMI_DIR" -name "*.pyc" -delete 2>/dev/null || true
