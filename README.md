# 番茄钟 Pomodoro (macOS & Windows)

> **Minimalist paper-and-ink Pomodoro timer** for **macOS** (native SwiftUI, zero dependencies) and **Windows** (Electron desktop app with matching design & behavior) — full-screen on Sidecar iPad or secondary displays, live menu bar / system tray countdown, universal Notion task sync, and local AI HTTP API + `pomo` CLI.
>
> - **Dual-platform**: pure SwiftUI native app on macOS (`arm64` + `x86_64`), Electron app on Windows (`x64`)
> - **Three adaptive layouts**: portrait window, multi-monitor / Sidecar landscape full-screen, floating mini bar
> - **Universal Notion sync**: paste any Notion database URL or ID — auto-detects schema (English & Chinese column names)
> - **AI-agent ready**: loopback-only `127.0.0.1` Bearer-authenticated JSON API + cross-platform Python `pomo` CLI
>
> **Downloads**: [Latest Release (macOS Universal + Windows Portable)](https://github.com/wwqwhichone-ui/pomodoro/releases/latest)

一款专为 **macOS** 与 **Windows** 打造的纸墨风格番茄钟应用。采用温暖纸色 / 深咖双主题与压缩粗体大数字排版，内置完整番茄工作法（预估、内外打断、作废、休息建议）、顶部菜单栏 / 系统托盘实时倒计时、副屏 / iPad 随航自动全屏联动、通用 Notion 数据库同步，以及面向 AI 助手（Claude Code / Codex 等）的本机命令行与 HTTP 接口。

---

## 快速开始（直接下载）

前往 **[GitHub Releases 最新版本](https://github.com/wwqwhichone-ui/pomodoro/releases/latest)** 下载对应系统安装包：

### macOS（Apple Silicon + Intel 通用版）
1. 下载 `Pomodoro-v*-macos-universal.zip`（需 macOS 14.0+）。
2. 解压后将 `Pomodoro.app` 拖入「应用程序（`/Applications`）」。
3. **首次打开提示**：由于使用免费本地自签名（ad-hoc），未经过付费 Apple 开发者公证，首次双击如提示“无法验证开发者”或“已损坏”，在终端运行一次即可打开（或在「系统设置 → 隐私与安全性」底部点击「仍要打开」）：
   ```bash
   xattr -cr /Applications/Pomodoro.app
   ```

### Windows（x64 绿色便携版 / 单文件版）
1. 在 Releases 页面任选其一（需 Windows 10 / 11 64 位）：
   - **`Pomodoro-v*-windows-x64-portable.exe`**：单文件绿色版，无需安装，双击即用。
   - **`Pomodoro-v*-windows-x64.zip`**：绿色压缩包，解压后运行其中的 `Pomodoro.exe`（启动更快）。
2. **首次打开提示**：由于开源项目未购买付费代码签名证书，如触发 Windows Defender SmartScreen“Windows 已保护你的电脑”提示，点击 **「更多信息」→「仍要运行」** 即可。

---

## 核心特性

- **纸墨双主题 + 自适应三形态布局**：
  - **竖屏标准窗**（日常使用）：随时点开今日待办浮层。
  - **横屏分栏全屏**（副屏 / iPad 随航 / 宽屏）：左侧「今日成果 + 当前任务 + 今日待办」，右侧大号分段进度环与控制区；移至 iPad 随航或外接副屏自动全屏并阻止屏幕休眠，一键「发送到副屏 / 移回主屏」。
  - **迷你悬浮条**：置顶显示剩余时间、当前任务与细线进度条。
- **顶部菜单栏 / 系统托盘实时倒计时**：
  - macOS 在顶部状态栏实时显示图标与剩余时间；Windows 在系统托盘悬停显示倒计时、左键唤出主窗、右键快捷控制（均可在设置中随时开关）。
- **完整番茄工作法**：
  - 任务预估番茄数（`− / +`）与超出提示，点击待办任务即可展开显示完整长标题与操作栏。
  - `-` 记录**内部打断**、`=` 记录**外部打断**（按物理键码拦截，中文输入法下也可用），误按可点击次数数字直接 `−1` 撤销。
  - 专注中途跳过记为**作废**，自动按完成组数切换短休息 / 长休息与休息建议，支持设置内两步确认「清零今日成果」。
- **通用 Notion 数据库同步**：支持直接粘贴 Notion 数据库链接或 ID，自动识别中英文列名与字段类型（`status` / `select` / `checkbox` / `date` / `multi_select`），支持自定义 DDL 提前天数与可选完成回写。
- **AI 友好的本机接口与 `pomo` CLI**：双端均监听 `127.0.0.1:47625` 并强制随机 Bearer Token 鉴权，AI 助手可直接查询状态、增删改任务、启动/暂停计时、记录或撤销打断。

---

## 界面操作与快捷键

### 快速添加任务语法

在「今日待办」底部输入框末尾自由组合以下标记：

```text
写周报 ×2 P1 @11-25
```

- `×2` / `x2` / `*2`：预估番茄数（1–12，默认 1）
- `P0`–`P3`：优先级（`P0` 紧急 ～ `P3` 低）
- `@今天` / `@明天` / `@后天` / `@11-25` / `@2026-11-25`：截止日期（DDL）

> 任务较长时，在「今日待办」中**点击任意任务**即可展开显示完整标题，不再受两行省略限制；点选未完成任务的同时还会展开预估调整与 Notion 跳转/删除按钮。

### 快捷键一览

| 功能 | macOS 快捷键 | Windows 快捷键 | 说明 |
|---|---|---|---|
| 开始 / 暂停 / 继续 | `空格` | `空格` | 输入框聚焦时自动放行；中文输入法下同样有效 |
| 记录内部打断 | `-` | `-` | 自己走神或想起别的事，记下后继续专注 |
| 记录外部打断 | `=` | `=` | 被他人或消息打断，推迟处理或记录 |
| 重置当前阶段 | `⌘R` | `Ctrl+R` | 回到当前阶段的完整时长 |
| 放弃 / 跳过本段 | `⇧⌘S` | `Ctrl+Shift+S` | 专注中途跳过记为作废；休息时直接结束休息 |
| 发送到副屏 / iPad 并全屏 | `⌥⌘I` | `Ctrl+Alt+I` | macOS 识别随航，Windows 识别外接/无线副屏 |
| 移回主屏 | `⌥⌘M` | `Ctrl+Alt+M` | 退出全屏并回到主屏原窗口位置 |
| 迷你悬浮窗 | `⌥⌘P` | `Ctrl+Alt+P` | 切换置顶悬浮条模式 |
| 全屏 / 退出全屏 | `⌃⌘F` | `F11` | 切换主窗口全屏状态 |

---

## Notion 同步配置

无需修改任何源码或固定模板，任意结构的 Notion 任务表均可使用：

1. 打开 [Notion My Integrations](https://www.notion.so/profile/integrations)，创建一个 Internal Integration，复制 Token（`ntn_…` 或 `secret_…`）。
2. 在你的 Notion 任务数据库页面右上角 `···` → **Connections**（或在 Integration 的 **Access** 设置中），将该数据库授权给这个 Integration。
3. 打开番茄钟右上角 **设置 → 同步与接口**：
   - 粘贴 **Integration 令牌**
   - 直接粘贴任务数据库的**网页链接**或 **Database / Data Source ID**
   - 按需设置 **DDL 提前天数**（1–30 天，默认 7 天）、**排除分类**（逗号分隔，默认 `Event`，让活动仅留在 Notion 日历视图而不进今日待办）和 **完成时回写 Notion**（默认关闭）
   - 如需记录每日番茄成果，在 **每日记录同步** 栏粘贴另一个记录数据库（如 `Pomodoro Log`）链接或 ID，点击 **保存记录库** 即可启用：每个番茄完成时实时更新当天记录，跨天重启/休眠唤醒也会自动补传昨日数据
   - 点击 **保存并同步**

### 字段自动适配规则

App 会在同步前自动读取数据库 schema，按字段类型与常见中英文列名自动匹配（不存在的列自动跳过，不会报错）：

| 用途 | 识别方式（示例列名） |
|---|---|
| 任务标题 | 数据库中唯一的 `title` 类型字段（如 `Name`、`Task Name`、`任务`） |
| 完成状态 | `status` 类型 → `select`（`Status` / `状态`）→ `checkbox`（`Done` / `已完成`） |
| 截止日期（DDL） | `Due Date` / `Due` / `DDL` / `Deadline` / `截止日期` / `截止时间`（`date`） |
| 计划日期 | `Scheduled Date` / `Do Date` / `Plan Date` / `计划日期`（`date`） |
| 优先级 | `Priority` / `优先级`（支持 `P0–P3` 或 `Urgent`/`High`/`Medium`/`Low`、`高`/`中`/`低`） |
| 置顶 / Top 3 | `Top 3` / `Focus` / `Pinned` / `Important` / `重点` / `置顶`（`checkbox`） |
| 标签 / 课程 / 项目 | `Course` / `Category` / `Project` / `Area` / `Tag` / `课程` / `分类` / `项目` / `标签` |

如配置了 **每日番茄记录同步**（推荐单独建一个 `Pomodoro Log` 数据库），支持自动识别以下中英文列名：
- `Day` / `日期标题`（Title）、`Date` / `日期`（Date，用作按天幂等匹配主键）
- `Pomodoros` / `番茄数`、`Focus Minutes` / `专注分钟`、`Internal Interruptions` / `内打断`、`External Interruptions` / `外打断`、`Voided` / `作废`（Number）
- `Tasks` / `任务`（Rich text，记录当日完成番茄的任务与计数）

---

## AI Agent 与命令行接入

App 启动后自动在本地开启 HTTP JSON 服务（`http://127.0.0.1:47625`），AI 工具可直接调用跨平台的 `tools/pomo` 命令行（加 `--json` 可输出结构化 JSON）：

```bash
pomo health                                           # 存活检查
pomo status                                           # 查看阶段、剩余时间与今日统计
pomo tasks                                            # 查看排序后的今日待办
pomo add "整理实验数据" -e 2 -p P1 -d 明天 --select      # 添加任务并设为当前任务
pomo start                                            # 开始专注
pomo interrupt internal                               # 记录一次内部打断
pomo interrupt internal --undo                        # 撤销本番茄内误记的一次打断
pomo done 1                                           # 按序号或 8 位 id 前缀标记完成
pomo sync                                             # 立即同步 Notion 任务
pomo log-today                                        # 立即同步今日番茄记录到 Notion
```

完整的 HTTP 接口路径、请求体与响应格式请见 [docs/API.md](docs/API.md)。

---

## 从源码编译与测试

### macOS 原生版本（零第三方依赖）

需要 macOS 14.0+、Xcode Command Line Tools（`xcode-select --install`）和 Python 3（仅 `pomo` CLI 需要）：

```bash
git clone https://github.com/wwqwhichone-ui/pomodoro.git
cd pomodoro

./build.sh                            # 编译到 build/Pomodoro.app
./build.sh --install --install-cli    # 安装到 /Applications 并链接 pomo 到 ~/.local/bin
./build.sh --universal --zip          # 打包 Apple Silicon + Intel 通用 zip
```

### Windows 版本（Electron）

需要 Node.js 20+（推荐 22）和 Python 3（可选，用于 `tools/pomo` CLI 联调）：

```bash
cd windows
npm install          # 安装开发依赖（electron / electron-builder）
npm test             # 运行单元测试与 API/CLI 集成测试
npm start            # 本地直接启动桌面端
npm run dist:win     # 打包 Windows 便携 .zip 与单文件 portable.exe 到 windows/dist/
```

---

## 隐私与安全

- **仅回环监听**：双端 HTTP 服务均显式绑定 `127.0.0.1`，局域网和公网无法访问。
- **随机令牌鉴权**：首次启动自动生成 256-bit 随机 Bearer Token（除 `/v1/health` 外所有接口均需校验）。
- **本地存储隔离**：
  - **macOS**：令牌保存在 `~/Library/Application Support/Pomodoro/{api,notion}.json`（权限 `0600`），任务与设置保存在系统 `UserDefaults`（`local.pomodoro.app`）。
  - **Windows**：配置与令牌保存在 `%APPDATA%\Pomodoro\{state,api,notion}.json`。
  - 全部数据仅存本机，不经过任何第三方服务器。

---

## 目录结构

```text
Sources/                 macOS 原生 SwiftUI 源码（零第三方依赖）
windows/                 Windows Electron 桌面端（1:1 复刻视觉、副屏、托盘、Notion、API）
  src/                   主进程、Preload、Model/Notion/API 与渲染层
  assets/                Windows 图标资源（icon.ico / icon.png / tray.png）
  test/                  核心单测与端到端冒烟测试
tools/pomo               跨平台 Python 3 命令行工具（支持 macOS / Windows / Linux）
docs/API.md              本地 HTTP 接口与 Notion 同步详尽文档
build.sh                 macOS 一键编译、Universal 打包与安装脚本
```

## License

[MIT License](LICENSE) © 2026 Weiqi Wang
