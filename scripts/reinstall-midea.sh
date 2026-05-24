#!/data/data/com.termux/files/usr/bin/bash
# scripts/reinstall-midea.sh - install/update Midea integration
set -euo pipefail

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

    if [ -d "${LEGACY_TMP}/custom_components/midea_ac_lan" ]; then
        cp -a "${LEGACY_TMP}/custom_components/midea_ac_lan" "${CUSTOM_COMPONENTS}/midea_ac_lan"
        echo "  [OK] deployed: ${CUSTOM_COMPONENTS}/midea_ac_lan"
    elif [ -d "${LEGACY_TMP}/custom_components/midea_lan" ]; then
        cp -a "${LEGACY_TMP}/custom_components/midea_lan" "${CUSTOM_COMPONENTS}/midea_lan"
        echo "  [OK] deployed: ${CUSTOM_COMPONENTS}/midea_lan"
    else
        echo "  [ERROR] legacy component path not found in ${LEGACY_TMP}"
        exit 1
    fi
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
