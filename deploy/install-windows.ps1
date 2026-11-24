<#
.SYNOPSIS
  番茄钟 Pomodoro — Windows 本机一键构建、部署与启动脚本

.DESCRIPTION
  1. 安装依赖并运行核心单测与 CLI 联调测试
  2. 使用 electron-builder 打包 Windows 桌面应用
  3. 部署到 %LOCALAPPDATA%\Programs\Pomodoro（免解压高速启动）
  4. 安装跨平台命令行工具 pomo / pomo.cmd 到 %USERPROFILE%\.local\bin 并加入用户 PATH
  5. 创建桌面与开始菜单快捷方式（可选开机自启 -AutoStart）
  6. 启动本机 Pomodoro 并校验 127.0.0.1:47625 健康状态与 pomo status
#>
param(
    [switch]$SkipTests,
    [switch]$FullDist,
    [switch]$AutoStart,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$WinDir = Join-Path $RepoRoot "windows"
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Pomodoro"
$CliBinDir = Join-Path $HOME ".local\bin"

Write-Host "==> [1/6] 检查 Windows 端依赖 ($WinDir)..." -ForegroundColor Cyan
Push-Location $WinDir
try {
    if (-not (Test-Path (Join-Path $WinDir "node_modules\electron"))) {
        Write-Host "    正在安装 npm 依赖..."
        & npm.cmd ci
        if ($LASTEXITCODE -ne 0) { throw "npm ci 失败" }
    }

    if (-not $SkipTests) {
        Write-Host "==> [2/6] 运行单元测试与 API/CLI 集成测试..." -ForegroundColor Cyan
        & npm.cmd test
        if ($LASTEXITCODE -ne 0) { throw "单元测试未通过" }
    } else {
        Write-Host "==> [2/6] 已跳过测试 (-SkipTests)" -ForegroundColor Yellow
    }

    Write-Host "==> [3/6] 构建 Windows 桌面版..." -ForegroundColor Cyan
    if ($FullDist) {
        & npm.cmd run dist:win
    } else {
        & npx.cmd electron-builder --win dir --x64
    }
    if ($LASTEXITCODE -ne 0) { throw "electron-builder 打包失败" }
} finally {
    Pop-Location
}

$UnpackedDir = Join-Path $WinDir "dist\win-unpacked"
$BuiltExe = Join-Path $UnpackedDir "Pomodoro.exe"
if (-not (Test-Path $BuiltExe)) {
    throw "未找到构建产物：$BuiltExe"
}

Write-Host "==> [4/6] 部署应用到 $InstallDir ..." -ForegroundColor Cyan
$running = Get-Process -Name "Pomodoro" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "    正在关闭运行中的旧版 Pomodoro 实例..."
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 600
}

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $UnpackedDir "*") -Destination $InstallDir -Recurse -Force

$DeployedExe = Join-Path $InstallDir "Pomodoro.exe"
$IconPath = Join-Path $WinDir "assets\icon.ico"
if (Test-Path $IconPath) {
    Copy-Item -Path $IconPath -Destination (Join-Path $InstallDir "icon.ico") -Force
}

Write-Host "==> [5/6] 安装 pomo CLI 到 $CliBinDir 并配置快捷方式..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $CliBinDir -Force | Out-Null
Copy-Item -Path (Join-Path $RepoRoot "tools\pomo") -Destination (Join-Path $CliBinDir "pomo") -Force
Copy-Item -Path (Join-Path $RepoRoot "tools\pomo.cmd") -Destination (Join-Path $CliBinDir "pomo.cmd") -Force

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $UserPath) { $UserPath = "" }
$PathParts = $UserPath -split ";" | Where-Object { $_ -ne "" }
if ($PathParts -notcontains $CliBinDir) {
    $NewUserPath = (($PathParts + $CliBinDir) -join ";")
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    Write-Host "    已将 $CliBinDir 添加到当前用户 PATH 环境变量"
}
if (($env:Path -split ";") -notcontains $CliBinDir) {
    $env:Path = "$CliBinDir;$env:Path"
}

$WshShell = New-Object -ComObject WScript.Shell
$ShortcutTargets = @(
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "番茄钟 Pomodoro.lnk"),
    (Join-Path ([Environment]::GetFolderPath("Programs")) "番茄钟 Pomodoro.lnk")
)
if ($AutoStart) {
    $ShortcutTargets += (Join-Path ([Environment]::GetFolderPath("Startup")) "番茄钟 Pomodoro.lnk")
}
foreach ($lnkPath in $ShortcutTargets) {
    $sc = $WshShell.CreateShortcut($lnkPath)
    $sc.TargetPath = $DeployedExe
    $sc.WorkingDirectory = $InstallDir
    $sc.Description = "极简纸墨风格番茄钟 Pomodoro"
    if (Test-Path (Join-Path $InstallDir "icon.ico")) {
        $sc.IconLocation = (Join-Path $InstallDir "icon.ico")
    }
    $sc.Save()
}

if (-not $NoLaunch) {
    Write-Host "==> [6/6] 启动本机番茄钟并验证接口健康状态..." -ForegroundColor Cyan
    try {
        $cim = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine = "`"$DeployedExe`""
            CurrentDirectory = $InstallDir
        } -ErrorAction Stop
        if ($cim.ReturnValue -ne 0) {
            Start-Process -FilePath $DeployedExe -WorkingDirectory $InstallDir
        }
    } catch {
        Start-Process -FilePath $DeployedExe -WorkingDirectory $InstallDir
    }

    $healthy = $false
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:47625/v1/health" -Method Get -TimeoutSec 2
            if ($resp.ok -eq $true) {
                $healthy = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 350
        }
    }

    if (-not $healthy) {
        throw "Pomodoro 已启动，但在 20 秒内未检测到 http://127.0.0.1:47625/v1/health 响应"
    }

    Write-Host ""
    Write-Host "✅ 番茄钟已成功部署并启动！" -ForegroundColor Green
    Write-Host "   程序位置 : $DeployedExe"
    Write-Host "   数据目录 : $(Join-Path $env:APPDATA 'Pomodoro')"
    Write-Host "   CLI 位置 : $(Join-Path $CliBinDir 'pomo.cmd')"
    Write-Host "   本地接口 : http://127.0.0.1:47625/v1/health"
    Write-Host ""
    & (Join-Path $CliBinDir "pomo.cmd") status
} else {
    Write-Host "==> [6/6] 部署完成（已跳过启动 -NoLaunch）" -ForegroundColor Green
}
