#!/data/data/com.termux/files/usr/bin/bash
# scripts/reinstall-midea.sh — 可选：部署美的美居集成（局域网）
# 支持空调、热水器等设备，通过 midea_lan 局域网直连
# 不影响 HA 主流程，纯独立脚本
set -euo pipefail

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CUSTOM_COMPONENTS="${HA_CONFIG}/custom_components"
MIDEA_REPO="https://github.com/wuwentao/midea_ac_lan.git"
MIDEA_DIR=""
BAK_DIR="${HA_BASE}/.bak/midea_lan_$(date +%Y%m%d_%H%M%S)"

echo ""
echo "========================================="
echo "  可选：部署美的美居集成 (midea_lan)"
echo "========================================="
echo ""

# 环境检查
if [ ! -d "$HA_BASE" ]; then
    echo "[ERROR] HomeAssistant-Termux 未安装，请先运行 scripts/install.sh"
    exit 1
fi

mkdir -p "$CUSTOM_COMPONENTS"

# Detect installed directory name first.
if [ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ]; then
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
elif [ -d "${CUSTOM_COMPONENTS}/midea_lan" ]; then
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_lan"
else
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
fi

# ── 1. 备份 ─────────────────────────────────────────────────────────────────
if [ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ]; then
    echo "  ▶ 备份现有 midea_ac_lan → ${BAK_DIR} ..."
    mkdir -p "$BAK_DIR"
    cp -a "${CUSTOM_COMPONENTS}/midea_ac_lan" "$BAK_DIR/"
    echo "  ✓ 已备份"
fi
if [ -d "${CUSTOM_COMPONENTS}/midea_lan" ]; then
    echo "  ▶ 备份现有 midea_lan → ${BAK_DIR} ..."
    mkdir -p "$BAK_DIR"
    cp -a "${CUSTOM_COMPONENTS}/midea_lan" "$BAK_DIR/"
    echo "  ✓ 已备份"
fi

# ── 2. 清理旧部署 ──────────────────────────────────────────────────────────
echo "  ▶ 清理旧部署 ..."
if [ -d "${CUSTOM_COMPONENTS}/midea_ac_lan" ]; then
    rm -rf "${CUSTOM_COMPONENTS}/midea_ac_lan"
    echo "  ✓ 已删除旧目录 midea_ac_lan"
fi
if [ -d "${CUSTOM_COMPONENTS}/midea_lan" ]; then
    rm -rf "${CUSTOM_COMPONENTS}/midea_lan"
    echo "  ✓ 已删除旧目录 midea_lan"
fi
find "$CUSTOM_COMPONENTS" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# ── 3. 拉取 ─────────────────────────────────────────────────────────────────
echo "  ▶ 拉取 midea_ac_lan ..."
MIDEA_TMP="${HOME}/.cache/midea_ac_lan"

if [ -d "${MIDEA_TMP}/.git" ]; then
    cd "$MIDEA_TMP"
    git pull --ff-only 2>/dev/null || {
        echo "  [WARN] git pull 失败，重新 clone ..."
        rm -rf "$MIDEA_TMP"
        git clone --depth 1 "$MIDEA_REPO" "$MIDEA_TMP" 2>&1
    }
else
    rm -rf "$MIDEA_TMP"
    git clone --depth 1 "$MIDEA_REPO" "$MIDEA_TMP" 2>&1
fi
echo "  ✓ 拉取完成"

# ── 4. 部署 ─────────────────────────────────────────────────────────────────
echo "  ▶ 部署到 custom_components ..."

# 组件目录可能在 custom_components 子目录，也可能在仓库根目录
SRC=""
if [ -d "${MIDEA_TMP}/custom_components/midea_ac_lan" ]; then
    SRC="${MIDEA_TMP}/custom_components/midea_ac_lan"
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_ac_lan"
elif [ -d "${MIDEA_TMP}/custom_components/midea_lan" ]; then
    SRC="${MIDEA_TMP}/custom_components/midea_lan"
    MIDEA_DIR="${CUSTOM_COMPONENTS}/midea_lan"
elif [ -f "${MIDEA_TMP}/manifest.json" ]; then
    # Root layout fallback: detect domain from manifest.
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
    echo "  [ERROR] 找不到 midea 组件目录，请检查仓库结构"
    echo "  手动查看: ls ${MIDEA_TMP}/"
    exit 1
fi

cp -a "$SRC" "$MIDEA_DIR"
echo "  ✓ 已部署: ${MIDEA_DIR}"

# 部署后立即尝试打补丁（依赖若尚未安装，会在启动后再次补）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "${SCRIPT_DIR}/patch-midea.sh" || echo "  [WARN] patch-midea.sh 失败"

# ── 5. 验证 ─────────────────────────────────────────────────────────────────
echo "  ▶ 验证 manifest.json ..."
MANIFEST="${MIDEA_DIR}/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "  [ERROR] manifest.json 不存在"
    exit 1
fi

python3 -c "
import json, sys
try:
    with open('$MANIFEST') as f:
        data = json.load(f)
    domain = data.get('domain', 'missing')
    version = data.get('version', 'missing')
    print(f'  ✓ domain  : {domain}')
    print(f'  ✓ version : {version}')
    if 'requirements' in data:
        print(f'  ✓ requirements: {len(data[\"requirements\"])} packages')
        for r in data['requirements']:
            print(f'      - {r}')
except json.JSONDecodeError as e:
    print(f'  [ERROR] manifest.json 非法: {e}')
    sys.exit(1)
"

# ── 6. 完成 ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  美的美居集成部署完毕"
echo "─────────────────────────────────────────"
echo ""
echo "  下一步:"
echo "    1. 重启 HA: sh scripts/start-ha.sh"
echo "    2. HA 前端 → 设置 → 添加集成 → 搜索 'Midea'"
echo "    3. 若自动发现为空，直接手动输入设备 IP"
echo ""
echo "  支持设备类型（局域网自动发现）:"
echo "    - 空调（含风尊系列）"
echo "    - 热水器"
echo "    - 洗衣机"
echo "    - 洗碗机"
echo ""
echo "  注意:"
echo "    - 美的设备需和手机在同一局域网"
echo "    - 部分设备需在美的美居 App 中开启局域网控制"
echo "    - 如遇问题可重新运行本脚本更新到最新版"
echo ""
echo "  如需删除此集成:"
echo "    rm -rf ~/HomeAssistant-Termux/haconfig/custom_components/midea_ac_lan"
echo "    rm -rf ~/HomeAssistant-Termux/haconfig/custom_components/midea_lan"
echo ""
