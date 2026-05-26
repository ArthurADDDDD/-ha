# ha-phone

**Home Assistant 手机宿主可重复部署方案**

- 宿主：Sony Xperia 1 III
- 环境：Android + Termux + Termux:Boot
- 目标：HA 稳定运行 + 小米 / 美的 / Google Home 全打通

## 快速开始

```bash
# 首次安装
git clone <your-repo-url> ~/ha
cd ~/ha
bash scripts/install.sh

# 启动（前台运行，Ctrl+C 停止）
bash scripts/start-ha.sh

# 检查状态
bash scripts/check-ha.sh
```

浏览器访问 `http://<手机IP>:8123`，在设置中添加集成。

## 目录结构

```
ha/
├── bootstrap/
│   ├── 01_termux_pkgs.sh      安装基础包
│   ├── 02_clone_base.sh       拉取 HomeAssistant-Termux
│   └── 03_patch_base.sh       打补丁（platform + 镜像源）
├── config/
│   ├── configuration.yaml     HA 配置模板（首次安装时复制到 haconfig）
│   └── scripts.yaml           语音组合脚本模板
├── lib/
│   └── utils.sh               公共函数（日志、路径、backup_once、get_lan_ip 等）
└── scripts/
    ├── install.sh             一键安装（幂等）
    ├── start-ha.sh            启动 HA（前台，Ctrl+C 停止）
    ├── stop-ha.sh             停止 HA
    ├── check-ha.sh            健康检查（容器/端口/集成/日志）
    ├── show-version.sh        查看版本
    ├── repair.sh              自动诊断并修复
    ├── clean.sh               清理安装（--force / --full）
    ├── patch-container.sh     容器内 Python 库兼容补丁（ifaddr 等）
    ├── patch-xiaomi-home.sh   xiaomi_home 兼容补丁（Patch B–F）
    ├── patch-midea.sh         midea_ac_lan 兼容补丁
    ├── reinstall-xiaomi-home.sh  重装 Xiaomi Home
    ├── reinstall-midea.sh        重装 Midea 集成（可选）
    └── setup-google-home.sh      Google Home 桥接配置向导
```

## 日常使用

```bash
bash scripts/start-ha.sh    # 启动（前台日志，Ctrl+C 完全停止 HA）
bash scripts/stop-ha.sh     # 后台停止
bash scripts/check-ha.sh    # 健康检查
bash scripts/show-version.sh
```

HA 配置文件实际路径：`~/HomeAssistant-Termux/haconfig/`（非本仓库 `config/`）。

## 重装 / 彻底清理

```bash
bash scripts/clean.sh             # 查看清理选项
bash scripts/clean.sh --force     # 清理容器+镜像+基项目（保留 haconfig）
bash scripts/clean.sh --full      # 以上全部+清空 haconfig（保留备份）
bash scripts/install.sh           # 清理后重新安装
```

备份保留在 `~/HomeAssistant-Termux/.bak/`。

## 可选集成

```bash
bash scripts/reinstall-xiaomi-home.sh   # 小米（已默认安装）
bash scripts/reinstall-midea.sh         # 美的（空调/热水器/洗衣机，可选）
```

## 遇到问题

```bash
bash scripts/repair.sh                  # 自动诊断并修复
bash scripts/reinstall-xiaomi-home.sh   # 仅重装 Xiaomi Home
```

## 补丁说明

每次 `start-ha.sh` 启动时自动打以下补丁（均幂等，已打过直接跳过）：

| # | 补丁 | 脚本 | 说明 |
|---|------|------|------|
| 1 | udocker platform | `bootstrap/03_patch_base.sh` | `source.env` 添加 `--platform=linux/arm64` |
| 2 | Docker 镜像源 | `bootstrap/03_patch_base.sh` | `home-assistant-core.sh` 固定使用 Docker Hub |
| 3 | ifaddr EACCES | `patch-container.sh` | 容器内 `ifaddr/_posix.py` 容忍 Android `getifaddrs()` 权限拒绝，避免 HA http 组件启动失败进入 recovery mode |
| B | xiaomi_home psutil | `patch-xiaomi-home.sh` | `psutil.net_if_addrs()` EACCES → try/except，避免配置向导 "unknown error" |
| C | xiaomi_home mDNS | `patch-xiaomi-home.sh` | 短路 `MipsService.init_async`，Android proot 多播套接字 SIGSEGV(11) 会崩整个 HA |
| D | xiaomi_home ping | `patch-xiaomi-home.sh` | 短路 `__ping_async`，ICMP raw socket 同样触发 proot SIGSEGV |
| E | xiaomi_home init_async | `patch-xiaomi-home.sh` | 短路启动期全部网络探测，`network_status=True` 直接就绪 |
| F | xiaomi_home OAuth URL | `patch-xiaomi-home.sh` | `OAUTH_REDIRECT_URL` 从 `homeassistant.local:8123` 改为手机 LAN IP，每次启动自动检测并更新 |
| A | midea ifaddr | `patch-midea.sh` | `ifaddr/_posix.py` / `midealocal/discover.py` 容忍 `getifaddrs` EACCES |

`patch-container.sh` 和 `patch-midea.sh` 有 stamp 缓存（`~/.ha_patch_stamp`），文件未变化时跳过扫描。`patch-xiaomi-home.sh` 每次都跑（负责 Patch F IP 检测）。

## 前提条件

- Termux + Termux:Boot 已安装
- ADB 白名单：`com.termux`, `com.termux.boot`
- 手机在家庭 Wi-Fi 内长期在线

## 小米设备接入

1. 启动 HA 后访问 `http://<手机IP>:8123`
2. 设置 → 设备与服务 → 添加集成 → 搜索 "Xiaomi Home"
3. 扫码 / 账号登录小米账号，设备自动出现

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

`haconfig/configuration.yaml` 中 `google_assistant` 块：

```yaml
google_assistant:
  project_id: YOUR_GCP_PROJECT_ID        # 必须 == Developer Console 项目 ID
  service_account: !include google_service_account.json   # 必须用 !include
  report_state: true
  expose_by_default: false               # 建议 false，按需 expose: true
  entity_config:
    climate.my_ac:
      expose: true
    switch.water_heater_power:
      expose: false
```

Developer Console 里「云端执行网址」必须以 `/api/google_assistant` 结尾。

### 踩坑记录

| # | 坑 | 解决 |
|---|-----|------|
| 1 | **ngrok 被运营商拦截** | 换 Cloudflare Tunnel（QUIC 协议） |
| 2 | **serveo.net Google 不可达** | 换 Cloudflare Tunnel |
| 3 | **OAuth 登录后 "could not reach"** | 云端执行网址补全 `/api/google_assistant` |
| 4 | **`service_account` 报 "expected a dictionary"** | HA 2026.5+ 要求 `service_account: !include xxx.json` |
| 5 | **HomeGraph 404** — reportState/request_sync 全 404 | Developer Console 项目 ID 必须等于 GCP 项目 ID；SA、HomeGraph API 都要在同一个 GCP 项目里 |
| 6 | **一个物理设备拆成 N 张卡片** | `entity_config` 隐藏冗余 sub-entity，只暴露主控 entity |
| 7 | **加湿器只显示贴纸** | HUMIDIFIER 类型 App UI bug；用 `template:` switch 包装主开关暴露（原 humidifier 保留供语音调湿度） |
| 8 | **Water Heater 不显示** | SYNC `attributes: {}` 为空 Google 丢弃；用 `generic_thermostat` 包装 `switch.*_power` + `sensor.*_temperature` 成 climate 实体 |
| 9 | **Cloudflare 临时域名重启变化** | 注册固定隧道名 |
| 10 | **Developer Console 设备类型不匹配** | 全选 Thermostat/WaterHeater/Humidifier/Switch/Sensor/Fan 等 |
| 11 | **"未关联的 Action"** | 测试套件状态，非错误；在 Google Home App 搜 `[test]` 完成账号关联 |
| 12 | **expose_by_default: true 导致 100+ entity 涌入** | 改 `expose_by_default: false`，用 `entity_config` 按需暴露 |
| 13 | **小米 BLE 设备离线** | 蓝牙设备依赖网关轮询，确保米家 App 内设备在线、距离不远 |
| 14 | **温湿度计只显示贴纸** | `SENSOR` 类型 App 新版 UI 无控件渲染，语音查询正常，协议限制无解 |

### 必需的非仓库文件

| 文件 | 说明 |
|------|------|
| `haconfig/google_service_account.json` | GCP SA 密钥（`.gitignore` 已排除） |
| `.google_home_env` | 隧道域名等运行时变量（`.gitignore` 已排除） |

## 美的空调局域网协议调试

通过 `midea_ac_lan` 集成接入美的风尊旗舰版空调，调试了 V3 LAN 协议（TCP 6444，AES 加密）。

### 抓包方法

```bash
# 手机端抓包（Termux 安装 tcpdump）
tcpdump -i wlan0 -X port 6444 -w /sdcard/midea.pcap
# 操作美的美居 App 目标功能 → 停止抓包 → 拉到电脑 AES 解密对比 payload
```

### 关键发现

| 发现 | 说明 |
|------|------|
| **智控温 = `prevent_super_cool` (0x0049)** | `intelligent_control` (0x0031) 不响应；App 点智控温实际发 0x0049，5 字节值：ON=`0x0100000000` |
| **`wind_around` (0x0059) 是 2 字节** | ON+上=`0x0101`，ON+下=`0x0102`，OFF=`0x0000`；1 字节有蜂鸣但不切换 |

### B0 / B5 协议速览

| 消息 | 方向 | 用途 |
|------|------|------|
| B0 SET | HA → AC | 控制命令 |
| B1 notify | AC → HA | 全量状态快照（查询响应） |
| B5 notify | AC → HA | 单属性变更推送（遥控器操作触发） |

### Google Home 语音方案

最终采用**暴露原子开关 + Google Home Routine**：HA 侧只暴露 `wind_around` / `prevent_super_cool` / `comfort_mode` 三个开关，组合逻辑交给 Google Home Routine。

## License

Private
