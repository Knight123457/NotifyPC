# 可选：用「任务计划程序」每 5 分钟健康检查，失败则拉起 start.ps1（崩溃自愈）
# 用法：powershell -ExecutionPolicy Bypass -File register-watchdog.ps1
# 取消：Unregister-ScheduledTask -TaskName "NotifyPC-Bridge-Watchdog" -Confirm:$false
$ErrorActionPreference = "Stop"

$skillRoot = Split-Path -Parent $PSScriptRoot
$startPs1 = Join-Path $skillRoot "scripts\start.ps1"
$taskName = "NotifyPC-Bridge-Watchdog"

if (-not (Test-Path $startPs1)) {
    Write-Host "[错误] 找不到 start.ps1: $startPs1" -ForegroundColor Red
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startPs1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "[+] 已注册任务计划: $taskName （每 5 分钟调用 start.ps1 健康检查）" -ForegroundColor Green
Write-Host "    取消: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
