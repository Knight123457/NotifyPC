# NotifyPC 一键部署脚本（幂等：重复执行安全）
# 作用：把本 skill 自带的 notify-bridge.exe 部署到 %USERPROFILE%\NotifyPC\，
#       初始化 config.json，放行防火墙（TCP 9876），可选注册开机自启。
# 用法：powershell -ExecutionPolicy Bypass -File install.ps1 [-AutoStart]
param(
    [switch]$AutoStart
)
$ErrorActionPreference = "Stop"

$skillRoot = Split-Path -Parent $PSScriptRoot
$destDir   = Join-Path $env:USERPROFILE "NotifyPC"
$exeSrc    = Join-Path $skillRoot "bin\notify-bridge.exe"
$exeDest   = Join-Path $destDir "notify-bridge.exe"
$htmlSrc   = Join-Path $skillRoot "dashboard.html"
$htmlDest  = Join-Path $destDir "dashboard.html"
$cfgSrc    = Join-Path $skillRoot "config.example.json"
$cfgDest   = Join-Path $destDir "config.json"

Write-Host "== NotifyPC 部署 ==" -ForegroundColor Cyan
Write-Host "skill 目录: $skillRoot"
Write-Host "部署目标 : $destDir"

if (-not (Test-Path $exeSrc)) {
    Write-Host "[错误] skill 内未找到 bin\notify-bridge.exe" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }

# 1) exe：源比目标新或目标缺失才复制
$needCopy = $false
if (-not (Test-Path $exeDest)) { $needCopy = $true }
elseif ((Get-Item $exeSrc).LastWriteTime -gt (Get-Item $exeDest).LastWriteTime) { $needCopy = $true }
if ($needCopy) {
    Copy-Item $exeSrc $exeDest -Force
    Write-Host "[1/4] 已部署 notify-bridge.exe" -ForegroundColor Green
} else {
    Write-Host "[1/4] notify-bridge.exe 已是最新，跳过" -ForegroundColor DarkGray
}

# 2) dashboard.html：存在则同步（可覆盖 exe 内嵌版）
if (Test-Path $htmlSrc) {
    Copy-Item $htmlSrc $htmlDest -Force
    Write-Host "[2/4] 已同步 dashboard.html" -ForegroundColor Green
} else {
    Write-Host "[2/4] 无外部 dashboard.html，使用 exe 内嵌版" -ForegroundColor DarkGray
}

# 3) config.json：首次创建（含 dashToken 由 exe 首次启动自动生成）
if (-not (Test-Path $cfgDest)) {
    if (Test-Path $cfgSrc) { Copy-Item $cfgSrc $cfgDest -Force }
    else { '{"tcpPort":9876,"dashPort":9875}' | Out-File $cfgDest -Encoding utf8 }
    Write-Host "[3/4] 已创建 config.json（dashToken 首次启动自动生成）" -ForegroundColor Green
} else {
    Write-Host "[3/4] config.json 已存在，保留原配置" -ForegroundColor DarkGray
}

# 4) 防火墙：放行 TCP 9876 入站（程序级规则，需要管理员权限）
try {
    $rule = netsh advfirewall firewall show rule name="NotifyPC Bridge (TCP 9876)" 2>$null
    if ($LASTEXITCODE -ne 0) {
        netsh advfirewall firewall add rule name="NotifyPC Bridge (TCP 9876)" dir=in action=allow protocol=TCP localport=9876 program="$exeDest" | Out-Null
        Write-Host "[4/4] 已放行防火墙 TCP 9876" -ForegroundColor Green
    } else {
        Write-Host "[4/4] 防火墙规则已存在，跳过" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "[4/4] 防火墙规则添加失败（需管理员权限）：$($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "      可手动：以管理员运行 netsh advfirewall firewall add rule name=`"NotifyPC Bridge`" dir=in action=allow protocol=TCP localport=9876" -ForegroundColor Yellow
}

# 可选：开机自启（HKCU Run，无需管理员）
if ($AutoStart) {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $runKey -Name "NotifyPC" -Value "`"$exeDest`""
    Write-Host "[+] 已注册开机自启（HKCU Run）" -ForegroundColor Green
} else {
    Write-Host "[i] 未注册开机自启（如需：install.ps1 -AutoStart）" -ForegroundColor DarkGray
}

Write-Host "== 部署完成，程序位于 $exeDest ==" -ForegroundColor Cyan
