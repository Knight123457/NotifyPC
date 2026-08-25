# NotifyPC 启动脚本（v4 BLE）
# 规则：HTTP 看板 :9875 在监听即视为健康。
$ErrorActionPreference = "Stop"

$skillRoot = Split-Path -Parent $PSScriptRoot
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
    return $null -ne (Get-ListenPid $dashPort)
}

function Stop-BridgePids {
    $pids = @()
    $a = Get-ListenPid $dashPort
    if ($a) { $pids += $a }
    Get-Process -Name "notify-bridge" -ErrorAction SilentlyContinue | ForEach-Object { $pids += $_.Id }
    $pids = $pids | Select-Object -Unique
    foreach ($procId in $pids) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "[!] 已结束残留进程 PID=$procId" -ForegroundColor Yellow
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

$needUpdate = $false
if ((Test-Path $exeSrc) -and (Test-Path $exeDest)) {
    if ((Get-Item $exeSrc).LastWriteTime -gt (Get-Item $exeDest).LastWriteTime) { $needUpdate = $true }
} elseif (Test-Path $exeSrc) {
    $needUpdate = $true
}
if ($needUpdate -or -not (Test-BridgeHealthy)) {
    Stop-BridgePids
}

& (Join-Path $skillRoot "scripts\install.ps1")

if (Test-BridgeHealthy -and -not $needUpdate) {
    Write-Host "[i] 桥接健康（:$dashPort），跳过启动" -ForegroundColor DarkGray
} else {
    if (-not $needUpdate) { Stop-BridgePids }
    Start-Process -FilePath $exeDest -WorkingDirectory $workDir -WindowStyle Hidden
    Write-Host "[+] 已启动 notify-bridge.exe v4（BLE）" -ForegroundColor Green
    if (Wait-DashboardReady) {
        Write-Host "[+] 看板已就绪 http://localhost:$dashPort" -ForegroundColor Green
    } else {
        Write-Host "[!] 等待就绪超时：请检查蓝牙与 %USERPROFILE%\NotifyPC" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[ok] http://localhost:$dashPort" -ForegroundColor Green
