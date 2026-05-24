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
│   └── reinstall-xiaomi-home.sh  重装 Xiaomi Home
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

## 遇到问题

```bash
sh scripts/repair.sh            # 自动诊断并修复
sh scripts/reinstall-xiaomi-home.sh  # 仅重装 Xiaomi Home
```

## 补丁说明

本仓库自动应用以下补丁：

1. **udocker platform** — `source.env` 添加 `--platform=linux/arm64`
2. **Docker 镜像源** — `home-assistant-core.sh` 固定使用 Docker Hub

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

## License

Private
