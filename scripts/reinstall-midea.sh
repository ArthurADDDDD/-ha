#!/data/data/com.termux/files/usr/bin/bash
# scripts/reinstall-midea.sh - install/update Midea LAN custom component
set -euo pipefail

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CUSTOM_COMPONENTS="${HA_CONFIG}/custom_components"
MIDEA_REPO_PRIMARY="https://github.com/wuwentao/midea_ac_lan.git"
MIDEA_REPO_FALLBACK="https://github.com/wuwentao/midea_lan.git"
MIDEA_TMP="${HOME}/.cache/midea_ac_lan"
MIDEA_TMP_NEW="${MIDEA_TMP}.new.$$"
BAK_DIR="${HA_BASE}/.bak/midea_lan_$(date +%Y%m%d_%H%M%S)"
MIDEA_DIR=""

echo ""
echo "========================================="
echo "  Optional: Install Midea LAN integration"
echo "========================================="
echo ""

if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux not found. Run scripts/install.sh first."
    exit 1
fi

mkdir -p "$CUSTOM_COMPONENTS"

if [ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ]; then
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
elif [ -d "${CUSTOM_COMPONENTS}/midea_lan" ]; then
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_lan"
else
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
fi

if [ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ] || [ -d "${CUSTOM_COMPONENTS}/midea_lan" ]; then
    echo "  > backup existing component to ${BAK_DIR}"
    mkdir -p "$BAK_DIR"
    [ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ] && cp -a "${CUSTOM_COMPONENTS}/midea_ac_lan" "$BAK_DIR/" || true
    [ -d "${CUSTOM_COMPONENTS}/midea_lan" ] && cp -a "${CUSTOM_COMPONENTS}/midea_lan" "$BAK_DIR/" || true
fi

echo "  > remove old deployment"
[ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ] && rm -rf "${CUSTOM_COMPONENTS}/midea_ac_lan" || true
[ -d "${CUSTOM_COMPONENTS}/midea_lan" ] && rm -rf "${CUSTOM_COMPONENTS}/midea_lan" || true
find "$CUSTOM_COMPONENTS" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

echo "  > fetch upstream repository"
PULL_OK=0
if [ -d "${MIDEA_TMP}/.git" ]; then
    cd "$MIDEA_TMP"
    if git pull --ff-only 2>/dev/null; then
        PULL_OK=1
    else
        echo "  [WARN] git pull failed, trying fresh clone ..."
    fi
fi

if [ "$PULL_OK" -eq 0 ]; then
    rm -rf "$MIDEA_TMP_NEW"
    if git clone --depth 1 "$MIDEA_REPO_PRIMARY" "$MIDEA_TMP_NEW" 2>&1; then
        rm -rf "$MIDEA_TMP"
        mv "$MIDEA_TMP_NEW" "$MIDEA_TMP"
        PULL_OK=1
    else
        echo "  [WARN] primary repo failed, trying fallback repo ..."
        rm -rf "$MIDEA_TMP_NEW"
        if git clone --depth 1 "$MIDEA_REPO_FALLBACK" "$MIDEA_TMP_NEW" 2>&1; then
            rm -rf "$MIDEA_TMP"
            mv "$MIDEA_TMP_NEW" "$MIDEA_TMP"
            PULL_OK=1
        fi
    fi
fi

rm -rf "$MIDEA_TMP_NEW" 2>/dev/null || true

if [ "$PULL_OK" -eq 0 ]; then
    if [ -d "${MIDEA_TMP}/.git" ]; then
        echo "  [WARN] network failed; using existing local cache: ${MIDEA_TMP}"
    else
        echo "  [ERROR] unable to fetch midea repository from both sources"
        echo "  [HINT] check network access to github.com and retry"
        exit 1
    fi
fi
echo "  [OK] repository is ready"

echo "  > deploy to custom_components"
SRC=""
if [ -d "${MIDEA_TMP}/custom_components/midea_ac_lan" ]; then
    SRC="${MIDEA_TMP}/custom_components/midea_ac_lan"
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
elif [ -d "${MIDEA_TMP}/custom_components/midea_lan" ]; then
    SRC="${MIDEA_TMP}/custom_components/midea_lan"
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_lan"
elif [ -f "${MIDEA_TMP}/manifest.json" ]; then
    DOMAIN="$(python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.cache/midea_ac_lan/manifest.json")
try:
    with open(p, "r", encoding="utf-8") as f:
        d = json.load(f)
    print(d.get("domain", "midea_ac_lan"))
except Exception:
    print("midea_ac_lan")
PY
)"
    SRC="${MIDEA_TMP}"
    MIDEA_DIR="${CUSTOM_COMPONENTS}/${DOMAIN}"
else
    echo "  [ERROR] component source path not found in ${MIDEA_TMP}"
    exit 1
fi

cp -a "$SRC" "$MIDEA_DIR"
echo "  [OK] deployed: ${MIDEA_DIR}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "${SCRIPT_DIR}/patch-midea.sh" || echo "  [WARN] patch-midea.sh failed"

MANIFEST="${MIDEA_DIR}/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "  [ERROR] manifest.json missing after deployment"
    exit 1
fi

python3 -c "
import json, sys
with open('$MANIFEST', 'r', encoding='utf-8') as f:
    data = json.load(f)
print('  [OK] domain  :', data.get('domain', 'missing'))
print('  [OK] version :', data.get('version', 'missing'))
req = data.get('requirements', [])
print('  [OK] requirements:', len(req))
for r in req:
    print('      -', r)
" || exit 1

echo ""
echo "========================================="
echo "  Midea integration deployment complete"
echo "========================================="
echo "  Next:"
echo "    1) sh scripts/start-ha.sh"
echo "    2) HA UI -> Settings -> Devices & Services -> Add integration -> Midea"
echo "    3) If discovery is empty, manually input device IP"
echo ""
