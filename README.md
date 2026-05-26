# Agent 状态灯（Mac -> iPhone 蓝牙）

这个项目现在不再沿用只服务 Claude 的命名。

它已经扩展成一套通用链路：

- Mac 端分别产出不同 agent 的状态文件，例如 `Claude` / `Codex`
- `mac-beacon` 把多个 agent 的状态合并成一条 BLE 广播
- iPhone App 收到后可在手机端切换当前查看的 agent

当前支持的状态：

| 状态 | 颜色 | 含义 |
|------|------|------|
| `working` | 白底彩色圆环 | 正在思考或执行任务 |
| `idle` | 白色 | 当前空闲 |
| `awaiting_approval` | 红色 | 等待你在 Mac 上批准 |

iPhone 端当前是横屏仪表盘布局：

- 中间显示 agent 当前状态
- 左侧显示 `5 小时` 剩余额度圆柱
- 右侧显示 `7 天` 剩余额度圆柱
- 圆柱颜色会随剩余比例从绿色逐渐变黄再变红

## 现在的架构

```text
Claude agent hooks      Codex agent hooks
    ↓                       ↓
~/.claude-status       ~/.codex/agent-status/status.txt
           \            /
            \          /
           Mac Beacon (Swift / BLE)
                    ↓
        iPhone App (切换不同 agent)
```

BLE 特征值现在是 JSON：

```json
{
  "version": 1,
  "agents": {
    "claude": "working",
    "codex": "idle"
  }
}
```

旧版纯字符串协议仍然兼容，iPhone 端会自动回退。

## 已完成的改动

- `mac-beacon` 现在同时读取 `~/.claude-status` 和 `~/.codex/agent-status/status.txt`
- iPhone 端增加了 agent 切换
- BLE 广播名已经统一成 `AgentStatus`
- 新增 `hooks/codex/`，用于把 Codex 状态写到 `~/.codex/agent-status/status.txt`

## Agent 接入

默认安装方式已经统一为一次同时安装 Claude 和 Codex：

```bash
cd hooks
chmod +x install.sh pre_tool_use.sh post_tool_use.sh stop.sh
chmod +x codex/*.sh
./install.sh
```

安装后会写入：

```bash
~/.claude-status
~/.codex/agent-status/status.txt
```

如果你只想单独重装 Codex，也可以继续使用：

```bash
cd hooks/codex
chmod +x *.sh
./install.sh
```

## Codex 细节

Codex 部分新增了这些脚本：

```text
hooks/codex/
├── session_start.sh
├── user_prompt_submit.sh
├── pre_tool_use.sh
├── post_tool_use.sh
├── permission_request.sh
└── stop.sh
```

它们分别对应这些事件语义：

- `SessionStart` -> `idle`
- `UserPromptSubmit` -> `working`
- `PreToolUse` -> `working`
- `PostToolUse` -> `working`
- `PermissionRequest` -> `awaiting_approval`
- `Stop` -> `idle`

安装脚本：

```bash
cd hooks/codex
chmod +x *.sh
./install.sh
```

它会把脚本复制到：

```bash
~/.codex/agent-status-hooks
```

并自动把运行时 hook 定义写到：

```bash
~/.codex/config.toml
```

状态文件默认写到：

```bash
~/.codex/agent-status/status.txt
```

Codex 侧的 source of truth 约定如下：

- 仓库里的 `hooks/codex/*.sh` 是安装源模板
- `~/.codex/agent-status-hooks/*.sh` 是实际运行时脚本
- `~/.codex/config.toml` 里的 `[hooks]` 是实际生效配置

这意味着：

- 你如果修改了仓库里的脚本，需要重新运行 `hooks/codex/install.sh`
- 你如果只改 `~/.codex/hooks.json`，这套接法默认不会以它为准

如果 Codex 提示这些 hooks 需要 review / trust，需要在 Codex 自己的 hooks 管理界面里批准它们；批准后，Codex 会自己维护对应的 trust state。

## 启动 Mac 端广播

```bash
cd mac-beacon
./build.sh
./AgentStatusBeacon
```

二进制名现在已经统一成 `AgentStatusBeacon`，它会同时广播 Claude 和 Codex。

默认监控：

- `CLAUDE_STATUS_FILE` -> `~/.claude-status`
- `CODEX_STATUS_FILE` -> `~/.codex/agent-status/status.txt`

## 开机自动后台运行

如果你不想每次手动在 terminal 里启动 beacon，可以把它安装成 macOS `launchd` 的 `LaunchAgent`：

```bash
cd mac-beacon
chmod +x build.sh run-beacon.sh install-launch-agent.sh uninstall-launch-agent.sh
./install-launch-agent.sh
```

安装后它会：

- 自动编译 `AgentStatusBeacon`
- 把运行文件复制到 `~/Library/Application Support/AgentStatusBeacon`
- 写入 `~/Library/LaunchAgents/com.jin.agent-status-beacon.plist`
- 在你登录 macOS 后自动后台启动
- 进程退出时自动拉起

日志位置：

```bash
~/Library/Logs/AgentStatusBeacon/stdout.log
~/Library/Logs/AgentStatusBeacon/stderr.log
```

常用命令：

```bash
launchctl print gui/$(id -u)/com.jin.agent-status-beacon
launchctl kickstart -k gui/$(id -u)/com.jin.agent-status-beacon
```

如果要取消开机自启：

```bash
cd mac-beacon
./uninstall-launch-agent.sh
```

## iPhone App

1. 新建 iOS App（SwiftUI，iOS 16+）
   App 名称建议直接使用 `Agent Status Monitor`
2. 把 `ios-app-src/` 下的 `.swift` 文件拖进项目
3. 在 `Info.plist` 加上：
   - `NSBluetoothAlwaysUsageDescription` -> `用于接收 Mac 上 agent 的状态`
   - `UISupportedInterfaceOrientations` / `UISupportedInterfaceOrientations~ipad` 至少包含 `Landscape Left` 和 `Landscape Right`
4. 用真机运行

App 启动后会扫描 BLE，并在横屏界面顶部显示可切换的 agent 分段控件。
当 BLE 已连接时，App 会保持常亮；断联后会恢复系统自动熄屏。

额度显示说明：

- 如果 BLE 载荷里带 `quotas` 字段，App 会显示真实额度
- 如果还没接真实额度，App 会先使用内置 fallback 数值做 UI 展示

## 手动测试

不用真正跑 Claude/Codex，也可以直接写状态文件测试：

```bash
echo working > ~/.claude-status
echo idle > ~/.claude-status
echo awaiting_approval > ~/.claude-status

mkdir -p ~/.codex/agent-status
echo working > ~/.codex/agent-status/status.txt
echo idle > ~/.codex/agent-status/status.txt
echo awaiting_approval > ~/.codex/agent-status/status.txt
```

## 关键文件

```text
ios-app-src/AgentStatusMonitorApp.swift
ios-app-src/ContentView.swift
ios-app-src/BLEStatusMonitor.swift
mac-beacon/Sources/AgentStatusBeacon/main.swift
hooks/codex/
```
