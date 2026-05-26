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
| 5 | **HomeGraph 404 (`Requested entity was not found`)** — SYNC/EXECUTE 正常但 reportState/request_sync 全 404，根因是 Google Home Developer Console 项目 ID **不等于** GCP 项目 ID（SA 在 A 项目、HomeGraph 数据在 B 项目）| 在 Console 项目对应的 GCP 项目里建 SA、启用 HomeGraph API、生成新 key 替换；`configuration.yaml` 的 `project_id` 也要改成同一个 ID |
| 6 | **一个物理设备拆成 N 个 Google Home 卡片** — midea_ac_lan/xiaomi_home 为每个设备创建大量 sub-entity | `entity_config` 隐藏冗余 entity，只暴露主控制 entity（climate/humidifier/switch 等） |
| 7 | **加湿器在 Google Home App 只显示贴纸**（HUMIDIFIER 类型新版 App UI bug，语音控制正常）| 用 `template:` switch 包装主开关暴露（保留原 humidifier 让语音调湿度仍可用）；模板字段必须用 `state:` / `availability:` 而非旧版 `value_template:` / `availability_template:` |
| 8 | **Water Heater 不显示**（SYNC 返回的 `attributes: {}` 为空，Google 直接丢弃设备）| 隐藏原 `water_heater.*`，用内置 `generic_thermostat` 包装 `switch.*_power` + `sensor.*_current_temperature` 成 climate 实体；Google 即按 thermostat 渲染，可开关 + 调温度（失去厂商私有 trait）|
| 9 | **Cloudflare 临时域名重启后变化** — URL 更新需同步改所有 Console 配置 | 正式使用需注册固定隧道 |
| 10 | **Developer Console 设备类型不匹配** — 选 Dog/空导致设备被丢弃 | 全选 Thermostat/WaterHeater/Humidifier/Switch/Sensor/Fan 等 |
| 11 | **"未关联的 Action"** — 测试套件状态，非错误 | 在 Google Home APP 里搜 `[test]` 完成账号关联 |
| 12 | **`expose_by_default: true` 导致所有 entity 暴露** — 108+ 个冗余 sub-entity 涌入 Google Home | 通过 `entity_config` 精准隐藏，配合 Python 脚本按 `device_id` 批量处理 |
| 13 | **小米 BLE 设备显示离线/无数据** — 蓝牙设备依赖网关轮询，HA 读到过期状态 | 确保米家 App 内设备在线，蓝牙距离不要太远 |
| 14 | **湿度计/温度计在 Google Home App 只显示贴纸** — `action.devices.types.SENSOR` 在 App 新版 UI 无控件渲染（语音查询正常）| 协议限制，无法在 App 内修复 |

### 必需的非仓库文件

| 文件 | 说明 |
|------|------|
| `config/google_service_account.json` | GCP SA 密钥，`.gitignore` 已排除 |
| `.google_home_env` | 隧道域名等运行时变量，`.gitignore` 已排除 |

## 美的空调局域网协议调试

通过 `midea_ac_lan` 集成接入美的风尊旗舰版空调，过程中深入调试了 V3 LAN 协议（TCP 6444，AES 加密）。

### 抓包方法

手机上用 tcpdump 抓空调 6444 端口的 B0/B5 消息，对比美的美居 App 发出的指令和 HA 发出的指令：

```bash
# 手机端抓包（需要 root 或 Termux 安装 tcpdump）
tcpdump -i wlan0 -X port 6444 -w /sdcard/midea.pcap

# 操作美的美居 App 中的目标功能（如开关智控温）
# → 停止抓包，拉到电脑上对比 nstrace/AES 解密后的 payload
```

### 关键发现：智控温 = `prevent_super_cool`

| 标签 | 预期 | 实际 |
|------|------|------|
| `intelligent_control` (0x0031) | 智控温 | **不响应** — 发任何值 AC 都无状态变化 |
| `prevent_super_cool` (0x0049) | 防过冷 | **就是智控温** — 5 字节值：ON=`0x0100000000`, OFF=`0x0000000000` |

通过抓包美的美居 App 的真实 B0 SET 消息确认：App 点智控温按钮时，发出的 tag 是 0x0049 而非 0x0031。

### 关键发现：`wind_around` 是 2 字节值

环绕风 tag (0x0059) 必须用 2 字节值：
- ON + 上：`0x0101`
- ON + 下：`0x0102`
- OFF：`0x0000`

最初尝试 1 字节值（0x01/0x02），AC 有蜂鸣声但状态不切换。

### patch 要点

`midea_ac_lan/_vendor/midealocal/devices/ac/message.py`:

```python
# Tag 定义（B5 body / B0 SET 共用）
prevent_super_cool = 0x0049   # 智控温（不是 0x0031！）
wind_around = 0x0059          # 环绕风

# B0 SET 构造 — prevent_super_cool 5 字节
if self.prevent_super_cool is not None:
    payload.extend(NewProtocolMessageBody.pack(
        param=NewProtocolTags.prevent_super_cool,
        value=bytearray(
            [0x01, 0x00, 0x00, 0x00, 0x00] if self.prevent_super_cool
            else [0x00, 0x00, 0x00, 0x00, 0x00]
        ),
    ))

# B0 SET 构造 — wind_around 2 字节（byte0=on/off, byte1=direction）
value=bytearray(
    [0x01, 0x01] if self.wind_around else [0x00, 0x00]
)

# B5/B1 解析
if NewProtocolTags.prevent_super_cool in params:
    self.prevent_super_cool = params[NewProtocolTags.prevent_super_cool][0] == 1
if NewProtocolTags.wind_around in params:
    self.wind_around = params[NewProtocolTags.wind_around][0] != 0
```

### B0 / B5 协议速览

| 消息类型 | 方向 | 用途 |
|----------|------|------|
| B0 SET | HA → AC | 发送控制命令 |
| B1 notify | AC → HA | 全量状态快照（查询响应） |
| B5 notify | AC → HA | 单 tag 状态变更推送 |

B5 是 AC 主动推送的单属性变更通知（如在遥控器上按了一下），HA 通过解析 B5 body 更新对应 entity 状态。

### Google Home 语音组合方案

两种方式实现一键多操作：

| 方案 | 做法 | 优缺点 |
|------|------|--------|
| **HA script** | `scripts.yaml` 写组合脚本，暴露为 scene 给 Google | 集中管理，但需改配置重启 |
| **Google Home Routine** | 暴露单独开关，在 Google Home App 里建 Routine | 无需改 HA 配置，用户自行灵活组合 |

最终采用 **暴露原子开关 + Google Home Routine** 的方案，HA 侧只暴露 `wind_around`/`prevent_super_cool`/`comfort_mode` 三个开关，组合逻辑交给 Google。

### 暴露控制

`configuration.yaml` 的 `google_assistant.entity_config` 中通过 `expose: false` 精准隐藏冗余 entity，只暴露用户需要的控制按钮。`expose_by_default: true` 模式下未列出的 entity 全暴露，因此每次新增集成后需检查并隐藏不想要的 entity。

## License

Private
