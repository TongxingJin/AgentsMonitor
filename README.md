# AgentsMonitor

在 iPhone 上实时查看 AI agent（Claude Code、Codex 等）的工作状态，以及剩余额度。

当 agent 在思考或执行任务时，手机屏幕会变成动态彩色；需要你介入批准时，屏幕会变成闪烁的红色呼吸灯。

---

## 支持的功能

### 状态显示

| 状态 | 视觉效果 | 含义 |
|------|----------|------|
| Working | 白底浮动彩色圆环 | Agent 正在思考或执行任务 |
| Idle | 白色 | Agent 当前空闲 |
| Awaiting Approval | 红色呼吸灯 | 需要你在电脑上批准操作 |

### 额度显示

- 左侧圆柱：**5 小时**剩余额度
- 右侧圆柱：**7 天**剩余额度
- 圆柱颜色随剩余比例从绿色逐渐变黄变红

### 多 Agent 切换

顶部选项卡可在 Claude Code 和 Codex 之间切换，各自独立显示状态和额度。

---

## 三种通信方式

### 蓝牙 BLE — Mac ↔ iPhone

适合：**MacBook 用户**

- 无需任何网络，纯设备间直连
- Mac 上运行 `mac-ble-beacon`，iPhone 自动发现并连接
- iOS 12 / iOS 26 均支持
- 同时支持 Claude Code 和 Codex 的状态与额度

### Tailscale — Ubuntu/Mac ↔ iPhone

适合：**台式机用户**，或需要**跨距离**监控

- 只要手机连接 WiFi、电脑在 Tailscale 网络内即可，无需在同一局域网
- Ubuntu 上运行 `ubuntu-tailscale-beacon`，iOS 26 app 填入电脑的 Tailscale IP 后自动轮询
- 支持同时配置多台电脑（如 MacBook + Ubuntu 台式机）

### USB — Ubuntu ↔ iPhone

适合：**Ubuntu 台式机用户**，无需在电脑或手机上配置任何网络服务

- 用数据线连接即可，不依赖蓝牙，不需要在手机上安装 Tailscale
- Ubuntu 主动通过 USB 将状态推送到手机，手机无需做任何网络配置

---

## 支持的平台

| 电脑端 | 手机端 | 通信方式 |
|--------|--------|----------|
| macOS (MacBook) | iOS 12+ | BLE 蓝牙 |
| macOS (MacBook) | iOS 26 | BLE 蓝牙 |
| Ubuntu 台式机 | iOS 26 | Tailscale HTTP |
| Ubuntu 台式机 | iOS 12+ | USB 反向推送 |

三种方式可以**同时运行**，App 会自动合并所有来源的状态，以最新、最活跃的为准。

---

## 快速安装

### 第一步：安装电脑端 Hooks

让 Claude Code 和 Codex 在运行时写出状态文件：

```bash
cd hooks
./install.sh
```

验证：
```bash
echo working > ~/.claude-status      # Claude 状态
echo idle > ~/.codex/agent-status/status.txt  # Codex 状态
```

### 第二步：按你的设备选择通信方式

---

#### 方案 A：Mac + BLE（推荐 MacBook 用户）

```bash
cd mac-ble-beacon
./build.sh
./install-launch-agent.sh   # 设置为开机自动运行
```

手机端：打开 iOS app，会自动扫描并连接，无需任何配置。

---

#### 方案 B：Ubuntu + Tailscale（推荐台式机用户）

**Ubuntu 端：**

默认不安装 Ubuntu 组件。只有在你确实要用 Tailscale 路径时再执行：

```bash
cd ubuntu-tailscale-beacon
./install.sh                       # 安装后自动 enable + start
```

**手机端（iOS 26）：**

打开 app，点击右上角网络图标，填入 Ubuntu 的 Tailscale IP（如 `100.91.235.49`），保存即可。

---

#### 方案 C：Ubuntu + USB

**前置条件：**

```bash
sudo apt install libimobiledevice-utils libusbmuxd-tools
idevicepair pair   # 首次需要信任设备
```

**安装并启动：**

默认不安装 Ubuntu 组件。只有在你确实要用 USB 路径时再执行：

```bash
cd ubuntu-usb
./install.sh                       # 安装后自动 enable + start
```

手机用数据线连接 Ubuntu，app 会自动接收状态推送。

---

### 第三步：安装 iPhone App

用 Xcode 打开 `app/` 目录，选择对应 target：

- `iOS26` — iOS 26+，支持全部三种通信方式
- `iOS12` — iOS 12，支持 BLE 和 USB

连接真机，Build & Run。

---

## Codex 额度同步到 Ubuntu

如果你在 Mac 上使用 Codex，但手机通过 USB 连接 Ubuntu，可以让 Mac 将额度数据推送给 Ubuntu：

在 Mac 的 `~/.zshrc` 中添加：

```bash
export QUOTA_PUSH_URL="http://<Ubuntu-Tailscale-IP>:8765/quota"
```

之后每次 Codex 在 Mac 上结束任务，额度数据会自动同步到 Ubuntu，通过 USB 连接的手机也能看到 Codex 剩余额度。

---

## 目录结构

```text
AgentsMonitor/
├── app/
│   ├── Shared/          # 共享 Swift 代码（BLE、HTTP、USB、Tailscale 监听）
│   ├── iOS26/           # iOS 26 SwiftUI app
│   └── iOS12/           # iOS 12 UIKit app
├── mac-ble-beacon/          # macOS BLE 广播（Swift）
├── ubuntu-tailscale-beacon/       # Ubuntu HTTP 状态服务（Python）
├── ubuntu-usb/          # Ubuntu USB 推送服务（Python）
└── hooks/
    ├── *.sh             # Claude Code hooks
    └── codex/           # Codex hooks
```

技术细节见 [ARCHITECTURE.md](ARCHITECTURE.md)。
