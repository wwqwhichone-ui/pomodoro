# Pomodoro — AI 协作规范（Claude Code / Codex CLI / Antigravity 共用）

> `CLAUDE.md` 是本文件的软链接。开工前先读 `.ai/handoff.md`，收工前更新它。

## 项目简介
macOS 原生番茄钟。窗口拖到 Sidecar（iPad 随航）上会自动全屏并切换横屏布局，支持顶部菜单栏实时倒计时；自动探测 Notion 任务数据库结构并同步每日待办 / DDL / 优先级；本机开放 HTTP 接口 + `pomo` 命令行供 AI 调用。视觉参考 Neverless App（米白纸色、压缩粗体数字、细线描边、分段细环）。

## 技术栈
- Swift 5 语言模式 + SwiftUI（`Window` 场景，最低 macOS 14），`swiftc` 直接编译 `Sources/*.swift`（无 Xcode 工程 / SwiftPM / 第三方依赖），ad-hoc 签名
- 网络：Notion REST API（URLSession）；本地接口用 Network.framework `NWListener`（仅回环）
- 命令行：`tools/pomo`（Python 3 标准库）

## 目录结构
```
Sources/main.swift              App 入口、菜单命令
Sources/Model.swift             Phase / Key / TaskItem（含优先级、DDL、Notion 字段）/ DDL 描述 / TimerModel（计时、任务、统计、合并 Notion）
Sources/WindowManager.swift     屏幕识别（Sidecar）、自动全屏、发送到 iPad / 移回 Mac、迷你窗、全局快捷键
Sources/MenuBarController.swift macOS 顶部菜单栏实时倒计时与快捷控制菜单
Sources/NotionSync.swift        Notion URL/ID 提取、Schema 自动探测、拉取 / 解析 / 回写，配置 notion.json
Sources/APIServer.swift         本机 HTTP 接口（路由、序列化），配置 api.json
Sources/Theme.swift             Theme（纸色 / 深咖）、Typo 字体、PressStyle
Sources/Components.swift        进度环、阶段切换、按钮、任务列表 / 行（点击展开完整名称）、优先级标签、打断记录等组件
Sources/Layouts.swift           ContentView（选布局、主题）、横屏 / 竖屏 / 迷你三种布局、工具栏、设置（三个分页）
Sources/SettingsControls.swift 设置用控件：CapsuleTabs、SettingRow / SettingGroup、InkStepper、InkSwitch、InkField、InkButton、KeyChip（设置里不要再用系统 Stepper / Toggle / 分段控件）
tools/pomo                      命令行（可软链到 ~/.local/bin/pomo）
tools/make_icon.swift           生成图标
docs/API.md                     接口与 Notion 同步说明
.github/workflows/release.yml   打 v* 标签时自动构建 Universal .zip 并发布 Release
```

## 常用命令
```bash
./build.sh                                # 仅编译打包到 build/Pomodoro.app
./build.sh --universal --zip              # 构建 Apple Silicon + Intel 通用版并打 zip
./build.sh --install --install-cli        # 同时安装 App 到 /Applications 和 pomo 到 ~/.local/bin
open build/Pomodoro.app                   # 运行刚构建的应用
pkill -x Pomodoro                         # 结束运行中的实例（重新构建前）
pomo health / pomo status / pomo tasks    # 通过接口操作运行中的 App
defaults read local.pomodoro.app          # 查看设置、任务、今日统计
```
- 无自动化测试；验证 = 构建零警告 + `pomo` 走一遍接口 + 截图看三种布局（竖屏 440×640、横屏 iPad 1074×789、迷你 320×104）
- 改动用户数据前先 `defaults export local.pomodoro.app <备份>`，测完 `pkill` 后 `defaults import` 还原
- 数据：设置与任务在 UserDefaults（`local.pomodoro.app`）；令牌在 `~/Library/Application Support/Pomodoro/{api,notion}.json`（600）

## 代码规范
- 尺寸都乘以布局基准（竖屏 / 横屏的 `D` 与 `s`、迷你的 `k`），保证 iPad 全屏等比放大；新增元素同样处理
- 颜色只从 `@Environment(\.theme)` 取，不写死；点缀色用 `t.accent(phase)`，克制使用
- 设置键集中在 `enum Key`；`TaskItem` 新增字段必须是可选值（兼容旧数据解码）
- 倒计时以 `endDate` 为准（不累加 tick）；暂停状态下修改时长不能误重置进度
- 布局判定 `LayoutKind.of` 与 `WindowManager.isCompact` 阈值保持一致（高 < 190 或宽 < 240 = 迷你）

## 注意事项
- 计时中 `beginActivity(.idleDisplaySleepDisabled)` 阻止息屏，否则随航会断开
- 全局快捷键（空格 开始暂停 / `-` 内部打断 / `=` 外部打断）由 `KeyMonitor` 按物理键码拦截（中文输入法下也有效），第一响应者是文本框时放行；带 ⌘⌥⌃⇧ 修饰键或按住连发时不触发
- Notion 令牌和数据库 ID 只能由用户自己在设置里填写；回写 Notion 默认关闭
- 本地接口必须保持只监听回环 + 令牌校验
- `.ai/` 为本地交接目录，不提交到 Git
