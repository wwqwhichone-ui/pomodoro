// 可复用的界面组件
import SwiftUI
import AppKit

// MARK: - 背景：纸色 + 极淡纸纹

struct Backdrop: View {
    @Environment(\.theme) private var t

    var body: some View {
        ZStack {
            t.bg
            PaperGrain(dark: t.isDark)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 固定种子的随机细点，营造纸张质感（只在尺寸变化时重绘）
struct PaperGrain: View {
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            let n = Int(size.width * size.height / 140)
            let color = dark ? Color.white : Color(hex: 0x5A4A30)
            for _ in 0..<n {
                let r = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: 1, height: 1)
                ctx.fill(Path(r), with: .color(color.opacity(0.025 + rnd() * 0.04)))
            }
        }
        .drawingGroup()
    }
}

// MARK: - 小部件

/// 灰色小标题（如「当前任务」「今日待办」）
struct SectionLabel: View {
    let text: String
    let s: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        Text(text)
            .font(Typo.text(12.5 * s, .medium))
            .foregroundColor(t.gray)
    }
}

/// 细线描边的圆形图标按钮
struct OutlineIconButton: View {
    let icon: String
    let size: CGFloat
    let help: String
    var weight: Font.Weight = .regular
    let action: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: weight))
                .foregroundColor(t.ink)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(t.ink.opacity(0.85), lineWidth: max(1, size * 0.028)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}

/// 顶部工具栏用的小图标
struct ToolIcon: View {
    let icon: String
    let help: String
    let s: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5 * s, weight: .regular))
                .foregroundColor(t.ink)
                .frame(width: 28 * s, height: 28 * s)
                .overlay(Circle().strokeBorder(t.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}

// MARK: - 进度环：已过（彩色）+ 剩余（墨色）分段细环

struct RingView: View {
    @ObservedObject var model: TimerModel
    let D: CGFloat
    @Environment(\.theme) private var t

    private var label: String {
        switch model.phase {
        case .focus: return "专注 · 第 \(model.stats.completed + 1) 个番茄"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }

    private var status: (icon: String, text: String) {
        if model.isRunning { return ("arrow.down.right", "预计 \(Fmt.hm.string(from: model.projectedEnd)) 结束") }
        if model.hasStarted { return ("pause", "已暂停") }
        return ("arrow.right", model.phase == .focus ? "准备专注" : "准备休息")
    }

    private var caption: String {
        if model.phase == .focus { return model.currentTask?.title ?? "一次只做一件事" }
        return model.breakTip
    }

    var body: some View {
        let p = model.progress
        let accent = t.accent(model.phase)
        let line = max(2.5, D * 0.012)
        let gap = p > 0.004 && p < 0.996 ? 0.007 : 0
        ZStack {
            // 剩余（墨色）
            Circle()
                .trim(from: min(1, p + gap / 2), to: 1 - gap / 2)
                .stroke(t.ink, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            // 已过（彩色）
            if p > gap {
                Circle()
                    .trim(from: gap / 2, to: p - gap / 2)
                    .stroke(accent, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            // 内圈发丝线
            Circle()
                .strokeBorder(t.line, lineWidth: 1)
                .frame(width: D * 0.74, height: D * 0.74)
            MinuteMarks(totalMinutes: Int(model.total / 60), progress: p, D: D)
            VStack(spacing: D * 0.012) {
                Text(label)
                    .font(Typo.text(D * 0.043, .medium))
                    .foregroundColor(t.gray)
                Text(model.timeText)
                    .font(Typo.display(D * 0.27))
                    .monospacedDigit()
                    .foregroundColor(t.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.3), value: model.timeText)
                HStack(spacing: D * 0.012) {
                    Image(systemName: status.icon)
                        .font(.system(size: D * 0.034, weight: .semibold))
                    Text(status.text)
                }
                .font(Typo.text(D * 0.043, .medium))
                .foregroundColor(model.isRunning ? accent : t.gray)
                Text(caption)
                    .font(Typo.serif(D * 0.05))
                    .foregroundColor(t.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: D * 0.56)
                    .padding(.top, D * 0.035)
            }
        }
        .frame(width: D, height: D)
        .animation(.linear(duration: 0.2), value: p)
    }
}

/// 环内的分钟刻度数字（像 Neverless 环形图里的标注）
struct MinuteMarks: View {
    let totalMinutes: Int
    let progress: Double
    let D: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        let step = totalMinutes <= 30 ? 5 : (totalMinutes <= 60 ? 10 : 15)
        let marks = stride(from: 0, to: max(totalMinutes, 1), by: step).map { $0 }
        let r = D * 0.43
        ZStack {
            ForEach(marks, id: \.self) { m in
                let f = Double(m) / Double(max(totalMinutes, 1))
                let a = f * 2 * .pi - .pi / 2
                Text("\(m)")
                    .font(Typo.text(D * 0.03, .medium))
                    .monospacedDigit()
                    .foregroundColor(f <= progress && progress > 0 ? t.ink : t.faint)
                    .position(x: D / 2 + cos(a) * r, y: D / 2 + sin(a) * r)
            }
        }
        .frame(width: D, height: D)
    }
}

// MARK: - 阶段切换（未选中为灰字，选中套细描边胶囊）

struct PhasePicker: View {
    let current: Phase
    let fontSize: CGFloat
    let onSelect: (Phase) -> Void

    var body: some View {
        CapsuleTabs(items: Phase.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { current }, set: { onSelect($0) }),
                    fontSize: fontSize)
    }
}

// MARK: - 控制按钮

/// 墨色实心胶囊主按钮
struct PrimaryButton: View {
    @ObservedObject var model: TimerModel
    let h: CGFloat
    @Environment(\.theme) private var t

    private var title: String {
        if model.isRunning { return "暂停" }
        if model.hasStarted { return "继续" }
        return model.phase == .focus ? "开始专注" : "开始休息"
    }

    var body: some View {
        Button { model.toggle() } label: {
            HStack(spacing: h * 0.18) {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: h * 0.3, weight: .bold))
                Text(title)
                    .font(Typo.text(h * 0.33, .semibold))
            }
            .foregroundColor(t.onInk)
            .padding(.horizontal, h * 0.62)
            .frame(minWidth: h * 2.9)
            .frame(height: h)
            .background(Capsule().fill(t.ink))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help("开始 / 暂停（空格）")
    }
}

struct ControlsView: View {
    @ObservedObject var model: TimerModel
    let D: CGFloat

    var body: some View {
        let h = D * 0.15
        HStack(spacing: D * 0.05) {
            OutlineIconButton(icon: "arrow.counterclockwise", size: h, help: "重置（⌘R）") { model.reset() }
            PrimaryButton(model: model, h: h)
            OutlineIconButton(icon: "forward.end", size: h,
                              help: model.phase == .focus ? "放弃这个番茄（中途放弃记为作废）" : "结束休息") { model.skip() }
        }
    }
}

// MARK: - 本组进度（4 个番茄一组）

struct SetProgress: View {
    let streak: Int
    let total: Int
    let s: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 5 * s) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < streak ? t.ink : t.ink.opacity(0.14))
                    .frame(width: 18 * s, height: 3 * s)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: streak)
        .help("每 \(total) 个番茄后长休息")
    }
}

// MARK: - 番茄计量（实心 = 已完成，空心 = 预估未完成，黄色 = 超出预估）

struct TomatoMeter: View {
    let done: Int
    let estimate: Int
    let size: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        let n = min(max(done, estimate), 12)
        HStack(spacing: size * 0.45) {
            ForEach(0..<n, id: \.self) { i in
                if i < done {
                    Circle()
                        .fill(i < estimate ? t.accent(.focus) : t.warning)
                        .frame(width: size, height: size)
                } else {
                    Circle()
                        .strokeBorder(t.ink.opacity(0.4), lineWidth: max(1, size * 0.14))
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

// MARK: - 今日统计

/// 竖屏用的一行统计
struct StatsLine: View {
    let stats: DayStats
    let fs: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        var parts = ["今日 \(stats.completed) 个番茄"]
        if stats.focusSeconds > 0 { parts.append("专注 \(Fmt.duration(stats.focusSeconds))") }
        if stats.interruptions > 0 { parts.append("打断 \(stats.interruptions)") }
        if stats.voided > 0 { parts.append("作废 \(stats.voided)") }
        return Text(parts.joined(separator: " · "))
            .font(Typo.text(fs, .medium))
            .foregroundColor(t.gray)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 侧栏顶部：像「投资组合 $37,550.63 ↑8.29%」那样展示今日成果
struct TodaySummary: View {
    let stats: DayStats
    let s: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            SectionLabel(text: "今日成果", s: s)
            HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
                Text("\(stats.completed)")
                    .font(Typo.display(40 * s))
                    .foregroundColor(t.ink)
                    .contentTransition(.numericText())
                Text("个番茄")
                    .font(Typo.text(14 * s, .semibold))
                    .foregroundColor(t.ink)
            }
            HStack(spacing: 10 * s) {
                Label(stats.focusSeconds > 0 ? "专注 \(Fmt.duration(stats.focusSeconds))" : "还没开始",
                      systemImage: "arrow.up.right")
                    .foregroundColor(stats.focusSeconds > 0 ? t.positive : t.gray)
                if stats.interruptions > 0 {
                    Text("打断 \(stats.interruptions)").foregroundColor(t.gray)
                }
                if stats.voided > 0 {
                    Text("作废 \(stats.voided)").foregroundColor(t.gray)
                }
            }
            .font(Typo.text(12 * s, .medium))
            .labelStyle(TightLabelStyle(spacing: 3 * s))
        }
    }
}

struct TightLabelStyle: LabelStyle {
    let spacing: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - 打断记录（番茄工作法：- 键记内部打断，= 键记外部打断）

struct InterruptionBar: View {
    @ObservedObject var model: TimerModel
    let s: CGFloat

    var body: some View {
        HStack(spacing: 8 * s) {
            InterruptionChip(mark: "-", label: "内部打断", count: model.sessionInternal, s: s,
                             help: "自己想去做别的事：把念头记下来，继续专注（快捷键 -）",
                             onLog: { model.logInterruption(internal: true) },
                             onUndo: { model.undoInterruption(internal: true) })
            InterruptionChip(mark: "=", label: "外部打断", count: model.sessionExternal, s: s,
                             help: "别人或消息打断：告知、协商、稍后再回（快捷键 =）",
                             onLog: { model.logInterruption(internal: false) },
                             onUndo: { model.undoInterruption(internal: false) })
        }
    }
}

/// 一个打断胶囊：点左边记一次；有次数时右边的数字单独可点，点一下减 1（误触补救）
struct InterruptionChip: View {
    let mark: String
    let label: String
    let count: Int
    let s: CGFloat
    let help: String
    let onLog: () -> Void
    let onUndo: () -> Void
    @State private var hoverBadge = false
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onLog) {
                HStack(spacing: 6 * s) {
                    Text(mark)
                        .font(.system(size: 13 * s, weight: .bold, design: .monospaced))
                    Text(label)
                }
                .lineLimit(1)
                .fixedSize()
                .font(Typo.text(12.5 * s, .medium))
                .foregroundColor(t.ink)
                .padding(.leading, 13 * s)
                .padding(.trailing, count > 0 ? 6 * s : 13 * s)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help(help)

            if count > 0 {
                Button(action: onUndo) {
                    Text(hoverBadge ? "−1" : "\(count)")
                        .font(Typo.display(14 * s))
                        .foregroundColor(t.accent(.focus))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 16 * s)
                        .padding(.horizontal, 6 * s)
                        .padding(.vertical, 2 * s)
                        .background(Capsule().fill(t.accent(.focus).opacity(hoverBadge ? 0.18 : 0.1)))
                        .padding(.trailing, 5 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .onHover { hoverBadge = $0 }
                .help("误按了？点这个数字减 1")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: 30 * s)
        .overlay(Capsule().strokeBorder(t.ink.opacity(0.85), lineWidth: 1))
        .animation(.snappy, value: count)
        .animation(.easeOut(duration: 0.12), value: hoverBadge)
    }
}

// MARK: - 今日待办（像 Neverless 的观察列表）

struct TaskListView: View {
    @ObservedObject var model: TimerModel
    let s: CGFloat
    @State private var draft = ""
    @FocusState private var adding: Bool
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(spacing: 8 * s) {
                SectionLabel(text: "今日待办", s: s)
                Spacer()
                NotionSyncButton(s: s)
                if model.tasks.contains(where: \.finished) {
                    Button("清除已完成") { model.clearFinished() }
                        .buttonStyle(.plain)
                        .font(Typo.text(11.5 * s, .medium))
                        .foregroundColor(t.gray)
                }
            }
            ScrollView {
                LazyVStack(spacing: 2 * s) {
                    ForEach(Array(model.sortedTasks.enumerated()), id: \.element.id) { i, task in
                        TaskRow(task: task, index: i + 1, isCurrent: task.id == model.currentTaskID, s: s,
                                onSelect: { model.selectTask(task.id) },
                                onToggle: { model.toggleFinished(task.id) },
                                onDelete: { model.removeTask(task.id) },
                                onEstimate: { model.adjustEstimate(task.id, by: $0) })
                    }
                    if model.tasks.isEmpty {
                        Text("先列出今天要做的事，\n再预估每件要几个番茄。")
                            .help("末尾可写 ×2（预估番茄数）、P0–P3（优先级）、@11-25 或 @明天（DDL）")
                            .font(Typo.serif(14 * s))
                            .foregroundColor(t.gray)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4 * s)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24 * s)
                    }
                }
                .animation(.snappy, value: model.tasks)
            }
            .scrollIndicators(.never)
            HStack(spacing: 10 * s) {
                Image(systemName: "plus")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundColor(t.ink)
                    .frame(width: 30 * s, height: 30 * s)
                    .overlay(Circle().strokeBorder(t.line, lineWidth: 1))
                TextField("添加任务，如「写周报 ×2 P1 @11-25」", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Typo.text(13 * s))
                    .foregroundColor(t.ink)
                    .focused($adding)
                    .onSubmit {
                        model.addTask(draft)
                        draft = ""
                    }
                    .onExitCommand { adding = false }
            }
            .padding(.horizontal, 6 * s)
            .padding(.vertical, 6 * s)
            .overlay(alignment: .bottom) {
                Rectangle().fill(adding ? t.ink.opacity(0.5) : t.line).frame(height: 1)
            }
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    let index: Int
    let isCurrent: Bool
    let s: CGFloat
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onEstimate: (Int) -> Void
    @AppStorage(Key.focusMin) private var focusMin = 25
    @State private var hover = false
    @State private var expandedFinished = false
    @Environment(\.theme) private var t

    private var showFullTitle: Bool { (isCurrent && !task.finished) || (task.finished && expandedFinished) }

    private var statusText: (String, Color) {
        if task.finished { return ("已完成", t.positive) }
        if task.done > task.estimate { return ("超出 \(task.done - task.estimate)", t.warning) }
        if isCurrent { return ("进行中", t.accent(.focus)) }
        return ("待开始", t.gray)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
        HStack(alignment: .top, spacing: 12 * s) {
            Button(action: onToggle) {
                ZStack {
                    Circle().strokeBorder(task.finished ? t.positive : t.ink.opacity(0.85), lineWidth: 1.2)
                    if task.finished {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13 * s, weight: .semibold))
                            .foregroundColor(t.positive)
                    } else {
                        Text("\(index)")
                            .font(Typo.display(16 * s))
                            .foregroundColor(t.ink)
                    }
                }
                .frame(width: 34 * s, height: 34 * s)
                .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .help(task.finished ? "标记为未完成" : "标记为已完成")

            VStack(alignment: .leading, spacing: 3 * s) {
                HStack(alignment: .firstTextBaseline, spacing: 5 * s) {
                    if task.isTop3 {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9 * s))
                            .foregroundColor(t.accent(.focus))
                            .help("Notion Top 3")
                    }
                    Text(task.title)
                        .font(Typo.text(14 * s, .semibold))
                        .strikethrough(task.finished, color: t.gray)
                        .foregroundColor(task.finished ? t.gray : t.ink)
                        .lineLimit(showFullTitle ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 右侧已显示「完成/预估」，副标题只在没有其他信息时才写预估，避免被截断成「…」
                TaskMetaLine(task: task, s: s,
                             showEstimate: task.priority == nil && task.due == nil && task.tag == nil)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2 * s) {
                Text("\(task.done)/\(task.estimate)")
                    .font(Typo.display(17 * s))
                    .foregroundColor(task.finished ? t.gray : t.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: task.estimate)
                    .help("已完成 \(task.done) 个 / 预估 \(task.estimate) 个番茄")
                Text(statusText.0)
                    .font(Typo.text(11 * s, .medium))
                    .foregroundColor(statusText.1)
            }
        }
            // 当前任务展开操作栏（不依赖悬停，iPad 上用 Pencil 点也能用）
            if isCurrent && !task.finished {
                actionBar
                    .padding(.leading, 46 * s)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 7 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
            .fill(t.ink.opacity(isCurrent && !task.finished ? 0.06 : (hover ? 0.035 : 0))))
        .contentShape(Rectangle())
        .onTapGesture {
            if task.finished {
                expandedFinished.toggle()
            } else {
                onSelect()
            }
        }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.snappy(duration: 0.25), value: isCurrent)
        .animation(.snappy(duration: 0.25), value: expandedFinished)
        .help(task.finished ? (expandedFinished ? "点击收起完整名称" : "点击查看完整名称") : (isCurrent ? "当前任务" : "点击设为当前任务，可查看完整名称与调整预估"))
    }

    /// 预估 − 4 +   ·   Notion ↗（本地任务为「删除」）
    private var actionBar: some View {
        HStack(spacing: 10 * s) {
            HStack(spacing: 5 * s) {
                Text("预估")
                    .font(Typo.text(11 * s, .medium))
                    .foregroundColor(t.gray)
                smallButton("minus", help: "预估少 1 个番茄") { onEstimate(-1) }
                    .disabled(task.estimate <= 1)
                    .opacity(task.estimate <= 1 ? 0.3 : 1)
                Text("\(task.estimate)")
                    .font(Typo.display(15 * s))
                    .foregroundColor(t.ink)
                    .frame(minWidth: 12 * s)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: task.estimate)
                smallButton("plus", help: "预估多 1 个番茄") { onEstimate(1) }
            }
            .help("预估这件事要几个番茄（当前每个 \(focusMin) 分钟）")
            if let url = task.notionURL.flatMap(URL.init(string:)) {
                chip("Notion ↗", help: "在浏览器里打开这条任务的 Notion 页面") { NSWorkspace.shared.open(url) }
            } else {
                chip("删除", help: "删除这个任务") { onDelete() }
            }
        }
    }

    private func chip(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.text(11 * s, .semibold))
                .foregroundColor(t.ink)
                .padding(.horizontal, 9 * s)
                .frame(height: 22 * s)
                .overlay(Capsule().strokeBorder(t.ink.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help(help)
    }

    private func smallButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundColor(t.ink)
                .frame(width: 22 * s, height: 22 * s)
                .overlay(Circle().strokeBorder(t.ink.opacity(0.3), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(help)
    }
}

/// 侧栏中部：当前任务 + 打断记录 / 休息建议
struct SessionBlock: View {
    @ObservedObject var model: TimerModel
    let s: CGFloat
    @State private var expandTitle = false
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            if model.phase == .focus {
                SectionLabel(text: "当前任务", s: s)
                Text(model.currentTask?.title ?? "还没有选择任务")
                    .font(Typo.text(19 * s, .semibold))
                    .foregroundColor(model.currentTask == nil ? t.gray : t.ink)
                    .lineLimit(expandTitle ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { if model.currentTask != nil { expandTitle.toggle() } }
                    .help(model.currentTask == nil ? "" : (expandTitle ? "点击收起" : "点击展开完整任务名"))
                    .animation(.snappy(duration: 0.2), value: expandTitle)
                if let task = model.currentTask {
                    HStack(spacing: 8 * s) {
                        TomatoMeter(done: task.done, estimate: task.estimate, size: 8 * s)
                        Text("\(task.done) / \(task.estimate) 个番茄")
                            .font(Typo.text(11.5 * s, .medium))
                            .foregroundColor(t.gray)
                    }
                    if task.priority != nil || task.due != nil {
                        TaskMetaLine(task: task, s: s, showEstimate: false)
                    }
                }
                InterruptionBar(model: model, s: s)
                    .padding(.top, 2 * s)
            } else {
                SectionLabel(text: model.phase == .longBreak ? "长休息" : "休息一下", s: s)
                Text(model.breakTip)
                    .font(Typo.serif(21 * s))
                    .foregroundColor(t.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("休息时彻底离开工作，不看消息，回来会更专注。")
                    .font(Typo.text(11.5 * s, .medium))
                    .foregroundColor(t.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .onChange(of: model.currentTaskID) { expandTitle = false }
    }
}

/// 竖屏时的「当前任务」胶囊，点开是任务清单
struct CurrentTaskPill: View {
    @ObservedObject var model: TimerModel
    let fs: CGFloat
    @State private var showList = false
    @Environment(\.theme) private var t

    var body: some View {
        Button { showList.toggle() } label: {
            HStack(spacing: fs * 0.55) {
                Image(systemName: "list.bullet")
                    .font(.system(size: fs * 0.85, weight: .medium))
                Text(model.currentTask?.title ?? "添加今天的任务")
                    .foregroundColor(model.currentTask == nil ? t.gray : t.ink)
                    .lineLimit(1)
                if let task = model.currentTask {
                    Text("\(task.done)/\(task.estimate)")
                        .font(Typo.display(fs * 1.15))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: fs * 0.6, weight: .semibold))
                    .foregroundColor(t.gray)
            }
            .font(Typo.text(fs, .medium))
            .foregroundColor(t.ink)
            .padding(.horizontal, fs * 1.0)
            .padding(.vertical, fs * 0.5)
            .overlay(Capsule().strokeBorder(t.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help("今日待办")
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            TaskListView(model: model, s: 1)
                .padding(18)
                .frame(width: 340, height: 430)
                .environment(\.theme, t)
                .presentationBackground(t.bg)
        }
    }
}


// MARK: - 优先级标签、DDL、Notion 同步按钮

/// P0 实心红；P1 彩色描边；P2 墨色描边；P3 灰字
struct PriorityTag: View {
    let level: Int
    let s: CGFloat
    @Environment(\.theme) private var t

    var body: some View {
        let red = t.accent(.focus)
        Text("P\(level)")
            .font(Typo.display(11 * s))
            .padding(.horizontal, 5 * s)
            .padding(.vertical, 1 * s)
            .foregroundColor(level == 0 ? t.onInk : (level == 1 ? red : (level == 2 ? t.ink : t.gray)))
            .background(Capsule().fill(level == 0 ? red : Color.clear))
            .overlay(Capsule().strokeBorder(level == 1 ? red : (level == 2 ? t.ink.opacity(0.6) : t.line),
                                            lineWidth: level == 0 ? 0 : 1))
    }
}

/// 副标题一行：[P1] DDL 剩 3 天 · 工作 · 预估 2 · 完成 0
struct TaskMetaLine: View {
    let task: TaskItem
    let s: CGFloat
    var showEstimate = true
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 6 * s) {
            if let p = task.priority { PriorityTag(level: p, s: s) }
            if let ddl = DDL.describe(task), !task.finished {
                Text(ddl.text)
                    .foregroundColor(ddl.level == 0 ? t.accent(.focus) : (ddl.level <= 2 ? t.warning : t.gray))
            }
            if let tag = task.tag { Text(tag).foregroundColor(t.gray) }
            if showEstimate {
                Text("预估 \(task.estimate) · 完成 \(task.done)").foregroundColor(t.gray)
            }
        }
        .font(Typo.text(11.5 * s, .medium))
        .lineLimit(1)
    }
}

struct NotionSyncButton: View {
    let s: CGFloat
    @ObservedObject private var sync = NotionSync.shared
    @Environment(\.theme) private var t

    private var help: String {
        if !sync.config.isConfigured { return "在设置里填写 Notion 令牌与数据库后，自动同步任务" }
        if let e = sync.lastError { return "同步失败：\(e)" }
        if let d = sync.lastSync { return "上次同步 \(Fmt.hm.string(from: d))，\(sync.lastCount) 条 · 点击立即同步" }
        return "立即同步 Notion"
    }

    var body: some View {
        if sync.config.isConfigured {
            Button { sync.sync() } label: {
                HStack(spacing: 4 * s) {
                    Image(systemName: sync.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                        .font(.system(size: 10 * s, weight: .semibold))
                        .rotationEffect(.degrees(sync.syncing ? 360 : 0))
                        .animation(sync.syncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                   value: sync.syncing)
                    Text(sync.lastSync.map { "Notion \(Fmt.hm.string(from: $0))" } ?? "Notion")
                }
                .font(Typo.text(11 * s, .medium))
                .foregroundColor(sync.lastError == nil ? t.gray : t.accent(.focus))
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }
}
