---
name: notify-dashboard
description: 启动 NotifyPC 桥接并打开手机通知看板。当用户说"通知看板"、"看手机通知"、"启动看板"、"打开通知看板"、"notify dashboard"、"手机来消息了看看"、"汇总手机通知"、"蓝牙通知"等意图时使用。本 skill 自包含电脑端全部运行文件（exe/看板页/部署脚本），自动部署到 %USERPROFILE%\NotifyPC 并启动。桥接提供 TCP 9876（WiFi）、蓝牙 RFCOMM 信道 5、HTTP 9875 看板（SSE 实时 + 汇总待办）。
agent_created: true
---

# NotifyPC 通知看板（自包含版）

## Overview

启动/检查 NotifyPC 桥接服务（`notify-bridge.exe` v2.6+），并打开通知看板 `http://localhost:9875`。看板优先 **SSE 实时推送**（`/api/events`），失败则回退 **`?since=` 增量轮询**。

**本 skill 自包含电脑端全部运行文件**：

```
本 skill 目录/
├── SKILL.md
├── bin/notify-bridge.exe
├── dashboard.html
├── config.example.json
└── scripts/
    ├── install.ps1              ← 部署 exe + 防火墙 + 可选开机自启
    ├── start.ps1                ← 健康检查：9875/9876 必须同 PID，否则杀残缺并重启
    └── register-watchdog.ps1    ← 可选：任务计划每 5 分钟自愈拉起
```

**部署约定**：运行时 exe 部署到 `%USERPROFILE%\NotifyPC\`，日志/配置与 skill 分离。

## 端口 / 通道约定

| 通道 | 用途 |
|------|------|
| 9876 (TCP) | WiFi：手机填 `电脑局域网IP:9876` |
| 蓝牙 RFCOMM 信道 5 | 蓝牙模式 |
| 9875 (HTTP) | 看板；本机免密；局域网 `?token=` |

## Workflow

1. 运行：
   ```powershell
   powershell -ExecutionPolicy Bypass -File "<本skill目录>\scripts\start.ps1"
   ```
   start.ps1 要求 **9875 与 9876 同 PID**；半死不活会杀进程再启。

2. 打开 `http://localhost:9875`。

3. （可选）崩溃自愈：
   ```powershell
   powershell -ExecutionPolicy Bypass -File "<本skill目录>\scripts\register-watchdog.ps1"
   ```

## API

- `GET /api/notifications` 全量；`GET /api/notifications?since=<ms>` 增量
- `GET /api/events` SSE（`event: notify`）
- `GET /api/stats` / `summary` / `info` / `clients`

## 注意事项

- 必须用 PowerShell `Start-Process` 独立进程；禁止 Bash 后台挂 agent。
- 单实例文件锁；已去掉盲目 `SO_REUSEADDR`，双开会绑端口失败并退出。
- HTTP 绑失败会 **整进程退出**，不会留下只听 9876 的僵尸。
- 数据在 `%USERPROFILE%\NotifyPC\`。
