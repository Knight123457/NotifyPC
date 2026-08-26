# NotifyPC 一键部署脚本（幂等）
# 优先级：本地 skill\bin → 已部署目录 → 镜像下载 → GitHub 直连
# 用法：powershell -ExecutionPolicy Bypass -File install.ps1 [-AutoStart]
param(
    [switch]$AutoStart,
    [switch]$KeepConfig
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

# GitHub 下载源（优先镜像，避免国内直连超时；最后兜底直连）
$ExeDownloadUrls = @(
    "https://ghproxy.net/https://raw.githubusercontent.com/Knight123457/NotifyPC/main/Release/notify-bridge.exe",
    "https://gh-proxy.com/https://raw.githubusercontent.com/Knight123457/NotifyPC/main/Release/notify-bridge.exe",
    "https://github.com/Knight123457/NotifyPC/raw/main/Release/notify-bridge.exe"
)

function Download-File([string]$Url, [string]$OutPath, [string]$Label) {
    Write-Host "  正在下载 $Label ..." -ForegroundColor DarkCyan
    Write-Host "  ← $Url" -ForegroundColor DarkGray
    $tmp = "$OutPath.download"
    try {
        # TLS1.2；大文件用 WebClient 更稳
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "NotifyPC-install")
        $wc.DownloadFile($Url, $tmp)
        if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 100000) {
            throw "下载文件过小或为空（$((Get-Item $tmp -ErrorAction SilentlyContinue).Length) bytes），可能不是有效 exe"
        }
        Move-Item -Force $tmp $OutPath
        Write-Host "  [ok] 已保存 $OutPath ($([math]::Round((Get-Item $OutPath).Length/1MB,1)) MB)" -ForegroundColor Green
        return $true
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        Write-Host "  [x] 失败: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

Write-Host "== NotifyPC 部署 ==" -ForegroundColor Cyan
Write-Host "skill 目录: $skillRoot"
Write-Host "部署目标 : $destDir"

# 0) 清理旧部署，防止旧 exe / 旧 config 与新 skill 冲突
$oldProc = Get-Process -Name "notify-bridge" -ErrorAction SilentlyContinue
if ($oldProc) {
    Write-Host "[0/5] 正在停止旧 notify-bridge 进程 (PID $($oldProc.Id))..." -ForegroundColor Yellow
    Stop-Process -Name "notify-bridge" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "[0/5] 旧进程已停止" -ForegroundColor Green
}

if (Test-Path $destDir) {
    $cfgOld = Join-Path $destDir "config.json"
    if ((Test-Path $cfgOld) -and -not $KeepConfig) {
        $backupDir = "$destDir.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "[0/5] 备份旧 config.json 到 $backupDir" -ForegroundColor DarkYellow
        New-Item -ItemType Directory -Path $backupDir | Out-Null
        Copy-Item $cfgOld $backupDir -Force
    }
    Write-Host "[0/5] 删除旧部署目录 $destDir" -ForegroundColor Yellow
    Remove-Item -Path $destDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $destDir) {
        Write-Host "[警告] 无法完全删除 $destDir，尝试继续覆盖..." -ForegroundColor Red
    } else {
        Write-Host "[0/5] 旧目录已清理" -ForegroundColor Green
    }
}

if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }

# 1) 确保有 notify-bridge.exe
$haveExe = $false
if (Test-Path $exeDest) {
    Write-Host "[1/5] 已存在 $exeDest，跳过下载" -ForegroundColor DarkGray
    $haveExe = $true
} elseif (Test-Path $exeSrc) {
    Copy-Item $exeSrc $exeDest -Force
    Write-Host "[1/5] 已从 skill\bin 复制 notify-bridge.exe" -ForegroundColor Green
    $haveExe = $true
} else {
    Write-Host "[1/5] 本地无 exe，尝试从 GitHub 下载…" -ForegroundColor Yellow
    foreach ($url in $ExeDownloadUrls) {
        if (Download-File $url $exeDest "notify-bridge.exe") {
            $haveExe = $true
            break
        }
    }
}

if (-not $haveExe) {
    Write-Host ""
    Write-Host "[错误] 无法获取 notify-bridge.exe" -ForegroundColor Red
    Write-Host "请任选其一：" -ForegroundColor Yellow
    Write-Host "  1) 浏览器打开以下镜像链接下载 exe，放到 $exeDest"
    Write-Host "     https://ghproxy.net/https://raw.githubusercontent.com/Knight123457/NotifyPC/main/Release/notify-bridge.exe"
    Write-Host "     https://gh-proxy.com/https://raw.githubusercontent.com/Knight123457/NotifyPC/main/Release/notify-bridge.exe"
    Write-Host "  2) 或把 exe 提交到仓库 Release/notify-bridge.exe 后再运行本脚本"
    exit 1
}

# 2) dashboard.html（来自 skill 本地，不依赖 GitHub）
if (Test-Path $htmlSrc) {
    Copy-Item $htmlSrc $htmlDest -Force
    Write-Host "[2/5] 已同步 dashboard.html（来自 skill）" -ForegroundColor Green
} elseif (Test-Path $htmlDest) {
    Write-Host "[2/5] dashboard.html 已存在，跳过" -ForegroundColor DarkGray
} else {
    Write-Host "[2/5] 无外部看板页，使用 exe 内嵌版" -ForegroundColor DarkGray
}

# 3) config.json
if (-not (Test-Path $cfgDest)) {
    if (Test-Path $cfgSrc) {
        Copy-Item $cfgSrc $cfgDest -Force
    } else {
        '{"dashPort":9875,"dashBind":"0.0.0.0","dashLocalBypass":true,"androidBleAddress":"","androidNames":[]}' |
            Out-File $cfgDest -Encoding utf8
    }
    Write-Host "[3/5] 已创建 config.json（dashToken 首次启动自动生成）" -ForegroundColor Green
} else {
    Write-Host "[3/5] config.json 已存在，保留原配置" -ForegroundColor DarkGray
}

# 4) 完成（v4 仅 BLE，无需 TCP 防火墙）
Write-Host "[4/5] v4 使用 BLE，无需放行 TCP 9876" -ForegroundColor DarkGray

# 5) 注册开机自启
if ($AutoStart) {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $runKey -Name "NotifyPC" -Value "`"$exeDest`""
    Write-Host "[5/5] 已注册开机自启（HKCU Run）" -ForegroundColor Green
} else {
    Write-Host "[5/5] 未注册开机自启（如需：install.ps1 -AutoStart）" -ForegroundColor DarkGray
}

Write-Host "== 部署完成，程序位于 $exeDest ==" -ForegroundColor Cyan
