#!/data/data/com.termux/files/usr/bin/bash
# scripts/patch-midea.sh - Patch midea_lan runtime deps for Android/Termux
#
# Patch A: ifaddr/_posix.py - tolerate getifaddrs() EACCES in haconfig/deps
# Patch B: midealocal/discover.py - tolerate ifaddr.get_adapters() failure
# Patch C: midealocal/discover.py - tolerate SO_BROADCAST failure
#
# Idempotent: each patch uses a marker and can be rerun safely.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

MIDEA_DIR=""
CONTAINER_LIB="${HOME}/.udocker/containers/${CONTAINER_NAME}/ROOT/usr/local/lib"

if [ -d "${HA_CONFIG}/custom_components/midea_ac_lan" ]; then
    MIDEA_DIR="${HA_CONFIG}/custom_components/midea_ac_lan"
elif [ -d "${HA_CONFIG}/custom_components/midea_lan" ]; then
    MIDEA_DIR="${HA_CONFIG}/custom_components/midea_lan"
elif [ -d "${HA_CONFIG}/custom_components/midea_ac" ]; then
    log_info "midea_ac (mill1000) detected; legacy midea_lan patch not required"
    exit 0
fi

if [ -z "$MIDEA_DIR" ]; then
    log_warn "midea_lan not installed, skip patch"
    exit 0
fi

backup_once() {
    cp "$1" "${1}.bak.$(date +%Y%m%d_%H%M%S)"
}

patch_ifaddr_file() {
    local target="$1"
    if grep -q 'ha-phone patch: Android/Termux getifaddrs' "$target" || grep -q 'ha-phone midea patch A' "$target"; then
        log_info "Patch A already present: $target"
        return 0
    fi

    log_step "Patch A: tolerate getifaddrs EACCES in $target"
    backup_once "$target"
    python3 - "$target" <<'PY'
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
    "        import sys  # ha-phone midea patch A: Android/Termux getifaddrs EACCES\n"
    "        print(f\"[ha-phone] ifaddr getifaddrs failed errno={eno}, returning empty adapters\", file=sys.stderr)\n"
    "        return []"
)
if needle not in s:
    print(f"PATTERN NOT FOUND (Patch A): {p}", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl, 1))
print("patched A:", p)
PY
    log_ok "Patch A applied"
}

patch_discover_file() {
    local target="$1"

    if grep -q 'ha-phone midea patch B' "$target"; then
        log_info "Patch B already present: $target"
    else
        log_step "Patch B: tolerate ifaddr failure in $target"
        backup_once "$target"
        python3 - "$target" <<'PY'
import sys

p = sys.argv[1]
s = open(p).read()
needle = "    adapters = ifaddr.get_adapters()\n"
repl = (
    "    # ha-phone midea patch B: Android getifaddrs EACCES\n"
    "    try:\n"
    "        adapters = ifaddr.get_adapters()\n"
    "    except (PermissionError, OSError) as _err:\n"
    "        _LOGGER.warning('ifaddr.get_adapters failed (%s), using manual IP fallback', _err)\n"
    "        return []\n"
)
if needle not in s:
    print(f"PATTERN NOT FOUND (Patch B): {p}", file=sys.stderr)
    sys.exit(2)
open(p, "w").write(s.replace(needle, repl, 1))
print("patched B:", p)
PY
        log_ok "Patch B applied"
    fi

    if grep -q 'ha-phone midea patch C' "$target"; then
        log_info "Patch C already present: $target"
        return 0
    fi

    if grep -q 'sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)' "$target"; then
        log_step "Patch C: tolerate SO_BROADCAST failure in $target"
        backup_once "$target"
        python3 - "$target" <<'PY'
import sys, re

p = sys.argv[1]
s = open(p).read()

# Match the SO_BROADCAST setsockopt line regardless of indentation
pattern = r'^(\s*)sock\.setsockopt\(socket\.SOL_SOCKET,\s*socket\.SO_BROADCAST,\s*1\)$'
m = re.search(pattern, s, re.MULTILINE)
if not m:
    print(f"PATTERN NOT FOUND (Patch C): {p}", file=sys.stderr)
    sys.exit(2)

indent = m.group(1)
original = m.group(0)
replacement = (
    f"{indent}try:\n"
    f"{indent}    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)\n"
    f"{indent}except OSError:\n"
    f"{indent}    pass  # ha-phone midea patch C\n"
)
open(p, "w").write(s.replace(original, replacement, 1))
print("patched C:", p)
PY
        log_ok "Patch C applied"
    else
        log_info "Patch C skipped: SO_BROADCAST line not found in $target"
    fi
}

find_targets() {
    local pattern="$1"
    local root
    for root in "${HA_CONFIG}/deps" "$CONTAINER_LIB" "${MIDEA_DIR}/_vendor"; do
        [ -d "$root" ] || continue
        find "$root" -path "$pattern" -type f 2>/dev/null || true
    done
}

report_dep_state() {
    local label="$1"
    local pattern="$2"
    if find_targets "$pattern" | head -1 | grep -q .; then
        log_info "$label detected"
    else
        log_warn "$label not found yet; let HA install requirements first, then rerun this script"
    fi
}

patched_any=0

while IFS= read -r file; do
    [ -n "$file" ] || continue
    patch_ifaddr_file "$file"
    patched_any=1
done < <(find_targets '*/ifaddr/_posix.py')

while IFS= read -r file; do
    [ -n "$file" ] || continue
    patch_discover_file "$file"
    patched_any=1
done < <(find_targets '*/midealocal/discover.py')

if [ "$patched_any" -eq 0 ]; then
    log_warn "No midea runtime files found to patch"
    report_dep_state "midealocal" '*/midealocal/__init__.py'
    report_dep_state "pycryptodome/Crypto" '*/Crypto/__init__.py'
else
    report_dep_state "midealocal" '*/midealocal/__init__.py'
    report_dep_state "pycryptodome/Crypto" '*/Crypto/__init__.py'
fi
