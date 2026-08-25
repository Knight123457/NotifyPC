---
name: Phone Notification Summary
description: 启动 Phone Notification Summary（原 NotifyPC v4）桥接并打开 Android 手机通知看板。当用户说"通知看板"、"看手机通知"、"启动看板"、"打开通知看板"、"汇总手机通知"、"蓝牙通知"、"phone notification summary"等意图时使用。Android 手机通过 BLE GATT 广播通知，电脑自动扫描连接，无需 WiFi / iPhone。
agent_created: true
---

# Phone Notification Summary（NotifyPC v4）

## Overview

启动 `notify-bridge.exe` v4，打开实时通知看板 `http://localhost:9875`。

- **仅支持 Android**：手机 App 开启「通知使用权」并点击「保存并开始转发」后，通过 BLE GATT 广播通知；电脑自动扫描连接。
- **已移除 iPhone/ANCS、WiFi、经典蓝牙 RFCOMM**（v4.0.18 起）。
- 看板每 3 秒自动轮询，新通知到达后约 3 秒内显示。

## 安装（首次使用）

Skill 应用后，运行同目录 `scripts\install.ps1`：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\install.ps1"
```

脚本会：
1. 在 `%USERPROFILE%\NotifyPC\` 目录部署 `notify-bridge.exe`
2. 若本地无 exe，从 GitHub Release 自动下载
3. 创建默认 `config.json`
4. 同步 `dashboard.html`

## 工作流

1. **检查桥接是否运行**：`netstat -ano | Select-String ':9875.*LISTENING'`
   - 已监听 → 直接跳到第 3 步打开看板。
   - 未监听 → 继续。
2. **运行 install.ps1** 确保 exe 与配置已部署。
3. **启动桥接**：用 PowerShell `Start-Process` 独立启动，避免依赖 agent 会话：
   ```powershell
   $exe = Join-Path $env:USERPROFILE "NotifyPC\notify-bridge.exe"
   Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
   ```
4. **打开看板**：用内置浏览器打开 `http://localhost:9875`。
5. **手机端**：安装 `NotifyPC.apk` → 开启「通知使用权」→ 点「保存并开始转发」。
6. **汇报状态**：看板地址、通知总数、在线客户端数。

## config.json

```json
{
  "dashPort": 9875,
  "dashBind": "0.0.0.0",
  "dashLocalBypass": true
}
```

首次启动会自动生成 `dashToken`。

## API（调试）

- `GET /api/notifications` → 全部通知（最新在前）
- `GET /api/notifications?since=<ms>` → 增量通知
- `GET /api/events` → SSE 实时推送
- `GET /api/stats` → 统计摘要
- `GET /api/summary` → 今日汇总 + 待办候选
- `GET /api/info` → 版本 / IP / 端口
- `GET /api/clients` → 在线手机客户端列表

## 注意事项

- 桥接必须用 PowerShell `Start-Process` 独立启动；**不要用 Bash run_in_background**，agent 轮次结束进程会被清理。
- 防火墙：v4 使用 BLE，无需放行 TCP。
- 杀软误报：PyInstaller 打包的 exe 可能被个别杀软误报，建议加白名单。
- 仅 Android；iPhone 不再支持。
