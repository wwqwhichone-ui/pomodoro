# 番茄钟 Pomodoro (macOS)

> **Native macOS Pomodoro timer** built purely in Swift & SwiftUI with zero third-party dependencies — designed to look like printed ink on warm paper, go full-screen on an iPad via Sidecar, live quietly in your menu bar, sync with **any** Notion task database, and let AI coding agents drive your focus flow via a local HTTP API & `pomo` CLI.
>
> - **Zero dependencies**: single-command `swiftc` build, macOS 14+, native SwiftUI & AppKit
> - **Three adaptive layouts + menu bar**: portrait window, Sidecar iPad landscape full-screen, floating mini bar, and live menu bar countdown
> - **Universal Notion sync**: paste any Notion database URL or ID — auto-detects schema (English & Chinese column names)
> - **AI-agent ready**: loopback-only `127.0.0.1` Bearer-authenticated JSON API + Python `pomo` CLI

一款专为 macOS 与 iPad 随航（Sidecar）打造的原生番茄钟应用。采用纸墨质感（纸色 / 深咖双主题）与压缩粗体大数字排版，内置完整番茄工作法（预估、内外打断、作废、休息建议）、顶部菜单栏实时倒计时、通用 Notion 数据库同步，以及面向 AI 助手（Claude Code / Codex 等）的本机命令行与 HTTP 接口。

---

## 核心特性

- **零第三方依赖，纯原生构建**：仅使用 SwiftUI、AppKit 与 Network.framework，一条 `swiftc` 命令即可编译打包成原生 `.app`，体积轻量、启动秒开。
- **纸墨双主题 + 自适应三形态布局**：
  - **竖屏标准窗**（Mac 日常使用）：可随时点开今日待办浮层。
  - **横屏分栏全屏**（iPad 随航 / 宽屏）：左侧「今日成果 + 当前任务 + 今日待办」，右侧大号分段进度环与控制区；拖到 iPad 随航屏幕自动全屏并防止息屏断连，一键「发送到 iPad / 移回 Mac」（`⌥⌘I` / `⌥⌘M`）。
  - **迷你悬浮条**（`⌥⌘P`）：置顶显示剩余时间、当前任务与细线进度条。
- **顶部菜单栏实时倒计时**：可在顶部状态栏实时显示当前阶段图标与剩余时间，点击直接开始/暂停、记录打断、切换迷你窗或唤出主窗口（可在设置中随时关闭）。
- **完整番茄工作法**：
  - 任务预估番茄数（`− / +`）与超出提示，点击待办任务即可展开显示完整长标题与操作栏。
  - `-` 记录**内部打断**、`=` 记录**外部打断**（按物理键码拦截，中文输入法下也可用），误按可点击次数数字直接 `−1` 撤销。
  - 专注中途跳过记为**作废**，自动按完成组数切换短休息 / 长休息与休息建议，支持设置内两步确认「清零今日成果」。
- **通用 Notion 数据库同步**：支持直接粘贴 Notion 数据库链接或 ID，自动识别中英文列名与字段类型（`status` / `select` / `checkbox` / `date` / `multi_select`），支持自定义 DDL 提前天数与可选完成回写。
- **AI 友好的本机接口与 `pomo` CLI**：默认监听 `127.0.0.1:47625` 并强制随机 Bearer Token 鉴权，AI 助手可直接查询状态、增删改任务、启动/暂停计时、记录或撤销打断。

---

## 快速开始

### 环境要求

- macOS 14.0 (Sonoma) 或更高版本
- 已安装 Xcode 或 Xcode Command Line Tools（提供 `swiftc`）：
  ```bash
  xcode-select --install
  ```
- Python 3（macOS 自带或 CLT 提供，仅 `pomo` CLI 需要）

### 编译、安装与运行

```bash
git clone https://github.com/wwqwhichone-ui/pomodoro-macos.git
cd pomodoro-macos

# 仅编译到 build/Pomodoro.app
./build.sh

# 编译并安装到 /Applications，同时安装 pomo 命令行到 ~/.local/bin/pomo
./build.sh --install --install-cli

# 运行应用
open /Applications/Pomodoro.app   # 若未加 --install，则运行 open build/Pomodoro.app
```

> 若提示 `pomo: command not found`，请确认 `~/.local/bin` 已加入你的 `PATH`（例如在 `~/.zshrc` 中添加 `export PATH="$HOME/.local/bin:$PATH"`）。

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

| 快捷键 | 功能 | 说明 |
|---|---|---|
| `空格` | 开始 / 暂停 / 继续 | 输入框聚焦时自动放行；中文输入法下同样有效 |
| `-` | 记录内部打断 | 自己走神或想起别的事，记下后继续专注 |
| `=` | 记录外部打断 | 被他人或消息打断，推迟处理或记录 |
| `⌘R` | 重置当前阶段 | 回到当前阶段的完整时长 |
| `⇧⌘S` | 放弃 / 跳过本段 | 专注中途跳过记为作废；休息时直接结束休息 |
| `⌥⌘I` | 发送到 iPad 并全屏 | 检测到随航屏幕时一键移至 iPad 全屏 |
| `⌥⌘M` | 移回 Mac | 退出随航全屏并回到 Mac 原窗口位置 |
| `⌥⌘P` | 迷你悬浮窗 | 切换置顶悬浮条模式 |
| `⌃⌘F` | 全屏 / 退出全屏 | 切换主窗口全屏状态 |

---

## Notion 同步配置

无需修改任何源码或固定模板，任意结构的 Notion 任务表均可使用：

1. 打开 [Notion My Integrations](https://www.notion.so/profile/integrations)，创建一个 Internal Integration，复制 Token（`ntn_…` 或 `secret_…`）。
2. 在你的 Notion 任务数据库页面右上角 `···` → **Connections**（或在 Integration 的 **Access** 设置中），将该数据库授权给这个 Integration。
3. 打开番茄钟右上角 **设置 → 同步与接口**：
   - 粘贴 **Integration 令牌**
   - 直接粘贴该 Notion 数据库的**网页链接**或 **Database / Data Source ID**
   - 按需设置 **DDL 提前天数**（1–30 天，默认 7 天）和 **完成时回写 Notion**（默认关闭）
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

---

## AI Agent 与命令行接入

App 启动后自动在本地开启 HTTP JSON 服务（`http://127.0.0.1:47625`），AI 工具可直接调用 `pomo` 命令行（加 `--json` 可输出结构化 JSON）：

```bash
pomo health                                           # 存活检查
pomo status                                           # 查看阶段、剩余时间与今日统计
pomo tasks                                            # 查看排序后的今日待办
pomo add "整理实验数据" -e 2 -p P1 -d 明天 --select      # 添加任务并设为当前任务
pomo start                                            # 开始专注
pomo interrupt internal                               # 记录一次内部打断
pomo interrupt internal --undo                        # 撤销本番茄内误记的一次打断
pomo done 1                                           # 按序号或 8 位 id 前缀标记完成
pomo sync                                             # 立即同步 Notion
```

完整的 HTTP 接口路径、请求体与响应格式请见 [docs/API.md](docs/API.md)。

---

## 隐私与安全

- **仅回环监听**：HTTP 服务显式绑定 `.loopback`（`127.0.0.1`），局域网和公网无法访问。
- **随机令牌鉴权**：首次启动自动生成 256-bit 随机 Bearer Token（除 `/v1/health` 外所有接口均需校验）。
- **本地权限隔离**：Notion 令牌与 API 配置分别保存在 `~/Library/Application Support/Pomodoro/notion.json` 与 `api.json`，文件权限固定为 `0600`；任务与计时设置保存在系统 `UserDefaults`（`local.pomodoro.app`），不经过任何第三方服务器。

---

## 目录结构

```text
Sources/
  main.swift               App 入口与原生菜单栏命令
  Model.swift              计时状态机、任务模型、DDL 解析与统计逻辑
  WindowManager.swift      Sidecar 屏幕识别、自动全屏、迷你窗与物理键码快捷键
  MenuBarController.swift  顶部状态栏实时倒计时与快捷操作菜单
  NotionSync.swift         Notion 链接解析、Schema 自动探测、同步与可选回写
  APIServer.swift          NWListener 本地回环 HTTP API 服务
  Theme.swift              纸色 / 深咖双主题配色、字体与按钮按压动效
  Components.swift         分段进度环、任务清单、点击展开完整标题、打断胶囊等组件
  Layouts.swift            横屏 / 竖屏 / 迷你三形态布局与设置面板
  SettingsControls.swift   纸墨风自定义设置控件
tools/
  pomo                     Python 3 命令行工具（零外部依赖）
  make_icon.swift          AppIcon.icns 图标生成脚本
docs/
  API.md                   本地 HTTP 接口与 Notion 同步详尽文档
build.sh                   一键编译、打包、可选安装 App 与 CLI
```

## License

[MIT License](LICENSE) © 2026 Weiqi Wang
