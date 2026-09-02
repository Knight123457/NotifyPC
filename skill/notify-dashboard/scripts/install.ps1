# NotifyPC 一键部署脚本（幂等、供应链安全）
# 优先级：本地 skill\bin（随包分发，已校验） → 已部署目录 → 报错/可选手动下载
# 用法：powershell -ExecutionPolicy Bypass -File install.ps1 [-AutoStart] [-KeepConfig] [-AllowDownload]
param(
    [switch]$AutoStart,
    [switch]$KeepConfig,
    [switch]$AllowDownload   # 仅当 skill 包内未包含 exe 时才尝试从 GitHub Release 下载（默认禁止自动下载）
)
$ErrorActionPreference = "Stop"

# ── 版本与供应链安全 ────────────────────────────────────────
# 随包分发的 notify-bridge.exe 必须与此 SHA-256 一致；发布前请用实际 exe 更新。
$ExeVersion      = "4.1.0"
$ExeSha256       = "d637bdcd81edbf824d844985b62b3fa4f82305af677aeb59363fa5d2fb1fb884"
$GitHubReleaseUrl = "https://github.com/Knight123457/NotifyPC/releases/download/v$ExeVersion/notify-bridge.exe"

$skillRoot = Split-Path -Parent $PSScriptRoot
$destDir   = Join-Path $env:USERPROFILE "NotifyPC"
$exeSrc    = Join-Path $skillRoot "bin\notify-bridge.exe"
$exeDest   = Join-Path $destDir "notify-bridge.exe"
$htmlSrc   = Join-Path $skillRoot "dashboard.html"
$htmlDest  = Join-Path $destDir "dashboard.html"
$cfgSrc    = Join-Path $skillRoot "config.example.json"
$cfgDest   = Join-Path $destDir "config.json"

function Get-SHA256([string]$Path) {
    if (-not (Test-Path $Path)) { return "" }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Write-ExeVerification([string]$Path) {
    $hash = Get-SHA256 $Path
    Write-Host "  SHA-256: $hash" -ForegroundColor DarkGray
    if ($ExeSha256 -and ($ExeSha256 -ne "PENDING_UPDATE_AFTER_REBUILD") -and ($hash -ne $ExeSha256.ToLower())) {
        throw "SHA-256 校验失败！期望 $ExeSha256，实际 $hash。该文件可能被篡改，部署已中止。"
    }
    if ($ExeSha256 -eq "PENDING_UPDATE_AFTER_REBUILD") {
        Write-Host "  [warn] install.ps1 中的 ExeSha256 仍为占位符，未启用 SHA-256 白名单校验。" -ForegroundColor Yellow
    }
}

function Download-File([string]$Url, [string]$OutPath, [string]$Label) {
    Write-Host "  正在下载 $Label ..." -ForegroundColor DarkCyan
    Write-Host "  ← $Url" -ForegroundColor DarkGray
    $tmp = "$OutPath.download"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "NotifyPC-install")
        $wc.DownloadFile($Url, $tmp)
        if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 100000) {
            throw "下载文件过小或为空，可能不是有效 exe"
        }
        $hash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $ExeSha256.ToLower()) {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            throw "下载文件 SHA-256 校验失败（$hash），已删除。请检查网络或 GitHub Release 文件是否被篡改。"
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

Write-Host "== NotifyPC v$ExeVersion 部署 ==" -ForegroundColor Cyan
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

# 1) 确保有 notify-bridge.exe（供应链安全：优先随包分发，严禁第三方镜像）
$haveExe = $false
if (Test-Path $exeSrc) {
    Write-Host "[1/5] 从 skill\bin 复制 notify-bridge.exe ..." -ForegroundColor Cyan
    Copy-Item $exeSrc $exeDest -Force
    Write-ExeVerification $exeDest
    Write-Host "[1/5] 已复制并校验 notify-bridge.exe" -ForegroundColor Green
    $haveExe = $true
} elseif (Test-Path $exeDest) {
    Write-Host "[1/5] 已存在 $exeDest，校验 SHA-256 ..." -ForegroundColor DarkGray
    Write-ExeVerification $exeDest
    Write-Host "[1/5] 已存在且校验通过" -ForegroundColor Green
    $haveExe = $true
} elseif ($AllowDownload) {
    Write-Host "[1/5] 本地无 exe，且指定 -AllowDownload，尝试从 GitHub Release 下载..." -ForegroundColor Yellow
    Write-Host "  下载源: $GitHubReleaseUrl" -ForegroundColor DarkGray
    Write-Host "  期望 SHA-256: $ExeSha256" -ForegroundColor DarkGray
    if (Download-File $GitHubReleaseUrl $exeDest "notify-bridge.exe") {
        $haveExe = $true
    }
}

if (-not $haveExe) {
    Write-Host ""
    Write-Host "[错误] 无法获取 notify-bridge.exe" -ForegroundColor Red
    Write-Host "本 skill 默认不自动从网络下载可执行文件，以确保供应链安全。" -ForegroundColor Yellow
    Write-Host "请任选其一：" -ForegroundColor Yellow
    Write-Host "  1) 将 notify-bridge.exe 放入 skill 的 bin\ 目录后重新运行本脚本（推荐）"
    Write-Host "  2) 手动从 GitHub Release 下载固定版本 exe，放到 $exeDest"
    Write-Host "     $GitHubReleaseUrl"
    Write-Host "     下载后请核对 SHA-256: $ExeSha256"
    Write-Host "  3) 如果确实需要自动下载，请使用: install.ps1 -AllowDownload"
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

# 3) config.json（安全默认：127.0.0.1，局域网访问需显式配置 dashToken）
if (-not (Test-Path $cfgDest)) {
    if (Test-Path $cfgSrc) {
        Copy-Item $cfgSrc $cfgDest -Force
    } else {
        '{"dashPort":9875,"dashBind":"127.0.0.1","dashToken":"","dashLocalBypass":true,"androidBleAddress":"","androidNames":[]}' |
            Out-File $cfgDest -Encoding utf8
    }
    Write-Host "[3/5] 已创建 config.json（默认仅监听 127.0.0.1，局域网访问请在 config.json 中设置 dashToken）" -ForegroundColor Green
} else {
    Write-Host "[3/5] config.json 已存在，保留原配置" -ForegroundColor DarkGray
}

# 4) 注册开机自启
if ($AutoStart) {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $runKey -Name "NotifyPC" -Value "`"$exeDest`""
    Write-Host "[4/5] 已注册开机自启（HKCU Run）" -ForegroundColor Green
} else {
    Write-Host "[4/5] 未注册开机自启（如需：install.ps1 -AutoStart）" -ForegroundColor DarkGray
}

Write-Host "== 部署完成，程序位于 $exeDest ==" -ForegroundColor Cyan
