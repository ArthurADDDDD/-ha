# ha-phone

**Home Assistant 手机宿主可重复部署方案**

- 宿主：Sony Xperia 1 III
- 环境：Android + Termux + Termux:Boot
- 目标：HA 稳定运行 + 优先打通 Xiaomi Home

## 快速开始

```bash
# 首次安装
git clone <your-repo-url> ha-phone
cd ha-phone
sh scripts/install.sh

# 启动
sh scripts/start-ha.sh

# 检查状态
sh scripts/check-ha.sh
```

浏览器访问 `http://<手机IP>:8123`，在设置中添加 Xiaomi Home 集成。

## 目录结构

```
ha-phone/
├── bootstrap/          # 初始化步骤
│   ├── 01_termux_pkgs.sh      安装基础包
│   ├── 02_clone_base.sh       拉取 HomeAssistant-Termux
│   └── 03_patch_base.sh       打补丁（platform + 镜像源）
├── config/
│   └── configuration.yaml     HA 基础配置
├── overlay/
│   └── custom_components/     (xiaomi_home 自动拉取)
├── scripts/
│   ├── install.sh             一键安装（幂等）
│   ├── repair.sh              修复（镜像/容器/补丁/集成）
│   ├── start-ha.sh            启动 HA
│   ├── stop-ha.sh             停止 HA
│   ├── show-version.sh        查看版本
│   ├── check-ha.sh            健康检查
│   ├── clean.sh                 清理现有安装
│   ├── patch-container.sh        容器内 Python 库兼容补丁（ifaddr 等）
│   ├── patch-xiaomi-home.sh      xiaomi_home 兼容补丁（psutil / mDNS 短路）
│   ├── reinstall-xiaomi-home.sh  重装 Xiaomi Home
│   └── reinstall-midea.sh       美的美居（可选）
└── lib/
    └── utils.sh               公共函数
```

## 日常使用

```bash
sh scripts/start-ha.sh          # 启动 HA
sh scripts/stop-ha.sh           # 停止 HA
sh scripts/check-ha.sh          # 健康检查（容器/端口/集成/日志）
sh scripts/show-version.sh      # 查看所有版本
```

## 重装 / 彻底清理

```bash
# 查看当前状态
sh scripts/check-ha.sh

# 选择性清理（推荐先看说明再执行）
sh scripts/clean.sh             # 查看清理选项
sh scripts/clean.sh --force     # 清理容器+镜像+基项目（保留 haconfig）
sh scripts/clean.sh --full      # 以上全部+清空 haconfig（保留备份）

# 清理后重新安装
sh scripts/install.sh
```

备份始终保留在 `~/HomeAssistant-Termux.bak.*`。

## 可选集成

```bash
# 小米（已默认安装）
sh scripts/reinstall-xiaomi-home.sh

# 美的美居（可选，独立部署）
sh scripts/reinstall-midea.sh       # 空调/热水器/洗衣机（局域网）
```

## 遇到问题

```bash
sh scripts/repair.sh                 # 自动诊断并修复
sh scripts/reinstall-xiaomi-home.sh  # 仅重装 Xiaomi Home
```

## 补丁说明

本仓库自动应用以下补丁：

1. **udocker platform** — `source.env` 添加 `--platform=linux/arm64`
2. **Docker 镜像源** — `home-assistant-core.sh` 固定使用 Docker Hub
3. **ifaddr EACCES** — 容器内 `ifaddr/_posix.py` 容忍 Android `getifaddrs()` 权限拒绝，避免 HA `http` 组件启动失败连锁导致 recovery mode（由 `scripts/patch-container.sh` 在 `start-ha.sh` 启动时自动打）
4. **xiaomi_home psutil EACCES** — `miot/miot_network.py` 的 `psutil.net_if_addrs()` 在 Android udocker 下 `PermissionError`，导致配置向导 "unknown error"，补丁让其返回空 dict 走 fallback（`scripts/patch-xiaomi-home.sh`，Patch B）
5. **xiaomi_home MIPS mDNS SIGSEGV** — `miot/miot_mdns.py` 的 `MipsService` 通过 `AsyncServiceBrowser` 监听多播，Android proot 多播套接字会 SIGSEGV(11) 导致 HA 整体崩溃；中国区 cloud_polling 不依赖局域网发现，补丁短路 `init_async/deinit_async`（`scripts/patch-xiaomi-home.sh`，Patch C）
6. **xiaomi_home ping SIGSEGV** — `miot/miot_network.py` 的 `__ping_async` 用 `subprocess` 调用 `ping` 二进制创建 ICMP raw socket，同样触发 proot SIGSEGV；短路直接返回 TIMEOUT，HTTP 探测（TCP）仍可用（`scripts/patch-xiaomi-home.sh`，Patch D）
7. **xiaomi_home init_async SIGSEGV** — Patch D 之后启动期仍崩在 `init_async` 的 http 探测 / `psutil.net_if_addrs()` C 扩展上（C 层段错绕过 Python try/except）；直接短路 `init_async`，置 `network_status=True` 跳过探测（`scripts/patch-xiaomi-home.sh`，Patch E）
8. **xiaomi_home OAuth redirect URL** — `miot/const.py` 把 `OAUTH_REDIRECT_URL` 写死成 `http://homeassistant.local:8123`，普通浏览器无法 mDNS 解析；改成手机 LAN IP（`scripts/patch-xiaomi-home.sh`，Patch F，启动时从 `get_lan_ip` 自动取）

## 前提条件

- Termux 已安装
- Termux:Boot 已安装
- ADB 白名单：`com.termux`, `com.termux.boot`
- 手机在家庭 Wi-Fi 内（局域网长期在线）

## 小米设备接入

1. 启动 HA 后访问 http://<IP>:8123
2. 设置 → 设备与服务 → 添加集成
3. 搜索 "Xiaomi Home"
4. 扫码/账号登录小米账号
5. 设备自动出现

## 版本要求

- Home Assistant Core >= 2024.4.4
- Python >= 3.11（容器自带）
- ha_xiaomi_home >= v0.4.7

## Google Home 桥接

### 连通方式

- **Cloudflare Tunnel** 提供公网 HTTPS → HA `localhost:8123`
- **Google Home Developer Console** Cloud-to-cloud 集成
- OAuth 账号关联 + Smart Home SYNC/QUERY/EXECUTE

### 配置要点

`configuration.yaml` 中 `google_assistant` 块：

```yaml
google_assistant:
  project_id: YOUR_GCP_PROJECT_ID
  service_account: !include google_service_account.json    # 必须用 !include
  report_state: true
  expose_by_default: true
  entity_config:
    # 隐藏冗余 sub-entity，避免一个设备拆成多个卡片
    switch.xxx_sub_switch:
      expose: false
    sensor.xxx_sub_sensor:
      expose: false
```

Developer Console 里 `云端执行网址` 必须以 `/api/google_assistant` 结尾。

### 踩坑记录

| # | 坑 | 解决 |
|---|-----|------|
| 1 | **ngrok 被运营商拦截** — TLS 到 ngrok-agent 失败 | 换 Cloudflare Tunnel（QUIC 协议） |
| 2 | **serveo.net Google 不可达** — SSH 反向隧道被 Google 服务端拦截 | 换 Cloudflare Tunnel |
| 3 | **OAuth 登录后 "could not reach"** — 云端执行网址漏了 `/api/google_assistant` | 补全为 `https://<domain>/api/google_assistant` |
| 4 | **`service_account` 报 "expected a dictionary"** — HA 2026.5+ 要求 `!include` | 改为 `service_account: !include xxx.json` |
| 5 | **HomeGraph API 返回 404** — SA 无 HomeGraph 权限，且未加入 Developer Console 项目成员 | GCP IAM 给 SA Viewer+，同时 Developer Console 成员列表添加 SA 邮箱 |
| 6 | **一个物理设备拆成 N 个 Google Home 卡片** — midea_ac_lan/xiaomi_home 为每个设备创建大量 sub-entity | `entity_config` 隐藏冗余 entity，只暴露主控制 entity（climate/humidifier/switch 等） |
| 7 | **小米 BLE 设备显示离线/无数据** — 蓝牙设备依赖网关轮询，HA 读到过期状态 | 确保米家 App 内设备在线，蓝牙距离不要太远 |
| 8 | **Water Heater 不显示** — Google HomeGraph 拒收 WATERHEATER 类型（"Requested entity was not found"） | 可能需伪装成 Thermostat 类型；Google 对该类型有区域限制 |
| 9 | **Cloudflare 临时域名重启后变化** — URL 更新需同步改所有 Console 配置 | 正式使用需注册固定隧道 |
| 10 | **Developer Console 设备类型不匹配** — 选 Dog/空导致设备被丢弃 | 全选 Thermostat/WaterHeater/Humidifier/Switch/Sensor/Fan 等 |
| 11 | **"未关联的 Action"** — 测试套件状态，非错误 | 在 Google Home APP 里搜 `[test]` 完成账号关联 |
| 12 | **`expose_by_default: true` 导致所有 entity 暴露** — 108+ 个冗余 sub-entity 涌入 Google Home | 通过 `entity_config` 精准隐藏，配合 Python 脚本按 `device_id` 批量处理 |

### 必需的非仓库文件

| 文件 | 说明 |
|------|------|
| `config/google_service_account.json` | GCP SA 密钥，`.gitignore` 已排除 |
| `.google_home_env` | 隧道域名等运行时变量，`.gitignore` 已排除 |

## License

Private
