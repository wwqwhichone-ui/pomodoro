# 番茄钟 Pomodoro — 本机部署与运维指南（DEPLOYMENT.md）

本文档说明如何在 **Windows 10/11** 与 **macOS 14+** 本机一键构建、部署、升级番茄钟桌面端及 `pomo` 命令行工具。

---

## 一、Windows 本机一键部署

### 1. 环境要求
- **操作系统**：Windows 10 / 11（x64）
- **Node.js**：20+（推荐 Node 22+）
- **Python 3**：3.9+（用于跨平台 `pomo` CLI）

### 2. 一键构建并部署到本机

在项目根目录的 PowerShell 中执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\install-windows.ps1
```

可选参数：
- `-AutoStart`：同时在系统「启动（Startup）」目录创建快捷方式，实现开机自动启动番茄钟。
- `-FullDist`：除部署本机免解压目录外，同时在 `windows/dist/` 生成绿色压缩包 `.zip` 与单文件 `portable.exe`。
- `-SkipTests`：跳过部署前单元测试。
- `-NoLaunch`：仅安装文件与快捷方式，不立即启动进程。

### 3. 部署产物与目录约定（Windows）

| 项目 | 路径 | 说明 |
|---|---|---|
| 桌面程序安装目录 | `%LOCALAPPDATA%\Programs\Pomodoro\Pomodoro.exe` | 免解压高速启动目录 |
| 桌面快捷方式 | `%USERPROFILE%\Desktop\番茄钟 Pomodoro.lnk` | 双击启动或唤醒主窗口 |
| 开始菜单快捷方式 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\番茄钟 Pomodoro.lnk` | 支持 Windows 搜索唤起 |
| 命令行工具 | `%USERPROFILE%\.local\bin\pomo.cmd` & `pomo` | 自动写入当前用户 `PATH` |
| 状态与任务数据 | `%APPDATA%\Pomodoro\state.json` | 计时设置、今日统计、30 天历史、窗口位置与任务列表 |
| 本地接口配置 | `%APPDATA%\Pomodoro\api.json` | 端口（默认 `47625`）与随机 256-bit Bearer Token |
| Notion 同步配置 | `%APPDATA%\Pomodoro\notion.json` | Notion Token、任务库 ID、每日记录库 ID（不同步到 Git） |

---

## 二、macOS 本机一键部署

### 1. 环境要求
- **操作系统**：macOS 14.0+（Apple Silicon / Intel）
- **编译工具**：Xcode Command Line Tools（`xcode-select --install`）
- **Python 3**：用于 `pomo` CLI

### 2. 一键构建并部署到本机

```bash
chmod +x ./deploy/install-macos.sh
./deploy/install-macos.sh
```

### 3. 部署产物与目录约定（macOS）

| 项目 | 路径 | 说明 |
|---|---|---|
| 应用程序 | `/Applications/Pomodoro.app` | 原生 SwiftUI 应用（ad-hoc 签名） |
| 命令行工具 | `~/.local/bin/pomo` | 软链接到仓库 `tools/pomo` |
| 状态与任务数据 | `UserDefaults`（`local.pomodoro.app`） | 计时设置、任务、今日统计与历史记录 |
| 接口与 Notion 配置 | `~/Library/Application Support/Pomodoro/{api,notion}.json` | 权限 `0600`，仅本机当前用户可读 |

---

## 三、部署后验证与日常运维

部署脚本执行完毕后会自动启动番茄钟并校验接口。也可以在任意终端手动验证：

```bash
pomo health                  # 输出 OK (Pomodoro)
pomo status                  # 查看当前阶段、剩余时间、今日统计与任务明细
pomo history                 # 查看近 7 天专注统计趋势与任务汇总
pomo tasks                   # 查看当前排序后的今日待办
```

### 升级流程
拉取最新代码后重新运行对应平台的部署脚本（`.\deploy\install-windows.ps1` 或 `./deploy/install-macos.sh`）即可平滑替换二进制并保留 `%APPDATA%\Pomodoro` / `UserDefaults` 中的全部任务、历史统计与 Notion 配置。
