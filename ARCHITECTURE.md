# Architecture

## 整体架构

```text
Claude Code hooks          Codex hooks
      ↓                         ↓
~/.claude-status    ~/.codex/agent-status/status.txt
         \                     /
          \                   /
     ┌─────────────────────────────────────────┐
     │         电脑端（三种方式任选）            │
     │                                         │
     │  Mac BLE beacon    Ubuntu HTTP beacon   │
     │  mac-beacon/        ubuntu-beacon/      │
     │                                         │
     │  Ubuntu USB pusher                      │
     │  ubuntu-usb/pusher.py                   │
     └─────────────────────────────────────────┘
              ↓ BLE / HTTP(Tailscale) / USB TCP
     ┌─────────────────────────────────────────┐
     │           iPhone App                    │
     │  app/Shared/StatusAggregator.swift       │
     │  合并多个来源，取最新活跃状态             │
     └─────────────────────────────────────────┘
```

---

## 状态文件约定

| Agent | 状态文件 | 额度文件 |
|-------|----------|----------|
| Claude Code | `~/.claude-status` | 内嵌在 BLE 载荷 |
| Codex | `~/.codex/agent-status/status.txt` | `~/.codex/agent-status/quota.json` |

状态值：`working` / `idle` / `awaiting_approval`（及若干等效别名）

---

## BLE 协议（Mac ↔ iPhone）

Service UUID: `A1B2C3D4-E5F6-47A1-9B2C-001122334455`  
Characteristic UUID: `A1B2C3D4-E5F6-47A1-9B2C-001122334466`（Read + Notify）

载荷为 JSON：

```json
{
  "version": 1,
  "agents": {
    "claude": "working",
    "codex": "idle"
  },
  "quotas": {
    "fiveHourRemainingHours": 3.2,
    "fiveHourCapacityHours": 5.0,
    "sevenDayRemainingDays": 5.1,
    "sevenDayCapacityDays": 7.0
  },
  "codexQuota": null
}
```

旧版纯字符串载荷（`"working"` 等）仍兼容，App 自动回退解析。

---

## HTTP 协议（Ubuntu ↔ iPhone via Tailscale）

`ubuntu-beacon` 在端口 `8765` 提供：

- `GET /status` — 返回与 BLE 结构相同的 JSON
- `POST /quota` — 接收 Mac 推送的 Codex 额度数据，写入本地 quota.json

App 每秒轮询一次 `/status`，可同时配置多个 IP（多台电脑）。

---

## USB 推送协议（Ubuntu ↔ iPhone）

利用 `usbmuxd` / `iproxy` 建立 Ubuntu → iPhone 的 TCP 反向隧道：

```text
iPhone NWListener (port 9000)
        ↑ TCP 连接
Ubuntu iproxy (127.0.0.1:9000 → iPhone:9000)
        ↑
Ubuntu pusher.py — 监视状态文件变化，每 0.5s 推送一次
```

推送格式（换行符分隔 JSON）：

```json
{"version":1,"agents":{"claude":"working","codex":"idle"},"quotas":null,"codexQuota":null}
```

iPhone App 用 `Network.framework` 的 `NWListener` 接收，支持 iOS 12+。

---

## StatusAggregator（多源合并）

`app/Shared/StatusAggregator.swift` 维护一个 `snapshotBySource` 字典，key 为来源 ID：

| 来源 ID | 对应监听器 |
|---------|-----------|
| `ble` | BLEStatusMonitor |
| `http` | HTTPStatusMonitor（mDNS 发现） |
| `usb` | USBStatusMonitor |
| `tailscale:<host>` | TailscaleStatusMonitor（每个 IP 一个） |

合并规则：
1. 任意来源 `working` → 最终 `working`
2. 任意来源 `awaiting_approval`（无 `working`）→ 最终 `awaiting_approval`
3. 全部 `idle` 或无连接 → `idle`

`isConnected` = 任意来源已连接。

---

## Codex 额度读取（Mac 端）

`hooks/codex/stop.sh` 在 Codex 结束任务后，在后台运行 `read_quota.py`：

1. 启动一个最小化 Codex 会话（PTY），发送 `/status` 命令
2. 解析输出中的 `5h limit` 和 `Weekly limit` 百分比及重置时间
3. 将剩余小时数/天数写入 `~/.codex/agent-status/quota.json`
4. 若设置了 `QUOTA_PUSH_URL`，将数据 POST 到 Ubuntu beacon

---

## Hook 事件映射

### Claude Code（`hooks/*.sh`）

写入 `~/.claude-status`：

| 事件 | 状态 |
|------|------|
| PreToolUse | `working` |
| PostToolUse | `working` |
| Stop | `idle` |

### Codex（`hooks/codex/*.sh`）

写入 `~/.codex/agent-status/status.txt`：

| 事件 | 状态 |
|------|------|
| SessionStart | `idle` |
| UserPromptSubmit | `working` |
| PreToolUse | `working` |
| PostToolUse | `working` |
| PermissionRequest | `awaiting_approval` |
| Stop | `idle` + 后台刷新额度 |

---

## Mac Beacon 常驻服务

`mac-beacon/install-launch-agent.sh` 写入：

```text
~/Library/LaunchAgents/com.jin.agent-status-beacon.plist
~/Library/Application Support/AgentStatusBeacon/AgentStatusBeacon
~/Library/Logs/AgentStatusBeacon/stdout.log
```

调试命令：

```bash
launchctl print gui/$(id -u)/com.jin.agent-status-beacon
launchctl kickstart -k gui/$(id -u)/com.jin.agent-status-beacon
tail -f ~/Library/Logs/AgentStatusBeacon/stdout.log
```

---

## Ubuntu Beacon 系统服务

`ubuntu-beacon/install.sh` 写入 `~/.config/systemd/user/ubuntu-beacon.service`。

```bash
systemctl --user status ubuntu-beacon
journalctl --user -u ubuntu-beacon -f
```

---

## Ubuntu USB 系统服务

`ubuntu-usb/install.sh` 写入两个 systemd user 服务：

- `ubuntu-iproxy.service` — 运行 `iproxy 9000 9000`（保持 USB 隧道）
- `ubuntu-usb-pusher.service` — 运行 `pusher.py`（监视状态文件并推送）

```bash
systemctl --user status ubuntu-iproxy ubuntu-usb-pusher
journalctl --user -u ubuntu-usb-pusher -f
```

iPhone 首次连接需要执行一次 `idevicepair pair` 建立信任。
