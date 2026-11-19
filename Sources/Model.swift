// 数据与计时逻辑：阶段、任务清单、今日统计、打断记录（番茄工作法）
import SwiftUI
import AppKit

// MARK: - 阶段

enum Phase: String, CaseIterable, Identifiable, Codable {
    case focus, shortBreak, longBreak
    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "短休息"
        case .longBreak: return "长休息"
        }
    }
}

// MARK: - 设置项（UserDefaults 键）

enum Key {
    static let focusMin = "focusMinutes"
    static let shortMin = "shortBreakMinutes"
    static let longMin = "longBreakMinutes"
    static let longEvery = "longBreakEvery"
    static let autoStart = "autoStartNext"
    static let sound = "playSound"
    static let onTop = "alwaysOnTop"
    static let autoFullScreen = "autoFullScreenOnIPad"
    static let appearance = "appearance"
    static let menuBar = "showInMenuBar"
    static let tasks = "tasks"
    static let currentTask = "currentTaskID"
    static let stats = "dayStats"
    // 第一版遗留的键，仅用于迁移
    static let legacyTaskName = "taskName"
    static let legacyStatsDate = "statsDate"
    static let legacyStatsCount = "statsCount"
}

// MARK: - 数据结构

/// 「今日待办」里的一项：预估番茄数 vs 实际完成数
struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var estimate: Int = 1
    var done: Int = 0
    var finished = false
    // 以下为可选字段（旧数据里没有，解码为 nil）
    /// 0 = P0 紧急 … 3 = P3 低
    var priority: Int?
    /// DDL（截止时间）
    var due: Date?
    /// DDL 是否带具体时刻；否则视为当天 23:59
    var dueHasTime: Bool?
    /// 计划哪天做
    var scheduled: Date?
    var top3: Bool?
    var note: String?
    /// "notion" = 从 Notion 同步；nil = 本地添加（手动或 AI 接口）
    var source: String?
    var notionID: String?
    var notionURL: String?
    /// Notion 里的分类 / 课程，显示在副标题
    var tag: String?

    var isNotion: Bool { source == "notion" }
    var isTop3: Bool { top3 == true }
    /// DDL 的实际截止时刻（只有日期时取当天结束）
    var dueMoment: Date? {
        guard let due else { return nil }
        if dueHasTime == true { return due }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: due)
    }
    /// 排序键：Top 3 → 优先级 → DDL → 原顺序
    var sortKey: (Int, Int, Double) {
        (isTop3 ? 0 : 1, priority ?? 9, dueMoment?.timeIntervalSince1970 ?? .greatestFiniteMagnitude)
    }
}

/// DDL 的人话描述与紧急程度（0 已逾期 / 1 一天内 / 2 三天内 / 3 更远）
enum DDL {
    static func describe(_ task: TaskItem, now: Date = Date()) -> (text: String, level: Int)? {
        guard let due = task.due, let moment = task.dueMoment else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        let hm = task.dueHasTime == true ? " \(Fmt.hm.string(from: due))" : ""
        if moment < now {
            return (days < 0 ? "已逾期 \(-days) 天" : "已逾期", 0)
        }
        let soon = moment.timeIntervalSince(now) < 24 * 3600
        switch days {
        case 0: return ("今天\(hm) 截止", 1)
        case 1: return ("明天\(hm) 截止", soon ? 1 : 2)
        case 2...3: return ("剩 \(days) 天", 2)
        default: return ("\(Fmt.md.string(from: due)) 截止", 3)
        }
    }
}

/// 从 Notion 拉回来的一条任务
struct NotionTask {
    var id: String
    var url: String?
    var title: String
    var priority: Int?
    var due: Date?
    var dueHasTime: Bool
    var scheduled: Date?
    var top3: Bool
    var tag: String?
}

/// 当天的记录（跨天自动清零）
struct DayStats: Codable, Equatable {
    var day: String
    var completed = 0
    var voided = 0
    var internalBreaks = 0
    var externalBreaks = 0
    var focusSeconds: Double = 0
    var interruptions: Int { internalBreaks + externalBreaks }
}

enum BreakTips {
    static let short = [
        "起身走两步，活动一下肩颈", "喝口水，补充一下水分", "看看窗外远处，放松眼睛",
        "闭上眼，做三次深呼吸", "伸个懒腰，舒展一下身体", "别刷手机，让大脑真正休息",
    ]
    static let long = [
        "出去走走，散个步", "吃点东西，补充能量", "回顾一下这一组番茄完成了什么",
        "离开座位，彻底放空一会儿", "和人聊聊天，换换脑子",
    ]
}

enum Fmt {
    static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    static let md: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()
    static func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }
}

// MARK: - 计时模型

final class TimerModel: ObservableObject {
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    /// 本组（距上次长休息）已完成的专注数
    @Published private(set) var streak = 0
    /// 每次自然结束 +1，界面据此闪屏
    @Published private(set) var finishToken = 0
    @Published private(set) var stats: DayStats
    /// 当前这个番茄里的打断次数
    @Published private(set) var sessionInternal = 0
    @Published private(set) var sessionExternal = 0
    @Published private(set) var breakTip = BreakTips.short[0]
    @Published var tasks: [TaskItem] = [] { didSet { save(tasks, Key.tasks) } }
    @Published var currentTaskID: UUID? = nil {
        didSet { d.set(currentTaskID?.uuidString, forKey: Key.currentTask) }
    }

    /// 任务被标记完成时回调（用于回写 Notion）
    var onTaskFinished: ((TaskItem) -> Void)?

    private(set) var endDate: Date?
    private var sessionTouched = false
    private var ticker: Timer?
    private var activity: NSObjectProtocol?
    private let d: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.d = defaults
        stats = DayStats(day: Self.dayString())
        d.register(defaults: [
            Key.focusMin: 25, Key.shortMin: 5, Key.longMin: 15, Key.longEvery: 4,
            Key.autoStart: false, Key.sound: true, Key.onTop: false, Key.autoFullScreen: true,
            Key.appearance: "light", Key.menuBar: true,
        ])
        let (loadedStats, rolledOver) = loadStats()
        stats = loadedStats
        tasks = load([TaskItem].self, Key.tasks) ?? []
        if rolledOver {
            tasks.removeAll { $0.finished }
            saveStats()
        }
        currentTaskID = d.string(forKey: Key.currentTask).flatMap(UUID.init(uuidString:))
        if tasks.isEmpty, let legacy = d.string(forKey: Key.legacyTaskName), !legacy.isEmpty {
            addTask(legacy)
            d.removeObject(forKey: Key.legacyTaskName)
        }
        remaining = duration(of: .focus)
    }

    // MARK: 派生值

    func duration(of p: Phase) -> TimeInterval {
        let key: String
        switch p {
        case .focus: key = Key.focusMin
        case .shortBreak: key = Key.shortMin
        case .longBreak: key = Key.longMin
        }
        return TimeInterval(max(1, d.integer(forKey: key)) * 60)
    }
    var total: TimeInterval { duration(of: phase) }
    var longEvery: Int { max(1, d.integer(forKey: Key.longEvery)) }
    var progress: Double { min(1, max(0, 1 - remaining / total)) }
    var hasStarted: Bool { isRunning || sessionTouched }
    var projectedEnd: Date { endDate ?? Date().addingTimeInterval(remaining) }
    var currentTask: TaskItem? { tasks.first { $0.id == currentTaskID } }
    var timeText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: 计时操作

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        ensureToday()
        if remaining <= 0 { remaining = total }
        endDate = Date().addingTimeInterval(remaining)
        sessionTouched = true
        isRunning = true
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        // 计时中阻止显示器休眠，避免 Mac 息屏导致 iPad 副屏断开
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated], reason: "番茄钟计时中")
    }

    func pause() {
        guard isRunning else { return }
        if let e = endDate { remaining = max(0, e.timeIntervalSinceNow) }
        stopTicker()
    }

    func reset() {
        stopTicker()
        enter(phase)
    }

    /// 专注中途放弃 = 作废（番茄工作法：一个番茄不可分割）；休息时 = 直接结束休息
    func skip() {
        if phase == .focus && hasStarted {
            ensureToday()
            stats.voided += 1
            saveStats()
        }
        advance(completed: false)
    }

    func select(_ p: Phase) {
        stopTicker()
        enter(p)
    }

    /// 时长设置变化后：未开始则套用新时长；暂停中不重置进度（新时长更短时仅钳制上限）
    func settingsChanged() {
        if !isRunning && !sessionTouched {
            remaining = total
        } else if !isRunning {
            remaining = min(remaining, total)
        }
        objectWillChange.send()
    }

    /// 记录一次打断：内部（自己走神，记作 '）/ 外部（别人或消息，记作 -）
    func logInterruption(internal isInternal: Bool) {
        guard phase == .focus else { return }
        ensureToday()
        if isInternal {
            sessionInternal += 1
            stats.internalBreaks += 1
        } else {
            sessionExternal += 1
            stats.externalBreaks += 1
        }
        saveStats()
    }

    /// 清零今日成果：番茄数、专注时长、打断、作废、本组进度（任务清单和各任务的番茄数不动）
    func resetToday() {
        stats = DayStats(day: Self.dayString())
        saveStats()
        streak = 0
        sessionInternal = 0
        sessionExternal = 0
    }

    /// 撤销一次误记的打断：只减当前这个番茄里记过的次数（减到 0 为止），今日统计同步减回
    @discardableResult
    func undoInterruption(internal isInternal: Bool) -> Bool {
        guard phase == .focus else { return false }
        ensureToday()
        if isInternal {
            guard sessionInternal > 0 else { return false }
            sessionInternal -= 1
            stats.internalBreaks = max(0, stats.internalBreaks - 1)
        } else {
            guard sessionExternal > 0 else { return false }
            sessionExternal -= 1
            stats.externalBreaks = max(0, stats.externalBreaks - 1)
        }
        saveStats()
        return true
    }

    // MARK: 任务清单

    /// 排好序的任务：未完成在前，其中 Top 3 → 优先级 → DDL → 添加顺序
    var sortedTasks: [TaskItem] {
        let indexed = tasks.enumerated().map { ($0.offset, $0.element) }
        return indexed.sorted { a, b in
            if a.1.finished != b.1.finished { return !a.1.finished }
            if a.1.sortKey != b.1.sortKey { return a.1.sortKey < b.1.sortKey }
            return a.0 < b.0
        }.map(\.1)
    }

    /// 快速添加语法（可任意组合写在末尾）：
    ///   ×3 / x3 / *3    预估 3 个番茄
    ///   P0 … P3          优先级
    ///   @今天 @明天 @11-25 @2026-11-25   DDL
    @discardableResult
    func addTask(_ raw: String) -> TaskItem? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var estimate = 1
        var priority: Int?
        var due: Date?
        var changed = true
        while changed {
            changed = false
            if let r = title.range(of: #"\s*[x×X*]\s*(\d{1,2})$"#, options: .regularExpression),
               let n = Int(title[r].filter(\.isNumber)), n > 0 {
                estimate = min(n, 12)
                title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if let r = title.range(of: #"(^|\s+)[Pp][0-3]$"#, options: .regularExpression),
               let n = Int(title[r].filter(\.isNumber)) {
                priority = n
                title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                changed = true
            }
            if let r = title.range(of: #"(^|\s+)@\S+$"#, options: .regularExpression),
               let date = Self.parseDay(String(title[r]).trimmingCharacters(in: .whitespaces).dropFirst()) {
                due = date
                title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return addTask(title: title, estimate: estimate, priority: priority, due: due)
    }

    /// 结构化添加（AI 接口用）
    @discardableResult
    func addTask(title: String, estimate: Int = 1, priority: Int? = nil, due: Date? = nil,
                 dueHasTime: Bool = false, top3: Bool = false, note: String? = nil) -> TaskItem? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var t = TaskItem(title: title, estimate: min(12, max(1, estimate)))
        t.priority = priority.map { min(3, max(0, $0)) }
        t.due = due
        t.dueHasTime = due == nil ? nil : dueHasTime
        t.top3 = top3 ? true : nil
        t.note = note
        tasks.append(t)
        if currentTask == nil || currentTask?.finished == true { autoSelect() }
        return tasks.first { $0.id == t.id }
    }

    /// 修改任务（AI 接口用）
    func updateTask(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let wasFinished = tasks[i].finished
        change(&tasks[i])
        tasks[i].estimate = min(12, max(1, tasks[i].estimate))
        if !wasFinished && tasks[i].finished { didFinish(tasks[i]) }
    }

    func selectTask(_ id: UUID) { currentTaskID = id }

    func toggleFinished(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].finished.toggle()
        if tasks[i].finished { didFinish(tasks[i]) }
    }

    func removeTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        if currentTaskID == id { autoSelect() }
    }

    func adjustEstimate(_ id: UUID, by delta: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].estimate = min(12, max(1, tasks[i].estimate + delta))
    }

    func clearFinished() {
        tasks.removeAll { $0.finished }
        if currentTask == nil { autoSelect() }
    }

    /// 合并 Notion 拉回的任务：新增 / 更新字段，Notion 里已完成或移出范围的同步任务移除。
    /// 本地记录的番茄数、预估、完成状态保留。
    func mergeNotion(_ items: [NotionTask]) {
        var result = tasks
        for it in items {
            if let i = result.firstIndex(where: { $0.notionID == it.id }) {
                result[i].title = it.title
                result[i].priority = it.priority
                result[i].due = it.due
                result[i].dueHasTime = it.due == nil ? nil : it.dueHasTime
                result[i].scheduled = it.scheduled
                result[i].top3 = it.top3 ? true : nil
                result[i].notionURL = it.url
                result[i].tag = it.tag
            } else {
                var t = TaskItem(title: it.title)
                t.source = "notion"
                t.notionID = it.id
                t.notionURL = it.url
                t.priority = it.priority
                t.due = it.due
                t.dueHasTime = it.due == nil ? nil : it.dueHasTime
                t.scheduled = it.scheduled
                t.top3 = it.top3 ? true : nil
                t.tag = it.tag
                result.append(t)
            }
        }
        let alive = Set(items.map(\.id))
        result.removeAll { t in
            t.isNotion && !alive.contains(t.notionID ?? "") && !(t.id == currentTaskID && isRunning) && !t.finished
        }
        tasks = result
        if currentTask == nil || currentTask?.finished == true { autoSelect() }
    }

    private func didFinish(_ task: TaskItem) {
        if currentTaskID == task.id { autoSelect() }
        onTaskFinished?(task)
    }

    private func autoSelect() {
        currentTaskID = sortedTasks.first { !$0.finished }?.id
    }

    /// 解析「今天 / 明天 / 后天 / 11-25 / 11/25 / 2026-11-25」
    static func parseDay<S: StringProtocol>(_ s: S) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch s {
        case "今天", "today": return today
        case "明天", "tomorrow": return cal.date(byAdding: .day, value: 1, to: today)
        case "后天": return cal.date(byAdding: .day, value: 2, to: today)
        default: break
        }
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).compactMap { Int($0) }
        var c = cal.dateComponents([.year], from: today)
        switch parts.count {
        case 2: (c.month, c.day) = (parts[0], parts[1])
        case 3: (c.year, c.month, c.day) = (parts[0], parts[1], parts[2])
        default: return nil
        }
        guard let date = cal.date(from: c) else { return nil }
        // 没写年份且日期已过 → 视为明年
        if parts.count == 2, date < today { return cal.date(byAdding: .year, value: 1, to: date) }
        return date
    }

    /// 跨天检查（定时调用）：清零今日统计、清掉昨天已完成的任务
    func refreshDay() { ensureToday() }

    // MARK: 内部

    private func enter(_ p: Phase) {
        phase = p
        sessionTouched = false
        remaining = total
        if p == .focus {
            sessionInternal = 0
            sessionExternal = 0
        } else {
            breakTip = (p == .longBreak ? BreakTips.long : BreakTips.short).randomElement() ?? ""
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
        if let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    private func tick() {
        guard let e = endDate else { return }
        let r = e.timeIntervalSinceNow
        if r <= 0 {
            remaining = 0
            advance(completed: true)
        } else {
            remaining = r
        }
    }

    private func advance(completed: Bool) {
        stopTicker()
        let next: Phase
        if phase == .focus {
            if completed {
                ensureToday()
                stats.completed += 1
                stats.focusSeconds += total
                saveStats()
                streak += 1
                if let i = tasks.firstIndex(where: { $0.id == currentTaskID }) { tasks[i].done += 1 }
            }
            next = streak >= longEvery ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak { streak = 0 }
            next = .focus
        }
        enter(next)

        guard completed else { return }
        finishToken += 1
        NSApp.requestUserAttention(.informationalRequest)
        if d.bool(forKey: Key.sound) { playChime() }
        if d.bool(forKey: Key.autoStart) { start() }
    }

    private func playChime() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.9) {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func ensureToday() {
        let today = Self.dayString()
        if stats.day != today {
            stats = DayStats(day: today)
            saveStats()
            tasks.removeAll { $0.finished }
        }
    }

    private func loadStats() -> (DayStats, Bool) {
        let today = Self.dayString()
        if let s = load(DayStats.self, Key.stats) {
            if s.day == today { return (s, false) }
            return (DayStats(day: today), true)
        }
        var s = DayStats(day: today)
        if d.string(forKey: Key.legacyStatsDate) == today {
            s.completed = d.integer(forKey: Key.legacyStatsCount)
        }
        return (s, false)
    }

    private func saveStats() { save(stats, Key.stats) }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func dayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
