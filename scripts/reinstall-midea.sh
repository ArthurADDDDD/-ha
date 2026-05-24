#!/data/data/com.termux/files/usr/bin/bash
# scripts/reinstall-midea.sh - install/update Midea integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CUSTOM_COMPONENTS="${HA_CONFIG}/custom_components"
BAK_DIR="${HA_BASE}/.bak/midea_$(date +%Y%m%d_%H%M%S)"

# Default to mill1000/midea-ac-py because it avoids the midea-local/commonregex chain.
MIDEA_IMPL="${MIDEA_IMPL:-mill}"

MILL_REPO="https://github.com/mill1000/midea-ac-py.git"
MILL_TMP="${HOME}/.cache/midea-ac-py"
MILL_TMP_NEW="${MILL_TMP}.new.$$"
MSMART_REPO="https://github.com/mill1000/midea-msmart.git"
MSMART_TMP="${HOME}/.cache/midea-msmart"
MSMART_TMP_NEW="${MSMART_TMP}.new.$$"

LEGACY_REPO_PRIMARY="https://github.com/wuwentao/midea_ac_lan.git"
LEGACY_REPO_FALLBACK="https://github.com/wuwentao/midea_lan.git"
LEGACY_TMP="${HOME}/.cache/midea_ac_lan"
LEGACY_TMP_NEW="${LEGACY_TMP}.new.$$"
MIDEA_LOCAL_REPO="https://github.com/rokam/midea-local.git"
MIDEA_LOCAL_TMP="${HOME}/.cache/midea-local"
MIDEA_LOCAL_TMP_NEW="${MIDEA_LOCAL_TMP}.new.$$"

echo ""
echo "========================================="
echo "  Install Midea integration"
echo "========================================="
echo "  implementation: ${MIDEA_IMPL}"
echo ""

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux not found. Run scripts/install.sh first."
    exit 1
fi

mkdir -p "$CUSTOM_COMPONENTS"

echo "  > backup current midea components"
mkdir -p "$BAK_DIR"
for d in midea_ac midea_ac_lan midea_lan; do
    if [ -d "${CUSTOM_COMPONENTS}/${d}" ]; then
        cp -a "${CUSTOM_COMPONENTS}/${d}" "$BAK_DIR/"
    fi
done

echo "  > remove old deployment"
for d in midea_ac midea_ac_lan midea_lan; do
    [ -d "${CUSTOM_COMPONENTS}/${d}" ] && rm -rf "${CUSTOM_COMPONENTS:?}/${d}"
done
find "$CUSTOM_COMPONENTS" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

if [ "$MIDEA_IMPL" = "mill" ]; then
    echo "  > fetch mill1000/midea-ac-py"
    FETCH_OK=0
    if [ -d "${MILL_TMP}/.git" ]; then
        cd "$MILL_TMP"
        if git pull --ff-only 2>/dev/null; then
            FETCH_OK=1
        fi
    fi
    if [ "$FETCH_OK" -eq 0 ]; then
        rm -rf "$MILL_TMP_NEW"
        if git clone --depth 1 "$MILL_REPO" "$MILL_TMP_NEW" 2>&1; then
            rm -rf "$MILL_TMP"
            mv "$MILL_TMP_NEW" "$MILL_TMP"
            FETCH_OK=1
        fi
    fi
    rm -rf "$MILL_TMP_NEW" 2>/dev/null || true
    if [ "$FETCH_OK" -eq 0 ] && [ ! -d "${MILL_TMP}/.git" ]; then
        echo "  [ERROR] unable to fetch ${MILL_REPO}"
        exit 1
    fi

    if [ ! -d "${MILL_TMP}/custom_components/midea_ac" ]; then
        echo "  [ERROR] midea_ac path not found in ${MILL_TMP}"
        exit 1
    fi

    cp -a "${MILL_TMP}/custom_components/midea_ac" "${CUSTOM_COMPONENTS}/midea_ac"
    echo "  [OK] deployed: ${CUSTOM_COMPONENTS}/midea_ac"

    echo "  > fetch mill1000/midea-msmart"
    MSMART_OK=0
    if [ -d "${MSMART_TMP}/.git" ]; then
        cd "$MSMART_TMP"
        if git pull --ff-only 2>/dev/null; then
            MSMART_OK=1
        fi
    fi
    if [ "$MSMART_OK" -eq 0 ]; then
        rm -rf "$MSMART_TMP_NEW"
        if git clone --depth 1 "$MSMART_REPO" "$MSMART_TMP_NEW" 2>&1; then
            rm -rf "$MSMART_TMP"
            mv "$MSMART_TMP_NEW" "$MSMART_TMP"
            MSMART_OK=1
        fi
    fi
    rm -rf "$MSMART_TMP_NEW" 2>/dev/null || true
    if [ "$MSMART_OK" -eq 0 ] && [ ! -d "${MSMART_TMP}/.git" ]; then
        echo "  [ERROR] unable to fetch ${MSMART_REPO}"
        exit 1
    fi

    echo "  > vendor msmart into midea_ac"
    VENDOR_DIR="${CUSTOM_COMPONENTS}/midea_ac/_vendor"
    rm -rf "$VENDOR_DIR"
    mkdir -p "$VENDOR_DIR"
    if [ -d "${MSMART_TMP}/msmart" ]; then
        cp -a "${MSMART_TMP}/msmart" "$VENDOR_DIR/"
    elif [ -d "${MSMART_TMP}/src/msmart" ]; then
        cp -a "${MSMART_TMP}/src/msmart" "$VENDOR_DIR/"
    else
        echo "  [ERROR] msmart module path not found in ${MSMART_TMP}"
        exit 1
    fi

    echo "  > patch vendored msmart __version__"
    python3 - "${VENDOR_DIR}/msmart/__init__.py" <<'PY'
import pathlib
import sys

init_path = pathlib.Path(sys.argv[1])
content = init_path.read_text(encoding="utf-8")

if "__version__" not in content:
    content += (
        "\n\ntry:\n"
        "    __version__\n"
        "except NameError:\n"
        "    try:\n"
        "        from importlib.metadata import version as _pkg_version\n"
        "        __version__ = _pkg_version('msmart-ng')\n"
        "    except Exception:\n"
        "        __version__ = 'unknown'\n"
    )
    init_path.write_text(content, encoding="utf-8")
PY

    echo "  > patch midea_ac manifest and vendor import path"
    python3 - "${CUSTOM_COMPONENTS}/midea_ac" <<'PY'
import json
import os
import sys

component_dir = sys.argv[1]
manifest_path = os.path.join(component_dir, "manifest.json")
with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

requirements = manifest.get("requirements", [])
manifest["requirements"] = [req for req in requirements if not req.startswith("msmart-ng")]

with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
    f.write("\n")

init_path = os.path.join(component_dir, "__init__.py")
with open(init_path, "r", encoding="utf-8") as f:
    content = f.read()

bootstrap = (
    "import os\n"
    "import sys\n"
    "# ha-phone vendor bootstrap\n"
    "_HA_PHONE_VENDOR = os.path.join(os.path.dirname(__file__), \"_vendor\")\n"
    "if _HA_PHONE_VENDOR not in sys.path:\n"
    "    sys.path.insert(0, _HA_PHONE_VENDOR)\n\n"
)
if "# ha-phone vendor bootstrap" not in content:
    lines = content.splitlines(keepends=True)
    insert_at = 0
    if lines and lines[0].startswith("#!"):
        insert_at = 1

    if insert_at < len(lines) and lines[insert_at].startswith(('"""', "'''")):
        quote = lines[insert_at][:3]
        if quote in lines[insert_at][3:]:
            insert_at += 1
        else:
            insert_at += 1
            while insert_at < len(lines):
                if quote in lines[insert_at]:
                    insert_at += 1
                    break
                insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    if insert_at < len(lines) and lines[insert_at].startswith("from __future__ import "):
        insert_at += 1
        while insert_at < len(lines) and lines[insert_at].startswith("from __future__ import "):
            insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    lines.insert(insert_at, bootstrap)
    with open(init_path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
PY

    echo "  > syntax check patched midea_ac"
    python3 -c "
import py_compile, sys, pathlib
component_dir = pathlib.Path('${CUSTOM_COMPONENTS}/midea_ac')
errors = []
for f in component_dir.rglob('*.py'):
    try:
        py_compile.compile(str(f), doraise=True)
    except py_compile.PyCompileError as e:
        errors.append(str(e))
if errors:
    for e in errors:
        print(f'SYNTAX ERROR: {e}', file=sys.stderr)
    sys.exit(1)
print('  [OK] all Python files pass syntax check')
"
else
    echo "  > fetch legacy midea_ac_lan"
    FETCH_OK=0
    if [ -d "${LEGACY_TMP}/.git" ]; then
        cd "$LEGACY_TMP"
        if git pull --ff-only 2>/dev/null; then
            FETCH_OK=1
        fi
    fi
    if [ "$FETCH_OK" -eq 0 ]; then
        rm -rf "$LEGACY_TMP_NEW"
        if git clone --depth 1 "$LEGACY_REPO_PRIMARY" "$LEGACY_TMP_NEW" 2>&1; then
            rm -rf "$LEGACY_TMP"
            mv "$LEGACY_TMP_NEW" "$LEGACY_TMP"
            FETCH_OK=1
        else
            rm -rf "$LEGACY_TMP_NEW"
            if git clone --depth 1 "$LEGACY_REPO_FALLBACK" "$LEGACY_TMP_NEW" 2>&1; then
                rm -rf "$LEGACY_TMP"
                mv "$LEGACY_TMP_NEW" "$LEGACY_TMP"
                FETCH_OK=1
            fi
        fi
    fi
    rm -rf "$LEGACY_TMP_NEW" 2>/dev/null || true
    if [ "$FETCH_OK" -eq 0 ] && [ ! -d "${LEGACY_TMP}/.git" ]; then
        echo "  [ERROR] unable to fetch legacy midea repository"
        exit 1
    fi

    LEGACY_DEPLOY_DIR=""
    if [ -d "${LEGACY_TMP}/custom_components/midea_ac_lan" ]; then
        LEGACY_DEPLOY_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
        cp -a "${LEGACY_TMP}/custom_components/midea_ac_lan" "$LEGACY_DEPLOY_DIR"
        echo "  [OK] deployed: ${LEGACY_DEPLOY_DIR}"
    elif [ -d "${LEGACY_TMP}/custom_components/midea_lan" ]; then
        LEGACY_DEPLOY_DIR="${CUSTOM_COMPONENTS}/midea_lan"
        cp -a "${LEGACY_TMP}/custom_components/midea_lan" "$LEGACY_DEPLOY_DIR"
        echo "  [OK] deployed: ${LEGACY_DEPLOY_DIR}"
    else
        echo "  [ERROR] legacy component path not found in ${LEGACY_TMP}"
        exit 1
    fi

    VENDOR_DIR="${LEGACY_DEPLOY_DIR}/_vendor"
    rm -rf "$VENDOR_DIR"
    mkdir -p "$VENDOR_DIR"

    # --- Phase A: Vendor midealocal from GitHub ---
    echo "  > fetch rokam/midea-local"
    LOCAL_OK=0
    if [ -d "${MIDEA_LOCAL_TMP}/.git" ]; then
        cd "$MIDEA_LOCAL_TMP"
        if git pull --ff-only 2>/dev/null; then
            LOCAL_OK=1
        fi
    fi
    if [ "$LOCAL_OK" -eq 0 ]; then
        rm -rf "$MIDEA_LOCAL_TMP_NEW"
        if git clone --depth 1 "$MIDEA_LOCAL_REPO" "$MIDEA_LOCAL_TMP_NEW" 2>&1; then
            rm -rf "$MIDEA_LOCAL_TMP"
            mv "$MIDEA_LOCAL_TMP_NEW" "$MIDEA_LOCAL_TMP"
            LOCAL_OK=1
        fi
    fi
    rm -rf "$MIDEA_LOCAL_TMP_NEW" 2>/dev/null || true
    if [ "$LOCAL_OK" -eq 0 ] && [ ! -d "${MIDEA_LOCAL_TMP}/midealocal" ]; then
        echo "  [ERROR] unable to fetch ${MIDEA_LOCAL_REPO}"
        exit 1
    fi
    cp -a "${MIDEA_LOCAL_TMP}/midealocal" "$VENDOR_DIR/"
    echo "  [OK] vendored midealocal"

    echo "  > patch vendored midealocal __version__"
    python3 - "${VENDOR_DIR}/midealocal/__init__.py" <<'PY'
import pathlib, sys
init_path = pathlib.Path(sys.argv[1])
content = init_path.read_text(encoding="utf-8")
if "__version__" not in content:
    content += (
        "\ntry:\n"
        "    from .version import __version__\n"
        "except ImportError:\n"
        "    __version__ = 'unknown'\n"
    )
    init_path.write_text(content, encoding="utf-8")
PY

    # --- Phase A.5: Patch config_flow.py ---
    # (1) Add "Login to Midea Cloud" action so user can login to 美的美居.
    # (2) Skip LAN discovery validation (UDP fails in container).
    # (3) Use stored login_data for V3 token/key fetch instead of preset account.
    echo "  > patch config_flow.py"
    python3 - "$LEGACY_DEPLOY_DIR" <<'PY'
import os, sys, re

component_dir = sys.argv[1]
cf = os.path.join(component_dir, "config_flow.py")
with open(cf, "r", encoding="utf-8") as f:
    content = f.read()

changed = False

# --- Patch 1: Add "login" to ADD_WAY dict ---
if "ha-phone ADD_WAY login" not in content:
    old_add_way = '''ADD_WAY = {
    "discovery": "Discover automatically",
    "manually": "Configure manually",
    "list": "List all appliances only",
    "cache": "Remove login cache",
}'''
    new_add_way = '''ADD_WAY = {
    "discovery": "Discover automatically",
    "manually": "Configure manually",
    "login": "Login to Midea Cloud",  # ha-phone ADD_WAY login
    "list": "List all appliances only",
    "cache": "Remove login cache",
}'''
    if old_add_way in content:
        content = content.replace(old_add_way, new_add_way)
        changed = True
        print("  [OK] ADD_WAY +login")
    else:
        print("  [WARN] ADD_WAY pattern not found")
else:
    print("  [SKIP] ADD_WAY already patched")

# --- Patch 2: Add "login" handler in async_step_user ---
if "ha-phone login action" not in content:
    old_action = (
        'if user_input["action"] == "manually":\n'
        '                self.found_device = {}\n'
        '                return await self.async_step_manually()'
    )
    new_action = (
        'if user_input["action"] == "login":  # ha-phone login action\n'
        '                self.found_device = {}\n'
        '                self._login_for_manual = True\n'
        '                return await self.async_step_login()\n'
        '            if user_input["action"] == "manually":\n'
        '                self.found_device = {}\n'
        '                return await self.async_step_manually()'
    )
    if old_action in content:
        content = content.replace(old_action, new_action)
        changed = True
        print("  [OK] async_step_user +login action")
    else:
        print("  [WARN] async_step_user login action pattern not found")
else:
    print("  [SKIP] async_step_user already patched")

# --- Patch 3: Patch async_step_login return to support manual flow ---
if "ha-phone login return manual" not in content:
    old_return = (
        '# return to next step after login pass\n'
        '                return await self.async_step_auto()'
    )
    new_return = (
        '# return to next step after login pass\n'
        '                if getattr(self, "_login_for_manual", False):  # ha-phone login return manual\n'
        '                    return await self.async_step_manually()\n'
        '                return await self.async_step_auto()'
    )
    if old_return in content:
        content = content.replace(old_return, new_return)
        changed = True
        print("  [OK] async_step_login return routing")
    else:
        print("  [WARN] async_step_login return pattern not found")
else:
    print("  [SKIP] async_step_login already patched")

# --- Patch 4: Use stored login_data in async_step_manually for V3 token/key ---
if "ha-phone stored login_data" not in content:
    old_login = (
        '# init cloud with preset account\n'
        '                result = await self._check_cloud_login()\n'
        '                if not result:\n'
        '                    return await self.async_step_manually(\n'
        '                        error="Perset account login failed!",\n'
        '                    )'
    )
    new_login = (
        '# init cloud: try stored login_data first, fall back to preset\n'
        '                login_data = self.hass.data.get(DOMAIN, {}).get("login_data", {})  # ha-phone stored login_data\n'
        '                if login_data:\n'
        '                    result = await self._check_cloud_login(\n'
        '                        cloud_name=login_data.get(CONF_SERVER),\n'
        '                        account=login_data.get(CONF_ACCOUNT),\n'
        '                        password=login_data.get(CONF_PASSWORD),\n'
        '                        force_login=True,\n'
        '                    )\n'
        '                else:\n'
        '                    result = await self._check_cloud_login()\n'
        '                if not result:\n'
        '                    return await self.async_step_manually(\n'
        '                        error="Preset account login failed!",\n'
        '                    )'
    )
    if old_login in content:
        content = content.replace(old_login, new_login)
        changed = True
        print("  [OK] async_step_manually stored login_data")
    else:
        print("  [WARN] async_step_manually login_data pattern not found")
else:
    print("  [SKIP] async_step_manually already patched")

# --- Patch 5: Skip LAN discovery validation ---
if "ha-phone manual discovery bypass" not in content:
    needle = (
        r"(\s*# discover result MUST exist\n"
        r"\s*if len\(self\.devices\) != 1:\n"
        r"\s*return await self\.async_step_manually\(error=\"invalid_device_ip\"\))"
    )
    m = re.search(needle, content)
    if m:
        indent = len(m.group(1).splitlines()[1]) - len(m.group(1).splitlines()[1].lstrip())
        i0 = " " * indent
        i1 = " " * (indent + 4)
        i2 = " " * (indent + 8)
        i3 = " " * (indent + 12)
        replacement = (
            f"{i0}# discover result MUST exist\n"
            f"{i0}if len(self.devices) != 1:\n"
            f"{i1}# ha-phone manual discovery bypass: UDP may fail in container\n"
            f"{i1}self.devices = {{\n"
            f"{i2}device_id: {{\n"
            f"{i3}CONF_DEVICE_ID: device_id,\n"
            f"{i3}CONF_IP_ADDRESS: ip,\n"
            f"{i3}CONF_PORT: user_input.get(CONF_PORT, 6444),\n"
            f"{i3}CONF_PROTOCOL: user_input.get(CONF_PROTOCOL, 3),\n"
            f"{i2}}},\n"
            f"{i1}}}"
        )
        content = content.replace(m.group(1), replacement)
        changed = True
        print("  [OK] discovery bypass")
    else:
        print("  [WARN] discovery bypass pattern not found")
else:
    print("  [SKIP] discovery bypass already patched")

if changed:
    with open(cf, "w", encoding="utf-8") as f:
        f.write(content)
    print("  [OK] config_flow.py patched successfully")
else:
    print("  [OK] config_flow.py already fully patched")
PY

    # --- Phase B: Vendor pycryptodome (Crypto) from bundled tarball ---
    echo "  > vendor pycryptodome (Crypto) from bundled tarball"
    CRYPTO_TARBALL="${SCRIPT_DIR}/../lib/Crypto.tar.gz"
    if [ -f "$CRYPTO_TARBALL" ]; then
        tar -xzf "$CRYPTO_TARBALL" -C "$VENDOR_DIR"
        echo "  [OK] Crypto vendored from bundled tarball"
    else
        echo "  [ERROR] Crypto tarball not found: ${CRYPTO_TARBALL}"
        exit 1
    fi

    # --- Phase C: Vendor pure-Python deps ---
    echo "  > vendor pure-Python dependencies (defusedxml, ifaddr)"
    python3 -m pip install --target "$VENDOR_DIR" --no-deps --no-compile defusedxml ifaddr 2>&1 | tail -3
    echo "  [OK] defusedxml + ifaddr vendored"

    # --- Phase D: Create commonregex safety shim ---
    echo "  > create commonregex shim"
    cat > "${VENDOR_DIR}/commonregex.py" <<'PY'
"""Minimal commonregex shim for Home Assistant Termux deployment."""
from __future__ import annotations
import re

class CommonRegex:
    def __init__(self, text: str) -> None:
        self._text = text or ""
        self.emails = re.findall(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", self._text)
        self.links = re.findall(r"https?://[^\s]+", self._text)
        self.ips = re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", self._text)
        self.phones = re.findall(r"\+?\d[\d\s().-]{6,}\d", self._text)

    def __getattr__(self, _name: str):
        return []
PY

    # --- Phase E: Strip midea-local from manifest.json ---
    echo "  > strip midea-local from manifest.json"
    python3 - "$LEGACY_DEPLOY_DIR" <<'PY'
import json, os, sys
component_dir = sys.argv[1]
manifest_path = os.path.join(component_dir, "manifest.json")
with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)
requirements = manifest.get("requirements", [])
manifest["requirements"] = [req for req in requirements if not req.startswith("midea-local")]
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

    # --- Phase F: Insert vendor bootstrap into __init__.py ---
    echo "  > insert vendor bootstrap into __init__.py"
    python3 - "$LEGACY_DEPLOY_DIR" <<'PY'
import os, sys

component_dir = sys.argv[1]
init_path = os.path.join(component_dir, "__init__.py")
with open(init_path, "r", encoding="utf-8") as f:
    content = f.read()

bootstrap = (
    "import os\n"
    "import sys\n"
    "# ha-phone vendor bootstrap\n"
    "_HA_PHONE_VENDOR = os.path.join(os.path.dirname(__file__), \"_vendor\")\n"
    "if _HA_PHONE_VENDOR not in sys.path:\n"
    "    sys.path.insert(0, _HA_PHONE_VENDOR)\n\n"
)
if "# ha-phone vendor bootstrap" not in content:
    lines = content.splitlines(keepends=True)
    insert_at = 0
    if lines and lines[0].startswith("#!"):
        insert_at = 1

    if insert_at < len(lines) and lines[insert_at].startswith(('"""', "'''")):
        quote = lines[insert_at][:3]
        if quote in lines[insert_at][3:]:
            insert_at += 1
        else:
            insert_at += 1
            while insert_at < len(lines):
                if quote in lines[insert_at]:
                    insert_at += 1
                    break
                insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    if insert_at < len(lines) and lines[insert_at].startswith("from __future__ import "):
        insert_at += 1
        while insert_at < len(lines) and lines[insert_at].startswith("from __future__ import "):
            insert_at += 1

    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    lines.insert(insert_at, bootstrap)
    with open(init_path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
PY

    # --- Phase G: Syntax check vendored files ---
    echo "  > syntax check vendored midea_ac_lan"
    python3 -c "
import py_compile, sys, pathlib
vendor_dir = pathlib.Path('${VENDOR_DIR}')
errors = []
for f in vendor_dir.rglob('*.py'):
    try:
        py_compile.compile(str(f), doraise=True)
    except py_compile.PyCompileError as e:
        errors.append(str(e))
if errors:
    for e in errors:
        print(f'SYNTAX ERROR: {e}', file=sys.stderr)
    sys.exit(1)
print('  [OK] all Python files pass syntax check')
"
fi

MANIFEST_PATH="$(find "${CUSTOM_COMPONENTS}" -maxdepth 2 -type f -name manifest.json | grep -E 'midea_ac|midea_ac_lan|midea_lan' | head -1 || true)"
if [ -n "$MANIFEST_PATH" ]; then
    python3 -c "
import json
with open('$MANIFEST_PATH', 'r', encoding='utf-8') as f:
    data = json.load(f)
print('  [OK] domain  :', data.get('domain', 'missing'))
print('  [OK] version :', data.get('version', 'missing'))
req = data.get('requirements', [])
print('  [OK] requirements:', len(req))
for r in req:
    print('      -', r)
" || true
fi

echo ""
echo "========================================="
echo "  Midea integration deployment complete"
echo "========================================="
echo "  Next:"
echo "    1) bash scripts/start-ha.sh"
echo "    2) HA UI -> Settings -> Devices & Services -> Add integration"
echo "    3) Search: Midea AC"
echo ""
echo "  Switch implementation:"
echo "    MIDEA_IMPL=mill   bash scripts/reinstall-midea.sh   (default)"
echo "    MIDEA_IMPL=legacy bash scripts/reinstall-midea.sh"
echo ""
