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

## 安装（首次使用 / 重装）

Skill 应用后，运行同目录 `scripts\install.ps1`：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\install.ps1"
```

脚本会自动完成旧版本清理 + 新部署：

1. **停止旧进程**：查找并结束正在运行的 `notify-bridge.exe`
2. **备份旧 config.json**：在 `%USERPROFILE%\NotifyPC.bak.<时间戳>\` 保留旧配置
3. **删除旧部署目录**：清空 `%USERPROFILE%\NotifyPC\`，避免旧 exe / 旧配置与新 skill 冲突
4. 在 `%USERPROFILE%\NotifyPC\` 目录部署 `notify-bridge.exe`
5. 若本地无 exe，优先通过国内镜像自动下载，镜像失败后再尝试 GitHub 直连
6. 创建默认 `config.json`
7. 同步 `dashboard.html`

如需保留旧配置（不删除目录，只覆盖文件），加 `-KeepConfig`：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\install.ps1" -KeepConfig
```

## 工作流

1. **检查桥接是否运行**：`netstat -ano | Select-String ':9875.*LISTENING'`
   - 已监听 → 直接跳到第 4 步打开看板。
   - 未监听 → 继续。
2. **运行 install.ps1** 确保 exe 与配置已部署。
3. **启动桥接**：用 PowerShell `Start-Process` 独立启动，避免依赖 agent 会话：
   ```powershell
   $exe = Join-Path $env:USERPROFILE "NotifyPC\notify-bridge.exe"
   Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
   ```
4. **检查/创建 WorkBuddy 摘要自动化**：看板的「AI 智能摘要」依赖 WorkBuddy 每小时自动归档。首次使用或重装时，检查是否已有名为 `手机通知增量摘要归档` 的自动化；若不存在则创建。
   - 用 `automation_update` mode=list 检查同名自动化。
   - 若不存在，用 `automation_update` mode=create 创建，参数见「附录：摘要自动化配置」。
5. **打开看板**：用内置浏览器打开 `http://localhost:9875`。
6. **手机端**：安装 `NotifyPC.apk` → 开启「通知使用权」→ 点「保存并开始转发」。
7. **汇报状态**：看板地址、通知总数、在线客户端数。

## config.json

```json
{
  "dashPort": 9875,
  "dashBind": "0.0.0.0",
  "dashToken": "",
  "dashLocalBypass": true,
  "iosBleAddress": "",
  "androidBleAddress": "",
  "androidNames": [],
  "ancsEnabled": false
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `dashPort` | 看板 HTTP 端口 |
| `dashBind` | 绑定地址 |
| `dashToken` | 首次启动自动生成，本地看板可保留空值 |
| `dashLocalBypass` | 本地请求免鉴权 |
| `androidBleAddress` | 可选，直接指定手机 BLE 地址连接 |
| `androidNames` | 可选，Windows 扫描不到 UUID 时按蓝牙名匹配，如 `["陈同学的Xiaomi 14"]` |
| `ancsEnabled` | iPhone/ANCS 已废弃，保持 `false` |

## API（调试）

- `GET /api/notifications` → 全部通知（最新在前）
- `GET /api/notifications?since=<ms>` → 增量通知
- `GET /api/events` → SSE 实时推送
- `GET /api/stats` → 统计摘要
- `GET /api/summary` → 今日汇总 + 待办候选
- `GET /api/info` → 版本 / IP / 端口
- `GET /api/clients` → 在线手机客户端列表

## 附录：摘要自动化配置

创建自动化时，将 prompt 中 `C:\Users\knigh\NotifyPC` 替换为当前用户的实际部署目录（PowerShell 中可用 `Join-Path $env:USERPROFILE "NotifyPC"` 获取）。

| 参数 | 值 |
|------|-----|
| `name` | `手机通知增量摘要归档` |
| `scheduleType` | `recurring` |
| `rrule` | `FREQ=HOURLY` |
| `cwds` | `<USERPROFILE>\NotifyPC` 的实际绝对路径 |
| `status` | `ACTIVE` |

**prompt：**

```text
你是通知归档助手。工作目录：<USERPROFILE>\NotifyPC
任务：增量处理手机通知日志，生成中文摘要并归档。每小时自动执行一次。

步骤：
1. 读取游标文件 <USERPROFILE>\NotifyPC\logs\.notify_cursor。内容是一个整数，表示已处理 notify.jsonl 到第几行。若文件不存在，视为 0。
2. 用 Bash 命令 `wc -l < "<USERPROFILE>\NotifyPC\logs\notify.jsonl"` 获取 notify.jsonl 当前总行数，记为 TOTAL。
3. 若游标值 >= TOTAL，说明无新通知，本次结束，不写任何文件，直接回复"无新通知"。
4. 否则用 Read 工具读取 <USERPROFILE>\NotifyPC\logs\notify.jsonl，offset=游标值+1，limit=TOTAL-游标值，获取全部新增行。每行是一个 JSON 通知，字段：v, ts, pkg, app, title, text, id。
5. 对新增通知做中文摘要：
   - 按应用(app)归类；
   - 每个应用下列出该时段的若干通知要点（标题+正文要点，简洁）；
   - 特别标注高价值通知：验证码/一次性密码、快递/取件、会议/日程、来电/未接、银行/支付、航班/车票等，在要点前加 ⚑ 标记；
   - 时间用 ts 毫秒时间戳转成 HH:MM 显示。
6. 把摘要追加写入归档文件 <USERPROFILE>\NotifyPC\logs\notify-digest-YYYYMM.md（用当前年月，例如 notify-digest-202608.md，不存在则创建），格式：
   ## YYYY-MM-DD HH:00 时段通知摘要
   - **应用名**
     - HH:MM  标题 — 正文要点
     - HH:MM  ⚑ 标题 — 正文要点（高价值）
7. 摘要写完后，用 Write 工具把 <USERPROFILE>\NotifyPC\logs\.notify_cursor 更新为 TOTAL（已处理到最新行）。
8. 回复本次处理了多少条新通知、归档到哪个文件。

注意：
- 全程只追加，绝不修改或删除 notify.jsonl 原始内容。
- 游标以 wc -l 的真实行数为准，确保不漏不重。
- 若 notify.jsonl 不存在，回复"日志尚未生成，桥接可能未运行"并结束。
```

## 注意事项

- 桥接必须用 PowerShell `Start-Process` 独立启动；**不要用 Bash run_in_background**，agent 轮次结束进程会被清理。
- 防火墙：v4 使用 BLE，无需放行 TCP。
- 杀软误报：PyInstaller 打包的 exe 可能被个别杀软误报，建议加白名单。
- 仅 Android；iPhone 不再支持。
