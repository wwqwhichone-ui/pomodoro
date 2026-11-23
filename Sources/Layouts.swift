// 三种布局：横屏（iPad / 宽窗口：左侧栏 + 右主区，仿 Neverless Mac 版）、竖屏（Mac 默认窗口）、迷你悬浮条
import SwiftUI
import AppKit

enum LayoutKind: Equatable {
    case mini, portrait, landscape

    static func of(_ s: CGSize) -> LayoutKind {
        if s.height < 190 || s.width < 240 { return .mini }
        return s.width / max(s.height, 1) >= 1.12 ? .landscape : .portrait
    }
}

// MARK: - 主视图

struct ContentView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var wm: WindowManager
    @AppStorage(Key.appearance) private var appearance = "light"
    @Environment(\.colorScheme) private var scheme
    @State private var flash = false

    private var theme: Theme {
        switch appearance {
        case "light": return .paper
        case "dark": return .night
        default: return scheme == .dark ? .night : .paper
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let kind = LayoutKind.of(geo.size)
            let top: CGFloat = (wm.isFullScreen || kind == .mini) ? 0 : 28
            ZStack {
                Backdrop()
                    .contentShape(Rectangle())
                    .onTapGesture { wm.window?.makeFirstResponder(nil) }
                Group {
                    switch kind {
                    case .mini: MiniLayout(model: model, wm: wm, size: geo.size)
                    case .portrait: PortraitLayout(model: model, wm: wm, size: geo.size, top: top)
                    case .landscape: LandscapeLayout(model: model, wm: wm, size: geo.size, top: top)
                    }
                }
                .transition(.opacity)
                theme.accent(model.phase)
                    .opacity(flash ? 0.16 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.25), value: kind)
            .onChange(of: kind, initial: true) { _, k in wm.setCompactChrome(k == .mini) }
        }
        .ignoresSafeArea()
        .background(WindowAccessor { wm.attach($0) })
        .environment(\.theme, theme)
        .preferredColorScheme(preferredScheme)
        .onAppear {
            KeyMonitor.install(model)
            NotionSync.shared.start(model: model)
            APIServer.shared.start(model: model)
            MenuBarController.shared.start(model: model, wm: wm)
        }
        .onChange(of: model.finishToken) { flashScreen() }
    }

    private func flashScreen() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                withAnimation(.easeOut(duration: 0.2)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeIn(duration: 0.25)) { flash = false }
                }
            }
        }
    }
}

// MARK: - 横屏：左侧栏（今日成果 / 当前任务 / 待办）+ 右主区（阶段、进度环、控制）

struct LandscapeLayout: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var wm: WindowManager
    let size: CGSize
    let top: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        let s = min(max(size.height / 720, 0.85), 1.45)
        let sideW = min(max(size.width * 0.32, 270), 440)
        let mainW = size.width - sideW
        let pad = 22 * s
        let D = max(140, min(mainW * 0.66, (size.height - 60 * s - pad * 2) / 1.3))
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16 * s) {
                Color.clear.frame(height: top > 0 ? top : 4)
                TodaySummary(stats: model.stats, s: s)
                hairline
                SessionBlock(model: model, s: s)
                hairline
                TaskListView(model: model, s: s)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, pad)
            .padding(.bottom, pad * 0.8)
            .frame(width: sideW)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(t.panel.opacity(0.6))
            .overlay(alignment: .trailing) { Rectangle().fill(t.line).frame(width: 1) }

            VStack(spacing: 0) {
                HStack {
                    PhasePicker(current: model.phase, fontSize: 12.5 * s) { model.select($0) }
                    Spacer()
                    WindowToolbar(model: model, wm: wm, s: s)
                }
                .padding(.top, top > 0 ? 6 : pad * 0.7)
                Spacer(minLength: 0)
                RingView(model: model, D: D)
                Spacer(minLength: 0)
                VStack(spacing: 16 * s) {
                    ControlsView(model: model, D: D)
                    SetProgress(streak: model.streak, total: model.longEvery, s: s)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pad)
            .padding(.bottom, pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hairline: some View {
        Rectangle().fill(t.line).frame(height: 1)
    }
}

// MARK: - 竖屏

struct PortraitLayout: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var wm: WindowManager
    let size: CGSize
    let top: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        let avail = size.height - max(top, 34)
        let D = max(120, min(size.width * 0.74, avail * 0.47))
        let s = min(max(D / 270, 0.8), 1.6)
        VStack(spacing: 0) {
            HStack {
                Spacer()
                WindowToolbar(model: model, wm: wm, s: min(s, 1.15))
            }
            .padding(.top, top > 0 ? 4 : 14)
            .padding(.horizontal, 12)
            Spacer(minLength: 2)
            PhasePicker(current: model.phase, fontSize: 12.5 * s) { model.select($0) }
            Spacer(minLength: 4)
            CurrentTaskPill(model: model, fs: 12.5 * s)
            Spacer(minLength: 6)
            RingView(model: model, D: D)
            Spacer(minLength: 6)
            ControlsView(model: model, D: D)
            Spacer(minLength: 6)
            VStack(spacing: 10 * s) {
                SetProgress(streak: model.streak, total: model.longEvery, s: s)
                StatsLine(stats: model.stats, fs: 11.5 * s)
                if model.phase == .focus {
                    InterruptionBar(model: model, s: s * 0.92)
                }
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 迷你悬浮条
//  ┌────────────────────────────────────────┐
//  │ 专注 · 写周报                  (▶)  ⤢ │
//  │ 24:59  ↘ 01:10 结束                    │
//  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │  已过彩色 / 剩余墨色
//  └────────────────────────────────────────┘

struct MiniLayout: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var wm: WindowManager
    let size: CGSize
    @Environment(\.theme) private var t

    private var label: String {
        if model.phase == .focus, let task = model.currentTask { return "专注 · \(task.title)" }
        return model.phase.title
    }

    private var status: String {
        if model.isRunning { return "\(Fmt.hm.string(from: model.projectedEnd)) 结束" }
        return model.hasStarted ? "已暂停" : "未开始"
    }

    var body: some View {
        let k = min(max(min(size.height / 104, size.width / 320), 0.8), 1.8)
        let pad = 18 * k
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10 * k) {
                VStack(alignment: .leading, spacing: 1 * k) {
                    Text(label)
                        .font(Typo.text(11.5 * k, .medium))
                        .foregroundColor(t.gray)
                        .lineLimit(1)
                    HStack(alignment: .lastTextBaseline, spacing: 8 * k) {
                        Text(model.timeText)
                            .font(Typo.display(38 * k))
                            .monospacedDigit()
                            .foregroundColor(t.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy(duration: 0.3), value: model.timeText)
                        Text(status)
                            .font(Typo.text(11 * k, .medium))
                            .foregroundColor(model.isRunning ? t.accent(model.phase) : t.gray)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Button { model.toggle() } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13 * k, weight: .bold))
                        .foregroundColor(t.onInk)
                        .offset(x: model.isRunning ? 0 : 1 * k)
                        .frame(width: 38 * k, height: 38 * k)
                        .background(Circle().fill(t.ink))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .help("开始 / 暂停（空格）")
                ToolIcon(icon: "arrow.up.left.and.arrow.down.right", help: "展开", s: k * 0.95) { wm.setMini(false) }
            }
            Spacer(minLength: 6 * k)
            MiniProgressBar(progress: model.progress, accent: t.accent(model.phase), k: k)
        }
        .padding(.horizontal, pad)
        .padding(.top, 12 * k)
        .padding(.bottom, 14 * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 细进度条：已过（彩色）+ 剩余（墨色），中间留一道缝
struct MiniProgressBar: View {
    let progress: Double
    let accent: Color
    let k: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let gap: CGFloat = progress > 0.004 && progress < 0.996 ? 3 * k : 0
            let done = max(0, w * progress - gap / 2)
            HStack(spacing: gap) {
                if done > 0 { Rectangle().fill(accent).frame(width: done) }
                Rectangle().fill(t.ink)
            }
        }
        .frame(height: 2.5 * k)
        .animation(.linear(duration: 0.2), value: progress)
    }
}

// MARK: - 工具栏

struct WindowToolbar: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var wm: WindowManager
    let s: CGFloat
    @AppStorage(Key.onTop) private var onTop = false
    @State private var showSettings = false
    @State private var hover = false
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 6 * s) {
            if wm.isOnIPad {
                ToolIcon(icon: "laptopcomputer", help: "移回 Mac（⌥⌘M）", s: s) { wm.sendToMac() }
            } else if wm.sidecarAvailable {
                ToolIcon(icon: "ipad.landscape", help: "发送到 iPad 并全屏（⌥⌘I）", s: s) { wm.sendToIPad() }
            }
            if !wm.isFullScreen {
                ToolIcon(icon: "pip.enter", help: "迷你悬浮窗（⌥⌘P）", s: s) { wm.setMini(true) }
                ToolIcon(icon: onTop ? "pin.fill" : "pin", help: onTop ? "取消置顶" : "窗口置顶", s: s) { onTop.toggle() }
            }
            ToolIcon(icon: wm.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                     help: "全屏 / 退出全屏（⌃⌘F）", s: s) { wm.toggleFullScreen() }
            ToolIcon(icon: "slider.horizontal.3", help: "设置", s: s) { showSettings.toggle() }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView(onChange: { model.settingsChanged() }, onResetToday: { model.resetToday() })
                        .environment(\.theme, t)
                        .presentationBackground(t.bg)
                }
        }
        .opacity(model.isRunning && !hover && !showSettings ? 0.35 : 1)
        .animation(.easeInOut(duration: 0.3), value: hover)
        .onHover { hover = $0 }
        .onChange(of: onTop) { wm.applyOnTop() }
    }
}

// MARK: - 设置（三个分页：计时 / 同步与接口 / 方法）

struct SettingsView: View {
    var onChange: () -> Void
    var onResetToday: (() -> Void)? = nil
    var initialTab = 0
    @State private var tab: Int?
    @Environment(\.theme) private var t

    var body: some View {
        let current = Binding(get: { tab ?? initialTab }, set: { tab = $0 })
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(Typo.text(24, .bold))
                .foregroundColor(t.ink)
                .padding(.bottom, 12)
            CapsuleTabs(items: [(0, "计时"), (1, "同步与接口"), (2, "方法")], selection: current)
                .padding(.leading, -12)
            switch current.wrappedValue {
            case 0: TimerSettings(onChange: onChange, onResetToday: onResetToday)
            case 1: SyncSettings()
            default: MethodNotes()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: 360, alignment: .leading)
        .background(t.bg)
    }
}

private struct TimerSettings: View {
    var onChange: () -> Void
    var onResetToday: (() -> Void)? = nil
    @AppStorage(Key.focusMin) private var focus = 25
    @AppStorage(Key.shortMin) private var short = 5
    @AppStorage(Key.longMin) private var long = 15
    @AppStorage(Key.longEvery) private var every = 4
    @AppStorage(Key.autoStart) private var autoStart = false
    @AppStorage(Key.sound) private var sound = true
    @AppStorage(Key.autoFullScreen) private var autoFull = true
    @AppStorage(Key.menuBar) private var showMenuBar = true
    @AppStorage(Key.appearance) private var appearance = "light"
    @State private var confirmResetToday = false
    @Environment(\.theme) private var t

    private var isClassic: Bool { focus == 25 && short == 5 && long == 15 && every == 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingGroup(title: "外观") {
                CapsuleTabs(items: [("light", "纸色"), ("dark", "深咖"), ("system", "跟随系统")],
                            selection: $appearance)
                    .padding(.leading, -12)
            }
            SettingGroup(title: "时长") {
                SettingRow(title: "专注") { InkStepper(value: $focus, range: 1...120) }
                SettingRow(title: "短休息") { InkStepper(value: $short, range: 1...60) }
                SettingRow(title: "长休息") { InkStepper(value: $long, range: 1...60) }
                SettingRow(title: "长休息间隔", detail: "完成几个番茄后长休息一次", divider: false) {
                    InkStepper(value: $every, range: 2...10, unit: "个")
                }
                if !isClassic {
                    Button { focus = 25; short = 5; long = 15; every = 4 } label: {
                        Label("恢复经典 25 / 5 / 15 · 每 4 个", systemImage: "arrow.uturn.backward")
                            .labelStyle(TightLabelStyle(spacing: 4))
                    }
                    .buttonStyle(.plain)
                    .font(Typo.text(12, .medium))
                    .foregroundColor(t.accent(.focus))
                    .padding(.top, 6)
                }
            }
            SettingGroup(title: "行为") {
                SettingRow(title: "自动开始下一段", detail: "专注结束直接进入休息，休息结束直接开始专注") {
                    InkSwitch(isOn: $autoStart)
                }
                SettingRow(title: "结束提示音", detail: "每段结束时响三声") { InkSwitch(isOn: $sound) }
                SettingRow(title: "菜单栏显示倒计时", detail: "在顶部状态栏实时显示剩余时间并快捷控制") {
                    InkSwitch(isOn: $showMenuBar)
                }
                SettingRow(title: "拖到 iPad 自动全屏", detail: "窗口移到随航屏幕时自动进入全屏", divider: false) {
                    InkSwitch(isOn: $autoFull)
                }
            }
            if let onResetToday {
                SettingGroup(title: "数据") {
                    SettingRow(title: "今日成果", detail: "清零今日番茄数、专注时长、打断与作废", divider: false) {
                        if confirmResetToday {
                            HStack(spacing: 6) {
                                InkButton(title: "取消", filled: false) { confirmResetToday = false }
                                InkButton(title: "确认清零") {
                                    onResetToday()
                                    confirmResetToday = false
                                }
                            }
                        } else {
                            InkButton(title: "清零", filled: false) { confirmResetToday = true }
                        }
                    }
                }
            }
        }
        .onChange(of: focus) { onChange() }
        .onChange(of: short) { onChange() }
        .onChange(of: long) { onChange() }
        .onChange(of: every) { onChange() }
        .onChange(of: showMenuBar) { MenuBarController.shared.setEnabled(showMenuBar) }
    }
}

private struct SyncSettings: View {
    @ObservedObject private var sync = NotionSync.shared
    @ObservedObject private var api = APIServer.shared
    @State private var syncTab = 0
    @State private var token = ""
    @State private var target = ""
    @State private var excludedText = ""
    @State private var logTarget = ""
    @State private var editingLogToken = false
    @State private var copied = false
    @Environment(\.theme) private var t

    private var dbLabel: String { sync.databaseTitle ?? "Notion 数据库" }
    private var logDbLabel: String { sync.logDatabaseTitle ?? "Notion 每日记录" }
    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTarget: String { target.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedLogTarget: String { logTarget.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var notionStatus: (String, Color, String) {
        if !sync.config.isConfigured { return ("未连接", t.faint, "填写 integration 令牌和数据库链接或 ID") }
        if sync.syncing { return ("同步中…", t.warning, "正在拉取 \(dbLabel)") }
        if let e = sync.lastError { return ("同步失败", t.accent(.focus), e) }
        if let d = sync.lastSync { return ("已连接 · \(dbLabel)", t.positive, "上次同步 \(Fmt.hm.string(from: d)) · \(sync.lastCount) 条任务") }
        return ("已连接 · \(dbLabel)", t.positive, "等待首次同步")
    }

    private var logStatus: (String, Color, String) {
        if !sync.config.isLogConfigured { return ("未配置", t.faint, "填写每日记录数据库（如 Pomodoro Log）链接或 ID") }
        if sync.logSyncing { return ("同步中…", t.warning, "正在写入 \(logDbLabel)") }
        if let e = sync.lastLogError { return ("同步失败", t.accent(.focus), e) }
        if let d = sync.lastLogSync { return ("已连接 · \(logDbLabel)", t.positive, "上次同步 \(Fmt.hm.string(from: d))") }
        return ("已连接 · \(logDbLabel)", t.positive, "等待同步")
    }

    private var dirty: Bool {
        trimmedToken != sync.config.trimmedToken
            || trimmedTarget != sync.config.targetInput
            || NotionConfig.parseCategories(excludedText) != sync.config.excludedCategories
    }

    private var logDirty: Bool {
        trimmedToken != sync.config.trimmedToken || trimmedLogTarget != sync.config.logTargetInput
    }

    var body: some View {
        let s = notionStatus
        let ls = logStatus
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(t.line).frame(height: 1).padding(.top, 10)
            CapsuleTabs(items: [(0, "任务同步"), (1, "每日记录"), (2, "AI 接口")],
                        selection: $syncTab, fontSize: 11.5)
                .padding(.leading, -10)
                .padding(.top, 10)

            switch syncTab {
            case 0:
                SettingGroup(title: "Notion 任务同步") {
                    StatusDot(text: s.0, color: s.1, detail: s.2)
                        .padding(.vertical, 8)
                    Text("范围：今天计划、\(sync.config.lookaheadDays) 天内到期、已逾期、置顶的未完成任务；启动时和每 30 分钟同步。")
                        .font(Typo.text(11))
                        .foregroundColor(t.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    InkField(label: "Integration 令牌", placeholder: "ntn_… 或 secret_…", text: $token, secure: true)
                    InkField(label: "任务数据库链接或 ID", placeholder: "粘贴任务数据库链接或 ID", text: $target, mono: true)
                    InkField(label: "排除分类（逗号分隔）", placeholder: "如 Event, 活动, 会议", text: $excludedText)
                    SettingRow(title: "DDL 提前天数", detail: "拉取未来几天内到期的任务") {
                        InkStepper(value: Binding(get: { sync.config.lookaheadDays },
                                                  set: { v in sync.update { $0.lookaheadDays = v } }),
                                   range: 1...30, unit: "天")
                    }
                    SettingRow(title: "完成时回写 Notion", detail: "在番茄钟里勾选完成时同步更新 Notion 状态", divider: false) {
                        InkSwitch(isOn: Binding(get: { sync.config.writeBack },
                                                set: { v in sync.update { $0.writeBack = v } }))
                    }
                    HStack(spacing: 8) {
                        InkButton(title: dirty ? "保存并同步" : "立即同步", icon: "arrow.triangle.2.circlepath") {
                            sync.update {
                                $0.token = trimmedToken
                                if trimmedTarget != $0.targetInput {
                                    let extracted = NotionSync.extractID(from: trimmedTarget)
                                    $0.dataSourceID = extracted
                                    $0.databaseID = extracted
                                }
                                $0.excludedCategories = NotionConfig.parseCategories(excludedText)
                            }
                            target = sync.config.targetInput
                            excludedText = sync.config.excludedCategoriesText
                            if sync.config.isConfigured { sync.sync() }
                        }
                        .disabled(trimmedToken.isEmpty || trimmedTarget.isEmpty || sync.syncing)
                    }
                    .padding(.top, 8)
                }
            case 1:
                SettingGroup(title: "每日记录同步") {
                    StatusDot(text: ls.0, color: ls.1, detail: ls.2)
                        .padding(.vertical, 8)
                    Text("跨天或次日打开自动归档昨天统计，完成番茄时实时更新当天记录；按日期去重。")
                        .font(Typo.text(11))
                        .foregroundColor(t.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    if trimmedToken.isEmpty || editingLogToken {
                        InkField(label: "Integration 令牌", placeholder: "ntn_… 或 secret_…", text: $token, secure: true)
                    } else {
                        HStack {
                            Text("已共用 Notion Integration 令牌")
                                .font(Typo.text(11))
                                .foregroundColor(t.gray)
                            Spacer()
                            Button("更换令牌") { editingLogToken = true }
                                .buttonStyle(.plain)
                                .font(Typo.text(11, .medium))
                                .foregroundColor(t.ink)
                        }
                        .padding(.vertical, 6)
                    }
                    InkField(label: "每日记录数据库链接或 ID", placeholder: "粘贴 Pomodoro Log 链接或 ID（留空关闭）", text: $logTarget, mono: true)
                    HStack(spacing: 8) {
                        InkButton(title: logDirty ? "保存记录库" : "立即同步今日", icon: "calendar.badge.clock") {
                            sync.update {
                                $0.token = trimmedToken
                                if trimmedLogTarget != $0.logTargetInput {
                                    let extracted = NotionSync.extractID(from: trimmedLogTarget)
                                    $0.logDataSourceID = extracted
                                    $0.logDatabaseID = extracted
                                }
                            }
                            logTarget = sync.config.logTargetInput
                            editingLogToken = false
                            if sync.config.isLogConfigured { sync.syncDailyLogNow(includeToday: true) }
                        }
                        .disabled(sync.logSyncing || (trimmedToken.isEmpty && !trimmedLogTarget.isEmpty) || (!logDirty && !sync.config.isLogConfigured))
                    }
                    .padding(.top, 8)
                }
            default:
                SettingGroup(title: "AI 接口") {
                    StatusDot(text: api.running ? "已开启" : "未启动",
                              color: api.running ? t.positive : t.accent(.focus),
                              detail: api.running ? "只在本机 127.0.0.1:\(api.config.port) 监听，需令牌访问" : api.lastError)
                        .padding(.vertical, 8)
                    HStack(spacing: 6) {
                        KeyChip(text: "pomo status", mono: true)
                        KeyChip(text: "pomo tasks", mono: true)
                        KeyChip(text: "pomo log-today", mono: true)
                    }
                    .padding(.vertical, 4)
                    Text("AI 用命令行 pomo 即可调用，说明见 docs/API.md")
                        .font(Typo.text(11))
                        .foregroundColor(t.gray)
                        .padding(.vertical, 4)
                    InkButton(title: copied ? "已复制" : "复制接口令牌", icon: copied ? "checkmark" : "doc.on.doc", filled: false) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(api.config.token, forType: .string)
                        copied = true
                    }
                    .padding(.top, 6)
                }
            }
        }
        .onAppear {
            token = sync.config.token
            target = sync.config.targetInput
            excludedText = sync.config.excludedCategoriesText
            logTarget = sync.config.logTargetInput
            editingLogToken = false
        }
    }
}

private struct MethodNotes: View {
    @Environment(\.theme) private var t

    private let steps: [(String, String)] = [
        ("列出今日待办", "预估每件要几个番茄"),
        ("选一件，专注 25 分钟", "中途不切换任务"),
        ("被打断就记一笔", "按 - 记内部打断 · 按 = 记外部打断，尽量推迟处理"),
        ("休息 5 分钟", "彻底离开工作，不看消息"),
        ("每 4 个番茄长休息", "15–30 分钟，回顾这一组"),
    ]
    private let keys: [(String, String)] = [
        ("空格", "开始 / 暂停"), ("⌘R", "重置"), ("⇧⌘S", "跳过"), ("-", "内部打断"),
        ("=", "外部打断"), ("⌥⌘I", "发送到 iPad"), ("⌥⌘M", "移回 Mac"), ("⌥⌘P", "迷你窗"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingGroup(title: "番茄工作法") {
                ForEach(steps.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(Typo.display(14))
                            .foregroundColor(t.ink)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(t.ink.opacity(0.8), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(steps[i].0).font(Typo.text(13, .medium)).foregroundColor(t.ink)
                            Text(steps[i].1).font(Typo.text(11)).foregroundColor(t.gray)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            SettingGroup(title: "快速添加") {
                Text("写周报 ×2 P1 @11-25")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(t.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.panel))
                    .padding(.vertical, 4)
                HStack(spacing: 14) {
                    legend("×2", "预估番茄")
                    legend("P0–P3", "优先级")
                    legend("@明天", "DDL")
                }
                .padding(.top, 4)
            }
            SettingGroup(title: "快捷键") {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(keys.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            KeyChip(text: keys[i].0)
                            Text(keys[i].1).font(Typo.text(12)).foregroundColor(t.gray)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func legend(_ token: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            KeyChip(text: token, mono: true)
            Text(text).font(Typo.text(11.5)).foregroundColor(t.gray)
        }
    }
}
