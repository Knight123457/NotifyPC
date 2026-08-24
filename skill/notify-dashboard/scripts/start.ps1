# NotifyPC 启动脚本（幂等：部署 + 健康检查 + 必要时重启）
# 规则：9875 与 9876 必须同 PID 同时 LISTENING，否则杀掉残缺进程并重启。
# 用法：powershell -ExecutionPolicy Bypass -File start.ps1
$ErrorActionPreference = "Stop"

$skillRoot = Split-Path -Parent $PSScriptRoot
$tcpPort = 9876
$dashPort = 9875
$exeDest = Join-Path $env:USERPROFILE "NotifyPC\notify-bridge.exe"
$exeSrc = Join-Path $skillRoot "bin\notify-bridge.exe"
$workDir = Split-Path $exeDest

function Get-ListenPid([int]$Port) {
    $matches = netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING"
    foreach ($m in $matches) {
        $parts = ($m.ToString() -split '\s+') | Where-Object { $_ -ne '' }
        if ($parts.Length -ge 5) {
            $pidVal = 0
            if ([int]::TryParse($parts[-1], [ref]$pidVal) -and $pidVal -gt 0) {
                return $pidVal
            }
        }
    }
    return $null
}

function Test-BridgeHealthy {
    $p75 = Get-ListenPid $dashPort
    $p76 = Get-ListenPid $tcpPort
    if ($null -eq $p75 -or $null -eq $p76) { return $false }
    return ($p75 -eq $p76)
}

function Stop-BridgePids {
    $pids = @()
    $a = Get-ListenPid $dashPort
    $b = Get-ListenPid $tcpPort
    if ($a) { $pids += $a }
    if ($b) { $pids += $b }
    Get-Process -Name "notify-bridge" -ErrorAction SilentlyContinue | ForEach-Object { $pids += $_.Id }
    $pids = $pids | Select-Object -Unique
    foreach ($procId in $pids) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "[!] 已结束不健康/残留进程 PID=$procId" -ForegroundColor Yellow
        } catch {}
    }
    Start-Sleep -Milliseconds 800
}

function Wait-DashboardReady {
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-BridgeHealthy) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $tcp.Connect("127.0.0.1", $dashPort)
                $tcp.Close()
                return $true
            } catch {
                try { $tcp.Close() } catch {}
            }
        }
    }
    return $false
}

# 若 skill 内 exe 更新，先停旧进程再部署（避免文件占用）
$needUpdate = $false
if ((Test-Path $exeSrc) -and (Test-Path $exeDest)) {
    if ((Get-Item $exeSrc).LastWriteTime -gt (Get-Item $exeDest).LastWriteTime) { $needUpdate = $true }
} elseif (Test-Path $exeSrc) {
    $needUpdate = $true
}
if ($needUpdate -or -not (Test-BridgeHealthy)) {
    Stop-BridgePids
}

# 部署（幂等）
& (Join-Path $skillRoot "scripts\install.ps1")

if (Test-BridgeHealthy -and -not $needUpdate) {
    Write-Host "[i] 桥接健康（9875/9876 同进程），跳过启动" -ForegroundColor DarkGray
} else {
    if (-not $needUpdate) { Stop-BridgePids }
    Start-Process -FilePath $exeDest -WorkingDirectory $workDir -WindowStyle Hidden
    Write-Host "[+] 已启动 notify-bridge.exe" -ForegroundColor Green
    if (Wait-DashboardReady) {
        Write-Host "[+] 看板已就绪 http://localhost:$dashPort （TCP :$tcpPort 同进程）" -ForegroundColor Green
    } else {
        Write-Host "[!] 等待就绪超时：请检查 %USERPROFILE%\NotifyPC 下进程与防火墙" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[ok] http://localhost:$dashPort" -ForegroundColor Green
