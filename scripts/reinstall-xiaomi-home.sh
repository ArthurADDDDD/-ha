#!/data/data/com.termux/files/usr/bin/bash
# scripts/reinstall-xiaomi-home.sh — 重新部署 Xiaomi Home 集成
# 操作流程: 备份 → 清理 → 拉取 → 部署 → 验证
set -euo pipefail

HA_BASE="${HOME}/HomeAssistant-Termux"
HA_CONFIG="${HA_BASE}/haconfig"
CUSTOM_COMPONENTS="${HA_CONFIG}/custom_components"
XIAOMI_DIR="${CUSTOM_COMPONENTS}/xiaomi_home"
XIAOMI_REPO="https://github.com/XiaoMi/ha_xiaomi_home.git"
BAK_DIR="${HA_BASE}/.bak/xiaomi_home_$(date +%Y%m%d_%H%M%S)"

echo ""
echo "========================================="
echo "  重新部署 Xiaomi Home 集成"
echo "========================================="
echo ""

# ── 1. 备份 ─────────────────────────────────────────────────────────────────
if [ -d "$XIAOMI_DIR" ]; then
    echo "  ▶ 备份现有 xiaomi_home → ${BAK_DIR} ..."
    mkdir -p "$BAK_DIR"
    cp -a "$XIAOMI_DIR" "$BAK_DIR/"
    echo "  ✓ 已备份"
fi

# ── 2. 清理 ─────────────────────────────────────────────────────────────────
echo "  ▶ 清理旧部署 ..."

# 删除旧目录
if [ -d "$XIAOMI_DIR" ]; then
    rm -rf "$XIAOMI_DIR"
    echo "  ✓ 已删除: $XIAOMI_DIR"
fi

# 清理残留 pyc 缓存
find "$CUSTOM_COMPONENTS" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find "$CUSTOM_COMPONENTS" -name "*.pyc" -delete 2>/dev/null || true

# ── 3. 拉取最新集成 ─────────────────────────────────────────────────────────
echo "  ▶ 拉取 ha_xiaomi_home ..."
XIAOMI_TMP="${HOME}/.cache/ha_xiaomi_home"

if [ -d "${XIAOMI_TMP}/.git" ]; then
    cd "$XIAOMI_TMP"
    git pull --ff-only 2>/dev/null || {
        echo "  [WARN] git pull 失败，重新 clone ..."
        rm -rf "$XIAOMI_TMP"
        git clone --depth 1 "$XIAOMI_REPO" "$XIAOMI_TMP" 2>&1
    }
else
    rm -rf "$XIAOMI_TMP"
    git clone --depth 1 "$XIAOMI_REPO" "$XIAOMI_TMP" 2>&1
fi
echo "  ✓ 拉取完成"

# ── 4. 部署 ─────────────────────────────────────────────────────────────────
echo "  ▶ 部署到 haconfig ..."
mkdir -p "$CUSTOM_COMPONENTS"

SRC="${XIAOMI_TMP}/custom_components/xiaomi_home"
if [ ! -d "$SRC" ]; then
    echo "  [ERROR] 源目录不存在: $SRC"
    exit 1
fi

cp -a "$SRC" "$XIAOMI_DIR"
echo "  ✓ 已部署: $XIAOMI_DIR"

# ── 5. 验证 ─────────────────────────────────────────────────────────────────
echo "  ▶ 验证 manifest.json ..."
MANIFEST="${XIAOMI_DIR}/manifest.json"
if [ ! -f "$MANIFEST" ]; then
    echo "  [ERROR] manifest.json 不存在！部署可能不完整"
    exit 1
fi

# 用 Python 验证 JSON 合法性（不做任何修改）
python3 -c "
import json, sys
try:
    with open('$MANIFEST') as f:
        data = json.load(f)
    domain = data.get('domain', 'missing')
    version = data.get('version', 'missing')
    deps = data.get('requirements', [])
    print(f'  ✓ domain      : {domain}')
    print(f'  ✓ version     : {version}')
    print(f'  ✓ requirements: {len(deps)} packages')
    if domain != 'xiaomi_home':
        print('  [WARN] domain 不是 xiaomi_home，可能有问题')
        sys.exit(1)
except json.JSONDecodeError as e:
    print(f'  [ERROR] manifest.json 非法: {e}')
    print('  请不要手动编辑此文件。如有问题重新运行本脚本。')
    sys.exit(1)
except Exception as e:
    print(f'  [ERROR] {e}')
    sys.exit(1)
"

# ── 6. 完成 ─────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "  Xiaomi Home 部署完毕"
echo "─────────────────────────────────────────"
echo ""
echo "  下一步:"
echo "    sh scripts/start-ha.sh             启动 HA"
echo "    然后在 HA 前端 → 设置 → 添加集成 → 搜索 'Xiaomi Home'"
echo ""
echo "  如果前端找不到 Xiaomi Home:"
echo "    - 检查: sh scripts/check-ha.sh"
echo "    - 确认 HA 版本 >= 2024.4.4"
echo "    - 重启 HA 后等待 60 秒再搜索"
echo ""
