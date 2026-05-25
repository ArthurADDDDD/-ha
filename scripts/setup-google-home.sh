#!/data/data/com.termux/files/usr/bin/bash
# scripts/setup-google-home.sh — 半自动 Google Home 桥接部署
# 幂等：可安全重复执行，已完成的步骤会自动跳过
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 引入共享工具库 ──
if [ -f "${REPO_DIR}/lib/utils.sh" ]; then
    source "${REPO_DIR}/lib/utils.sh"
else
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'; C_RESET='\033[0m'
    HA_BASE="${HOME}/HomeAssistant-Termux"
    HA_CONFIG="${HA_BASE}/haconfig"
    log_info()  { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*"; }
    log_warn()  { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*"; }
    log_error() { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$*"; }
    log_ok()    { printf "${C_GREEN}[OK]${C_RESET}    %s\n" "$*"; }
    log_step()  { printf "\n${C_BLUE}==>${C_RESET} %s\n" "$*"; }
fi

C_BOLD_GREEN='\033[1;32m'
C_BOLD_YELLOW='\033[1;33m'
C_BOLD_CYAN='\033[1;36m'
C_BOLD_RED='\033[1;31m'

# ── 状态文件 ──
STATE_FILE="${REPO_DIR}/.google_home_env"
touch "$STATE_FILE" 2>/dev/null || true

get_state() { grep "^${1}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- || true; }
set_state() {
    if grep -q "^${1}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^${1}=.*|${1}=${2}|" "$STATE_FILE"
    else
        echo "${1}=${2}" >> "$STATE_FILE"
    fi
}

# ── 辅助函数 ──
prompt_human() {
    printf "\n${C_BOLD_GREEN}========================================${C_RESET}\n"
    printf "${C_BOLD_GREEN}  >>>  需要人工操作  <<<${C_RESET}\n"
    printf "${C_BOLD_GREEN}========================================${C_RESET}\n\n"
}

wait_for_enter() {
    printf "\n${C_BOLD_CYAN}完成后按 Enter 继续...${C_RESET}"
    read -r
}

press_enter_to_continue() {
    printf "\n${C_BOLD_CYAN}按 Enter 继续...${C_RESET}"
    read -r
}

# ── 前置检查 ──
check_prerequisites() {
    echo ""
    echo "========================================="
    echo "  Google Home Bridge 部署向导"
    echo "  半自动交互式配置"
    echo "========================================="
    echo ""

    if [ ! -d "/data/data/com.termux" ]; then
        log_error "请在 Termux 环境中运行此脚本"
        exit 1
    fi

    if [ ! -d "$HA_BASE" ]; then
        log_error "HomeAssistant-Termux 未找到，请先运行 scripts/install.sh"
        exit 1
    fi

    ensure_dir() { mkdir -p "$1"; }
    ensure_dir "$HA_CONFIG"
    ensure_dir "$REPO_DIR/config"

    log_ok "环境检查通过"
}

# ════════════════════════════════════════════════════════════════════════════════
# 阶段 1：ngrok 内网穿透
# ════════════════════════════════════════════════════════════════════════════════
phase1_ngrok() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "  阶段 1/4：ngrok 内网穿透"
    echo "─────────────────────────────────────────"

    # ── 1.1 检查/安装 ngrok ──
    if command -v ngrok >/dev/null 2>&1; then
        log_ok "ngrok 已安装: $(ngrok version 2>&1 | head -1)"
    else
        log_info "ngrok 未安装，尝试从 Termux 源安装..."
        if pkg install ngrok -y 2>/dev/null; then
            log_ok "ngrok 安装成功"
        else
            log_warn "pkg 安装失败，尝试直接下载二进制..."
            NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
            NGROK_TMP="/tmp/ngrok-install-$$"
            mkdir -p "$NGROK_TMP"

            if curl -fsSL "$NGROK_URL" -o "$NGROK_TMP/ngrok.tgz" 2>/dev/null; then
                tar xzf "$NGROK_TMP/ngrok.tgz" -C "$NGROK_TMP"
                cp "$NGROK_TMP/ngrok" "${HOME}/../usr/bin/ngrok"
                chmod +x "${HOME}/../usr/bin/ngrok"
                rm -rf "$NGROK_TMP"
                log_ok "ngrok 安装成功: $(ngrok version 2>&1 | head -1)"
            else
                rm -rf "$NGROK_TMP"
                echo ""
                prompt_human
                printf "${C_BOLD_YELLOW}无法自动安装 ngrok。请手动操作：${C_RESET}\n\n"
                echo "  1. 浏览器访问 https://ngrok.com/download"
                echo "  2. 下载 Linux ARM64 版本"
                echo "  3. 解压并将 ngrok 二进制放入 PATH（如 ~/../usr/bin/）"
                echo "  4. chmod +x ~/../usr/bin/ngrok"
                echo ""
                log_error "请安装 ngrok 后重新运行此脚本"
                exit 1
            fi
        fi
    fi

    # ── 1.2 检查/配置 authtoken ──
    NGROK_CONFIG="${HOME}/.config/ngrok/ngrok.yml"
    if [ -f "$NGROK_CONFIG" ] && grep -q "authtoken" "$NGROK_CONFIG" 2>/dev/null; then
        log_ok "ngrok authtoken 已配置"
    else
        prompt_human
        printf "${C_BOLD_YELLOW}需要 ngrok 账号的 authtoken。${C_RESET}\n\n"
        echo "  1. 浏览器访问 https://dashboard.ngrok.com/signup"
        echo "     免费注册一个 ngrok 账号（用 Google 或 GitHub 登录即可）"
        echo ""
        echo "  2. 登录后访问 https://dashboard.ngrok.com/get-started/your-authtoken"
        echo "     复制你的 authtoken（一串字符串）"
        echo ""
        echo "  3. 回到此处，粘贴 authtoken："
        echo ""

        read -r -p "  authtoken: " NGROK_TOKEN
        if [ -z "$NGROK_TOKEN" ]; then
            log_error "authtoken 不能为空，已取消"
            exit 1
        fi

        ngrok config add-authtoken "$NGROK_TOKEN"
        log_ok "authtoken 已保存"
    fi

    # ── 1.3 获取/确认静态域名 ──
    EXISTING_DOMAIN=$(get_state "NGROK_DOMAIN")
    if [ -n "$EXISTING_DOMAIN" ]; then
        log_info "已记录的 ngrok 域名: ${EXISTING_DOMAIN}"
        printf "是否继续使用此域名？[Y/n] "
        read -r USE_EXISTING
        if [ "${USE_EXISTING:-Y}" = "Y" ] || [ "${USE_EXISTING:-Y}" = "y" ]; then
            NGROK_DOMAIN="$EXISTING_DOMAIN"
        else
            EXISTING_DOMAIN=""
        fi
    fi

    if [ -z "${EXISTING_DOMAIN:-}" ]; then
        prompt_human
        printf "${C_BOLD_YELLOW}需要设置一个静态 ngrok 域名。${C_RESET}\n\n"
        echo "  ngrok 免费版支持 1 个静态域名，格式为 <name>.ngrok-free.app"
        echo ""
        echo "  设置步骤："
        echo "  1. 浏览器访问 https://dashboard.ngrok.com/cloud-edge/domains"
        echo "  2. 点击 'Create Domain' 或 'New Domain'"
        echo "  3. 输入你想要的名称（如 my-ha），创建域名"
        echo "  4. 记下完整的域名（如 my-ha.ngrok-free.app）"
        echo ""
        echo "  回到此处，输入你的域名："
        echo ""

        read -r -p "  域名 (不含 https://): " NGROK_DOMAIN
        if [ -z "$NGROK_DOMAIN" ]; then
            log_error "域名不能为空，已取消"
            exit 1
        fi
        # 去掉可能误输入的协议前缀
        NGROK_DOMAIN="${NGROK_DOMAIN#https://}"
        NGROK_DOMAIN="${NGROK_DOMAIN#http://}"

        set_state "NGROK_DOMAIN" "$NGROK_DOMAIN"
        log_ok "域名已记录: ${NGROK_DOMAIN}"
    fi

    # ── 1.4 创建 ngrok 启动辅助脚本 ──
    NGROK_RUNNER="${REPO_DIR}/scripts/run-ngrok.sh"

    cat > "$NGROK_RUNNER" << RUNNER_EOF
#!/data/data/com.termux/files/usr/bin/bash
# scripts/run-ngrok.sh — 启动 ngrok 隧道（后台运行 + 日志）
set -euo pipefail

DOMAIN="${NGROK_DOMAIN}"
LOGFILE="${HA_BASE}/ngrok.log"
PIDFILE="/tmp/ngrok-ha.pid"

# 杀掉旧进程
if [ -f "\$PIDFILE" ]; then
    OLDPID=\$(cat "\$PIDFILE")
    if kill -0 "\$OLDPID" 2>/dev/null; then
        echo "[INFO] 停止旧 ngrok 进程 (PID: \$OLDPID)"
        kill "\$OLDPID" 2>/dev/null || true
        sleep 1
    fi
    rm -f "\$PIDFILE"
fi

# 清理残留的 ngrok 进程
pkill -f "ngrok http.*8123" 2>/dev/null || true
sleep 0.5

echo "[INFO] 启动 ngrok: https://\${DOMAIN} -> http://localhost:8123"
nohup ngrok http --domain="\${DOMAIN}" 8123 > "\$LOGFILE" 2>&1 &
NGROK_PID=\$!
echo \$NGROK_PID > "\$PIDFILE"

sleep 2
if kill -0 "\$NGROK_PID" 2>/dev/null; then
    echo "[OK]   ngrok 已启动 (PID: \$NGROK_PID)"
    echo "      公网地址: https://\${DOMAIN}"
    echo "      日志文件: \${LOGFILE}"
else
    echo "[ERROR] ngrok 启动失败，查看日志: \${LOGFILE}"
    tail -20 "\${LOGFILE}"
    exit 1
fi
RUNNER_EOF

    chmod +x "$NGROK_RUNNER"
    log_ok "已生成 ngrok 启动脚本: scripts/run-ngrok.sh"

    # ── 1.5 测试启动 ngrok ──
    echo ""
    log_info "正在测试启动 ngrok 隧道..."

    # 先清理旧进程
    pkill -f "ngrok http.*8123" 2>/dev/null || true
    sleep 0.5

    LOGFILE="${HA_BASE}/ngrok.log"
    nohup ngrok http --domain="$NGROK_DOMAIN" 8123 > "$LOGFILE" 2>&1 &
    NGROK_PID=$!

    # 等待 ngrok 启动
    for i in $(seq 1 10); do
        sleep 1
        if grep -q "started tunnel" "$LOGFILE" 2>/dev/null; then
            break
        fi
        if ! kill -0 "$NGROK_PID" 2>/dev/null; then
            log_error "ngrok 进程意外退出，查看日志:"
            echo ""
            tail -30 "$LOGFILE"
            echo ""
            log_error "常见原因：域名已占用、authtoken 无效、网络问题"
            exit 1
        fi
    done

    if grep -q "started tunnel" "$LOGFILE" 2>/dev/null; then
        log_ok "ngrok 隧道已成功建立！"
        FULFILLMENT_URL="https://${NGROK_DOMAIN}/api/google_assistant"
        set_state "FULFILLMENT_URL" "$FULFILLMENT_URL"

        echo ""
        printf "${C_BOLD_GREEN}  Fulfillment URL: ${FULFILLMENT_URL}${C_RESET}\n"
        echo "  (该地址暂不可用，需要 HA 配置 google_assistant 集成后才生效)"
        echo ""
    else
        log_warn "ngrok 可能未完全就绪，请手动检查: tail -f $LOGFILE"
    fi
}

# ════════════════════════════════════════════════════════════════════════════════
# 阶段 2：GCP 与 HomeGraph API
# ════════════════════════════════════════════════════════════════════════════════
phase2_gcp() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "  阶段 2/4：GCP 与 HomeGraph API"
    echo "─────────────────────────────────────────"

    # ── 2.1 检查/安装 gcloud CLI ──
    if command -v gcloud >/dev/null 2>&1; then
        log_ok "gcloud CLI 已安装"
    else
        log_info "gcloud CLI 未安装，尝试安装..."
        GCLOUD_TARBALL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz"
        GCLOUD_TMP="/tmp/gcloud-install-$$"

        mkdir -p "$GCLOUD_TMP"
        if curl -fsSL "$GCLOUD_TARBALL" -o "$GCLOUD_TMP/gcloud.tar.gz" 2>/dev/null; then
            tar xzf "$GCLOUD_TMP/gcloud.tar.gz" -C "${HOME}"
            "${HOME}/google-cloud-sdk/install.sh" --quiet --usage-reporting=false --path-update=false
            # 添加到 PATH
            export PATH="${HOME}/google-cloud-sdk/bin:${PATH}"
            if [ -f "${HOME}/google-cloud-sdk/path.bash.inc" ]; then
                source "${HOME}/google-cloud-sdk/path.bash.inc"
            fi
            rm -rf "$GCLOUD_TMP"
            log_ok "gcloud CLI 安装成功"
        else
            rm -rf "$GCLOUD_TMP"
            echo ""
            prompt_human
            printf "${C_BOLD_YELLOW}无法自动安装 gcloud CLI。请手动操作：${C_RESET}\n\n"
            echo "  方法 1（推荐）：在电脑上用浏览器完成 GCP 设置"
            echo "    a) 访问 https://console.cloud.google.com"
            echo "    b) 创建项目、启用 HomeGraph API、创建 Service Account"
            echo "    c) 下载 JSON 密钥传到手机: $HA_CONFIG/google_service_account.json"
            echo "    d) 手动运行此脚本的后续步骤"
            echo ""
            echo "  方法 2：在 Termux 中手动安装 gcloud"
            echo "    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz"
            echo "    tar xzf google-cloud-cli-linux-arm.tar.gz -C ~"
            echo "    ~/google-cloud-sdk/install.sh"
            echo ""
            log_error "请安装 gcloud CLI 后重新运行此脚本，或使用上述方法 1"
            exit 1
        fi
    fi

    # ── 2.2 gcloud 登录 ──
    GCLOUD_ACCOUNT=$(gcloud auth list --format='value(account)' 2>/dev/null | head -1 || true)
    if [ -n "$GCLOUD_ACCOUNT" ]; then
        log_ok "gcloud 已登录: ${GCLOUD_ACCOUNT}"
    else
        prompt_human
        printf "${C_BOLD_YELLOW}即将打开 Google 登录页面。${C_RESET}\n\n"
        echo "  请在浏览器中完成 Google 账号登录并授权 gcloud CLI。"
        echo ""

        gcloud auth login --no-browser --quiet 2>&1 | tee /tmp/gcloud-login.log &
        GCLOUD_LOGIN_PID=$!

        sleep 2
        GCLOUD_URL=$(grep -o 'https://[^[:space:]]*' /tmp/gcloud-login.log 2>/dev/null | head -1 || true)
        if [ -n "$GCLOUD_URL" ]; then
            printf "${C_BOLD_GREEN}请打开以下 URL 完成登录：${C_RESET}\n"
            printf "${C_BOLD_CYAN}%s${C_RESET}\n\n" "$GCLOUD_URL"
        fi

        # 等待登录完成（最多 3 分钟）
        for i in $(seq 1 90); do
            sleep 2
            GCLOUD_ACCOUNT=$(gcloud auth list --format='value(account)' 2>/dev/null | head -1 || true)
            if [ -n "$GCLOUD_ACCOUNT" ]; then
                break
            fi
            if ! kill -0 "$GCLOUD_LOGIN_PID" 2>/dev/null; then
                break
            fi
        done

        kill "$GCLOUD_LOGIN_PID" 2>/dev/null || true
        wait "$GCLOUD_LOGIN_PID" 2>/dev/null || true

        GCLOUD_ACCOUNT=$(gcloud auth list --format='value(account)' 2>/dev/null | head -1 || true)
        if [ -z "$GCLOUD_ACCOUNT" ]; then
            log_error "gcloud 登录失败或超时，请重试"
            exit 1
        fi
        log_ok "gcloud 登录成功: ${GCLOUD_ACCOUNT}"
    fi

    # ── 2.3 创建/选择 GCP 项目 ──
    EXISTING_PROJECT=$(get_state "GCP_PROJECT_ID")
    if [ -n "$EXISTING_PROJECT" ] && gcloud projects describe "$EXISTING_PROJECT" >/dev/null 2>&1; then
        log_ok "GCP 项目已存在: ${EXISTING_PROJECT}"
        GCP_PROJECT_ID="$EXISTING_PROJECT"
    else
        # 生成唯一 Project ID
        if [ -z "${EXISTING_PROJECT:-}" ]; then
            GCP_PROJECT_ID="ha-gh-$(date +%s | sha256sum 2>/dev/null | head -c 8 || echo "$(date +%s)" | tail -c 8)"
        else
            GCP_PROJECT_ID="$EXISTING_PROJECT"
        fi

        if gcloud projects describe "$GCP_PROJECT_ID" >/dev/null 2>&1; then
            log_ok "GCP 项目已存在: ${GCP_PROJECT_ID}"
        else
            log_info "创建 GCP 项目: ${GCP_PROJECT_ID}"
            if gcloud projects create "$GCP_PROJECT_ID" --name="HA Google Home Bridge" 2>&1; then
                log_ok "项目创建成功"
            else
                echo ""
                prompt_human
                printf "${C_BOLD_YELLOW}项目创建失败。可能原因：${C_RESET}\n"
                echo "  - 项目 ID 已被占用（极小概率）"
                echo "  - 账号没有创建项目的权限"
                echo "  - 需要验证 billing account"
                echo ""
                echo "  请手动在浏览器中创建项目："
                echo "  https://console.cloud.google.com/projectcreate"
                echo ""
                echo "  创建完成后，输入项目 ID："
                read -r -p "  项目 ID: " GCP_PROJECT_ID
                if [ -z "$GCP_PROJECT_ID" ]; then
                    log_error "项目 ID 不能为空"
                    exit 1
                fi
            fi
        fi
        set_state "GCP_PROJECT_ID" "$GCP_PROJECT_ID"
    fi

    # 设置为当前项目
    gcloud config set project "$GCP_PROJECT_ID" --quiet

    # ── 2.4 启用 HomeGraph API ──
    if gcloud services list --enabled --project="$GCP_PROJECT_ID" 2>/dev/null | grep -q "homegraph.googleapis.com"; then
        log_ok "HomeGraph API 已启用"
    else
        log_info "启用 HomeGraph API (免费，不会产生费用)..."
        if gcloud services enable homegraph.googleapis.com --project="$GCP_PROJECT_ID" 2>&1; then
            log_ok "HomeGraph API 已启用"
        else
            log_warn "HomeGraph API 启用失败，请确认项目已绑定 billing account"
            log_info "你可能需要先访问 https://console.cloud.google.com/billing 设置结算账号"
            echo ""
            printf "${C_BOLD_YELLOW}是否跳过此步骤继续？[y/N] ${C_RESET}"
            read -r SKIP_API
            if [ "${SKIP_API:-N}" != "y" ] && [ "${SKIP_API:-N}" != "Y" ]; then
                exit 1
            fi
        fi
    fi

    # ── 2.5 创建 Service Account ──
    SA_NAME="ha-homegraph-sa"
    SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

    if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
        log_ok "Service Account 已存在: ${SA_EMAIL}"
    else
        log_info "创建 Service Account: ${SA_NAME}"
        gcloud iam service-accounts create "$SA_NAME" \
            --display-name="HA HomeGraph Service Account" \
            --project="$GCP_PROJECT_ID" \
            --quiet
        log_ok "Service Account 已创建"
    fi

    # ── 2.6 授予 HomeGraph Admin 角色 ──
    log_info "授予 roles/homegraph.admin 权限..."
    gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/homegraph.admin" \
        --quiet 2>/dev/null || {
        log_warn "授予 homegraph.admin 角色失败，可能需要项目所有者权限"
        log_info "你可以稍后在 IAM 页面手动添加: https://console.cloud.google.com/iam-admin/iam"
    }

    # ── 2.7 下载 JSON 密钥 ──
    SA_KEY_HA="${HA_CONFIG}/google_service_account.json"
    SA_KEY_REPO="${REPO_DIR}/config/google_service_account.json"

    if [ -f "$SA_KEY_HA" ]; then
        log_ok "Service Account 密钥已存在: ${SA_KEY_HA}"
    else
        log_info "下载 Service Account 密钥..."
        gcloud iam service-accounts keys create "$SA_KEY_HA" \
            --iam-account="$SA_EMAIL" \
            --project="$GCP_PROJECT_ID" \
            --quiet 2>/dev/null || {
            log_error "密钥下载失败"
            log_info "你可以在 GCP Console 手动下载:"
            echo "  https://console.cloud.google.com/iam-admin/serviceaccounts/details/${SA_EMAIL}/keys"
            exit 1
        }
        log_ok "密钥已保存: ${SA_KEY_HA}"
    fi

    # 同步到 repo
    if [ "$SA_KEY_HA" != "$SA_KEY_REPO" ]; then
        cp "$SA_KEY_HA" "$SA_KEY_REPO"
        log_ok "密钥已同步到仓库: ${SA_KEY_REPO}"
    fi

    # 验证密钥文件
    if python3 -c "import json; json.load(open('${SA_KEY_HA}'))" 2>/dev/null; then
        log_ok "密钥文件格式验证通过"
    else
        log_warn "密钥文件格式可能有问题，请手动检查"
    fi
}

# ════════════════════════════════════════════════════════════════════════════════
# 阶段 3：Actions Console 手动配置
# ════════════════════════════════════════════════════════════════════════════════
phase3_actions_console() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "  阶段 3/4：Actions Console 手动配置"
    echo "─────────────────────────────────────────"

    NGROK_DOMAIN=$(get_state "NGROK_DOMAIN")
    FULFILLMENT_URL=$(get_state "FULFILLMENT_URL")
    GCP_PROJECT_ID=$(get_state "GCP_PROJECT_ID")
    SA_EMAIL="ha-homegraph-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

    prompt_human

    cat << MANUAL_GUIDE
${C_BOLD_YELLOW}此阶段需要在 Google Actions Console 网页端手动完成。${C_RESET}

以下是详细操作步骤：

┌─────────────────────────────────────────────────────────────┐
  步骤 A：创建 Smart Home 项目
└─────────────────────────────────────────────────────────────┘

  1. 浏览器访问 ${C_BOLD_CYAN}https://console.actions.google.com/${C_RESET}

  2. 点击 "New project"（新建项目）

  3. 项目名称建议填写 "HA Google Home Bridge"

  4. 在 "What kind of Action do you want to build?" 下
     选择 "${C_BOLD_CYAN}Smart Home${C_RESET}" 类型

  5. 点击 "Start building" 或 "Build your Action"

┌─────────────────────────────────────────────────────────────┐
  步骤 B：配置 Fulfillment URL
└─────────────────────────────────────────────────────────────┘

  1. 在左侧导航栏找到 "Develop" → "Fulfillment"

  2. 在 Fulfillment URL 输入框中填入：

     ${C_BOLD_GREEN}${FULFILLMENT_URL}${C_RESET}

  3. 点击 "Save"（保存）

┌─────────────────────────────────────────────────────────────┐
  步骤 C：配置 Account Linking（OAuth 账号关联）
└─────────────────────────────────────────────────────────────┘

  1. 在左侧导航栏找到 "Develop" → "Account linking"

  2. 选择 Linking type:
     ${C_BOLD_CYAN}OAuth 2.0 / Authorization code${C_RESET}

  3. 填写以下 OAuth 信息：

     Client ID:        ${C_BOLD_GREEN}https://oauth-redirect.googleusercontent.com/r/${GCP_PROJECT_ID}${C_RESET}
     Client Secret:    随便填一个字符串（如 "hasecret"）
     Authorization URL: ${C_BOLD_GREEN}https://${NGROK_DOMAIN}/auth/authorize${C_RESET}
     Token URL:         ${C_BOLD_GREEN}https://${NGROK_DOMAIN}/auth/token${C_RESET}

  4. Scopes: 填入 ${C_BOLD_CYAN}email${C_RESET} 和 ${C_BOLD_CYAN}name${C_RESET}

  5. Testing instructions: 填 "For personal HA bridge, no testing needed"

  6. 点击 "Save"

┌─────────────────────────────────────────────────────────────┐
  步骤 D：添加 Service Account 为项目成员
└─────────────────────────────────────────────────────────────┘

  1. 在 Actions Console 左侧导航找到 "Project settings" → "Permissions"

  2. 点击 "Add" → 输入以下 Service Account 邮箱：

     ${C_BOLD_GREEN}${SA_EMAIL}${C_RESET}

  3. 角色选择 "Project" → "Owner" 或 "Admin"

  4. 点击 "Add" 确认

┌─────────────────────────────────────────────────────────────┐
  步骤 E：启用 HomeGraph API（如之前未成功）
└─────────────────────────────────────────────────────────────┘

  如果阶段 2 的 API 启用步骤失败，请访问：
  ${C_BOLD_CYAN}https://console.cloud.google.com/apis/library/homegraph.googleapis.com?project=${GCP_PROJECT_ID}${C_RESET}
  点击 "Enable"

┌─────────────────────────────────────────────────────────────┐
  重要提醒
└─────────────────────────────────────────────────────────────┘

  - Actions Console 的 OAuth 回调 URL 格式是固定的，不要修改
  - Service Account 必须添加为项目成员，否则 HA 无法调用 HomeGraph API
  - 所有配置完成后，不需要发布 Action（保持在 Test 状态即可）
    只有你的 Google 账号可以使用，完全免费

MANUAL_GUIDE

    echo ""
    printf "${C_BOLD_GREEN}========================================${C_RESET}\n"
    printf "${C_BOLD_GREEN}  完成上述所有步骤后请输入 'Y' 继续${C_RESET}\n"
    printf "${C_BOLD_GREEN}========================================${C_RESET}\n"

    while true; do
        echo ""
        read -r -p "  输入 'Y' 继续: " CONFIRM
        if [ "$CONFIRM" = "Y" ] || [ "$CONFIRM" = "y" ]; then
            log_ok "确认继续"
            break
        else
            log_info "请输入 'Y' 确认，或按 Ctrl+C 中断脚本"
        fi
    done
}

# ════════════════════════════════════════════════════════════════════════════════
# 阶段 4：HA 配置注入
# ════════════════════════════════════════════════════════════════════════════════
phase4_ha_config() {
    echo ""
    echo "─────────────────────────────────────────"
    echo "  阶段 4/4：HA 配置注入"
    echo "─────────────────────────────────────────"

    GCP_PROJECT_ID=$(get_state "GCP_PROJECT_ID")
    HA_CONF="${HA_CONFIG}/configuration.yaml"
    REPO_CONF="${REPO_DIR}/config/configuration.yaml"

    # ── 检查是否已配置 ──
    if grep -q "^google_assistant:" "$HA_CONF" 2>/dev/null; then
        log_warn "configuration.yaml 中已存在 google_assistant 配置，跳过注入"
        log_info "如需重新配置，请先手动删除现有 google_assistant 块"
    else
        log_info "备份 configuration.yaml..."
        TS=$(date +%Y%m%d_%H%M%S)
        cp "$HA_CONF" "${HA_CONF}.bak.${TS}"
        log_ok "已备份: ${HA_CONF}.bak.${TS}"

        GOOGLE_ASSISTANT_CONFIG=$(
            cat << YAML_END

# ── Google Home 桥接 ──
google_assistant:
  project_id: ${GCP_PROJECT_ID}
  service_account: google_service_account.json
  report_state: true
  expose_by_default: false
  entity_config: {}
YAML_END
        )

        # 追加到 HA 运行时配置
        printf '%s\n' "$GOOGLE_ASSISTANT_CONFIG" >> "$HA_CONF"
        log_ok "已注入 google_assistant 配置到: ${HA_CONF}"

        # 同步到仓库
        if [ -f "$REPO_CONF" ]; then
            if grep -q "^google_assistant:" "$REPO_CONF" 2>/dev/null; then
                log_info "仓库配置已存在 google_assistant 块，跳过"
            else
                printf '%s\n' "$GOOGLE_ASSISTANT_CONFIG" >> "$REPO_CONF"
                log_ok "已同步配置到仓库: ${REPO_CONF}"
            fi
        fi
    fi

    # ── 验证 SA 密钥 ──
    SA_KEY="${HA_CONFIG}/google_service_account.json"
    if [ -f "$SA_KEY" ]; then
        log_ok "Service Account 密钥已就位: ${SA_KEY}"
    else
        log_warn "Service Account 密钥未找到，请确认阶段 2 是否成功"
    fi

    # ── .gitignore 检查 ──
    GITIGNORE="${REPO_DIR}/.gitignore"
    if [ -f "$GITIGNORE" ]; then
        if ! grep -q "google_service_account.json" "$GITIGNORE" 2>/dev/null; then
            log_warn "建议在 .gitignore 中添加 google_service_account.json 防止密钥泄露"
            echo "  echo 'config/google_service_account.json' >> ${GITIGNORE}"
        else
            log_ok "google_service_account.json 已在 .gitignore 中"
        fi
    fi
}

# ════════════════════════════════════════════════════════════════════════════════
# 完成
# ════════════════════════════════════════════════════════════════════════════════
print_summary() {
    NGROK_DOMAIN=$(get_state "NGROK_DOMAIN")
    FULFILLMENT_URL=$(get_state "FULFILLMENT_URL")
    GCP_PROJECT_ID=$(get_state "GCP_PROJECT_ID")

    echo ""
    echo "========================================="
    echo "  Google Home Bridge 部署完成！"
    echo "========================================="
    echo ""
    printf "  ${C_BOLD_GREEN}ngrok 域名:${C_RESET}     https://${NGROK_DOMAIN}\n"
    printf "  ${C_BOLD_GREEN}Fulfillment:${C_RESET}   ${FULFILLMENT_URL}\n"
    printf "  ${C_BOLD_GREEN}GCP 项目 ID:${C_RESET}   ${GCP_PROJECT_ID}\n"
    echo ""
    echo "─────────────────────────────────────────"
    echo "  下一步操作："
    echo "─────────────────────────────────────────"
    echo ""
    echo "  1. 确保 ngrok 隧道在运行:"
    echo "     ${C_BOLD_CYAN}bash scripts/run-ngrok.sh${C_RESET}"
    echo ""
    echo "  2. 重启 Home Assistant 使配置生效:"
    echo "     ${C_BOLD_CYAN}bash scripts/start-ha.sh${C_RESET}"
    echo ""
    echo "  3. 在 Google Home APP 中搜索新设备:"
    echo "     打开 Google Home → + → 设置设备 → 与 Google 服务关联"
    echo "     找到你的 HA 项目并完成账号关联"
    echo ""
    echo "  4. 查看 HA 日志确认状态:"
    echo "     ${C_BOLD_CYAN}tail -f ${HA_BASE}/home-assistant.log | grep google_assistant${C_RESET}"
    echo ""
    echo "========================================="
}

# ════════════════════════════════════════════════════════════════════════════════
# 主流程
# ════════════════════════════════════════════════════════════════════════════════
main() {
    check_prerequisites

    # 检查用户是否只想运行特定阶段
    if [ "${1:-}" = "--phase" ]; then
        case "${2:-}" in
            1) phase1_ngrok; exit 0 ;;
            2) phase2_gcp; exit 0 ;;
            3) phase3_actions_console; exit 0 ;;
            4) phase4_ha_config; exit 0 ;;
            *) log_error "无效阶段: ${2:-}，可选: 1 2 3 4"; exit 1 ;;
        esac
    fi

    # 阶段 1
    NGROK_DOMAIN=$(get_state "NGROK_DOMAIN")
    if [ -n "$NGROK_DOMAIN" ] && command -v ngrok >/dev/null 2>&1; then
        log_info "阶段 1 (ngrok) 已完成，域名: ${NGROK_DOMAIN}"
        printf "重新运行阶段 1？[y/N] "
        read -r RERUN
        if [ "${RERUN:-N}" = "y" ] || [ "${RERUN:-N}" = "Y" ]; then
            phase1_ngrok
        fi
    else
        phase1_ngrok
    fi

    # 阶段 2
    GCP_PROJECT_ID=$(get_state "GCP_PROJECT_ID")
    if [ -n "$GCP_PROJECT_ID" ] && [ -f "${HA_CONFIG}/google_service_account.json" ]; then
        log_info "阶段 2 (GCP) 已完成，项目: ${GCP_PROJECT_ID}"
        printf "重新运行阶段 2？[y/N] "
        read -r RERUN
        if [ "${RERUN:-N}" = "y" ] || [ "${RERUN:-N}" = "Y" ]; then
            phase2_gcp
        fi
    else
        phase2_gcp
    fi

    # 阶段 3
    phase3_actions_console

    # 阶段 4
    phase4_ha_config

    # 完成
    print_summary
}

main "$@"
