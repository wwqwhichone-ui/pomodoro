// Notion 同步：自动探测任意任务数据库结构，拉取「今天要做 / 近期到期 / 已逾期 / 置顶」且未完成的任务，
// 支持按分类（如 Event 活动）排除过滤，并支持每日番茄钟成果按日期去重同步到 Notion 日志库。
// 令牌与数据库 ID 存在 ~/Library/Application Support/Pomodoro/notion.json（权限 600）。
import Foundation
import AppKit

struct NotionConfig: Codable {
    var token: String = ""
    /// 新版 API（2025-09-03）用 data source ID；旧版用 database ID，自动探测并优先尝试新版
    var dataSourceID: String = ""
    var databaseID: String = ""
    /// 在番茄钟里勾选完成时，把 Notion 里的完成状态回写为 Done / 已完成
    var writeBack: Bool = false
    /// DDL 往后看几天
    var lookaheadDays: Int = 7
    /// 排除不进入「今日待办」的分类名（例如 Event、活动、会议）
    var excludedCategories: [String] = ["Event"]
    /// 每日番茄记录数据库（如 Pomodoro Log）的 data source / database ID
    var logDataSourceID: String = ""
    var logDatabaseID: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        dataSourceID = try c.decodeIfPresent(String.self, forKey: .dataSourceID) ?? ""
        databaseID = try c.decodeIfPresent(String.self, forKey: .databaseID) ?? ""
        writeBack = try c.decodeIfPresent(Bool.self, forKey: .writeBack) ?? false
        let days = try c.decodeIfPresent(Int.self, forKey: .lookaheadDays) ?? 7
        lookaheadDays = min(90, max(1, days))
        excludedCategories = try c.decodeIfPresent([String].self, forKey: .excludedCategories) ?? ["Event"]
        logDataSourceID = try c.decodeIfPresent(String.self, forKey: .logDataSourceID) ?? ""
        logDatabaseID = try c.decodeIfPresent(String.self, forKey: .logDatabaseID) ?? ""
    }

    var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDataSourceID: String { dataSourceID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDatabaseID: String { databaseID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var targetInput: String { !trimmedDataSourceID.isEmpty ? trimmedDataSourceID : trimmedDatabaseID }
    var isConfigured: Bool { !trimmedToken.isEmpty && (!trimmedDataSourceID.isEmpty || !trimmedDatabaseID.isEmpty) }

    var trimmedLogDataSourceID: String { logDataSourceID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedLogDatabaseID: String { logDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var logTargetInput: String { !trimmedLogDataSourceID.isEmpty ? trimmedLogDataSourceID : trimmedLogDatabaseID }
    var isLogConfigured: Bool { !trimmedToken.isEmpty && (!trimmedLogDataSourceID.isEmpty || !trimmedLogDatabaseID.isEmpty) }
    var excludedCategoriesText: String { excludedCategories.joined(separator: ", ") }

    static func parseCategories(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let seps = CharacterSet(charactersIn: ",，")
        for part in raw.components(separatedBy: seps) {
            let clean = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let lower = clean.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                result.append(clean)
            }
        }
        return result
    }
}

private enum SchemaMatch {
    typealias PropEntry = (name: String, prop: [String: Any], type: String)

    static func databaseTitle(from json: [String: Any]) -> String? {
        guard let titleArr = json["title"] as? [[String: Any]] else { return nil }
        let t = titleArr.compactMap { $0["plain_text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func entries(from json: [String: Any]) -> [PropEntry] {
        guard let props = json["properties"] as? [String: [String: Any]] else { return [] }
        return props.map { (name: $0.key, prop: $0.value, type: ($0.value["type"] as? String ?? "")) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func findMatching(_ entries: [PropEntry], type: String, keywords: [String],
                             excluding used: Set<String>, avoidInSubstring: [String] = []) -> PropEntry? {
        findMatching(entries, types: [type], keywords: keywords, excluding: used, avoidInSubstring: avoidInSubstring)
    }

    static func findMatching(_ entries: [PropEntry], types: [String], keywords: [String],
                             excluding used: Set<String>, avoidInSubstring: [String] = []) -> PropEntry? {
        let candidates = entries.filter { types.contains($0.type) && !used.contains($0.name) }
        for kw in keywords {
            if let exact = candidates.first(where: {
                $0.name.trimmingCharacters(in: .whitespaces).lowercased() == kw
            }) {
                return exact
            }
        }
        for kw in keywords {
            if let sub = candidates.first(where: { entry in
                let l = entry.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard l.contains(kw) else { return false }
                return !avoidInSubstring.contains { l.contains($0) }
            }) {
                return sub
            }
        }
        return nil
    }
}

/// 从任意 Notion 任务数据库自动探测出的字段映射
struct NotionSchema: Equatable {
    var databaseTitle: String?
    var titleProp: String?
    var statusProp: String?
    var statusType: String? // "status" | "select" | "checkbox"
    var openStatuses: [String] = []
    var doneStatus: String?
    var dueProp: String?
    var scheduledProp: String?
    var priorityProp: String?
    var top3Prop: String?
    var categoryProp: String?
    var categoryType: String? // "select" | "multi_select"
    var categoryOptions: [String] = []
    var tagProps: [String] = []

    static func detect(from json: [String: Any]) -> NotionSchema {
        var schema = NotionSchema()
        schema.databaseTitle = SchemaMatch.databaseTitle(from: json)
        let entries = SchemaMatch.entries(from: json)
        guard !entries.isEmpty else { return schema }
        var used = Set<String>()

        // 1. 标题列
        if let titleEntry = entries.first(where: { $0.type == "title" }) {
            schema.titleProp = titleEntry.name
            used.insert(titleEntry.name)
        }

        // 2. 状态列：status -> select -> checkbox
        let statusKeywords = ["status", "状态", "state", "进度"]
        let doneKeywords = ["done", "completed", "complete", "finished", "已完成", "完成"]
        let closedKeywords = doneKeywords + ["archived", "cancelled", "canceled", "已归档", "已取消"]

        if let stEntry = SchemaMatch.findMatching(entries, type: "status", keywords: statusKeywords, excluding: used)
            ?? entries.first(where: { $0.type == "status" && !used.contains($0.name) }) {
            schema.statusProp = stEntry.name
            schema.statusType = "status"
            used.insert(stEntry.name)
            let stObj = stEntry.prop["status"] as? [String: Any] ?? [:]
            let options = stObj["options"] as? [[String: Any]] ?? []
            let allNames = options.compactMap { $0["name"] as? String }
            let groups = stObj["groups"] as? [[String: Any]] ?? []
            var completeIDs = Set<String>()
            for g in groups {
                let gName = (g["name"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                if gName == "complete" || gName == "done" || gName == "已完成" {
                    for id in (g["option_ids"] as? [String] ?? []) { completeIDs.insert(id) }
                }
            }
            if !completeIDs.isEmpty {
                let completeNames = options.compactMap { opt -> String? in
                    guard let id = opt["id"] as? String, completeIDs.contains(id) else { return nil }
                    return opt["name"] as? String
                }
                schema.doneStatus = completeNames.first {
                    let l = $0.trimmingCharacters(in: .whitespaces).lowercased()
                    return l == "done" || l == "已完成"
                } ?? completeNames.first
                schema.openStatuses = options.compactMap { opt -> String? in
                    guard let id = opt["id"] as? String, !completeIDs.contains(id) else { return nil }
                    return opt["name"] as? String
                }
            } else {
                schema.doneStatus = allNames.first { name in
                    let l = name.trimmingCharacters(in: .whitespaces).lowercased()
                    return doneKeywords.contains { l == $0 || l.contains($0) }
                }
                schema.openStatuses = allNames.filter { name in
                    let l = name.trimmingCharacters(in: .whitespaces).lowercased()
                    return !closedKeywords.contains { l == $0 || l.contains($0) }
                }
            }
        } else if let selEntry = SchemaMatch.findMatching(entries, type: "select", keywords: statusKeywords, excluding: used) {
            schema.statusProp = selEntry.name
            schema.statusType = "select"
            used.insert(selEntry.name)
            let options = (selEntry.prop["select"] as? [String: Any])?["options"] as? [[String: Any]] ?? []
            let allNames = options.compactMap { $0["name"] as? String }
            schema.doneStatus = allNames.first { name in
                let l = name.trimmingCharacters(in: .whitespaces).lowercased()
                return doneKeywords.contains { l == $0 || l.contains($0) }
            }
            schema.openStatuses = allNames.filter { name in
                let l = name.trimmingCharacters(in: .whitespaces).lowercased()
                return !closedKeywords.contains { l == $0 || l.contains($0) }
            }
        } else if let chkEntry = SchemaMatch.findMatching(entries, type: "checkbox", keywords: doneKeywords, excluding: used) {
            schema.statusProp = chkEntry.name
            schema.statusType = "checkbox"
            used.insert(chkEntry.name)
        }

        // 3. 截止日期列
        let dueKeywords = ["due date", "due", "ddl", "deadline", "截止日期", "截止时间", "截止", "date", "日期"]
        let scheduledGuard = ["scheduled", "do date", "plan", "计划", "开始"]
        if let due = SchemaMatch.findMatching(entries, type: "date", keywords: dueKeywords, excluding: used,
                                              avoidInSubstring: scheduledGuard) {
            schema.dueProp = due.name
            used.insert(due.name)
        }

        // 4. 计划日期列
        let scheduledKeywords = ["scheduled date", "scheduled", "do date", "plan date", "计划日期", "安排日期", "计划", "开始日期"]
        if let sched = SchemaMatch.findMatching(entries, type: "date", keywords: scheduledKeywords, excluding: used) {
            schema.scheduledProp = sched.name
            used.insert(sched.name)
        }

        // 5. 优先级列
        let priorityKeywords = ["priority", "优先级", "紧急", "级别"]
        if let prio = SchemaMatch.findMatching(entries, types: ["select", "status"], keywords: priorityKeywords, excluding: used) {
            schema.priorityProp = prio.name
            used.insert(prio.name)
        }

        // 6. 置顶 / Top 3 列
        let top3Keywords = ["top 3", "top3", "focus", "pinned", "important", "重点", "置顶", "今日重点"]
        if let top3 = SchemaMatch.findMatching(entries, type: "checkbox", keywords: top3Keywords, excluding: used) {
            schema.top3Prop = top3.name
            used.insert(top3.name)
        }

        // 6.5. 分类列（用于排除过滤，不放入 used 以保持副标题标签兼容）
        let categoryKeywords = ["category", "type", "kind", "分类", "类别", "类型"]
        if let cat = SchemaMatch.findMatching(entries, types: ["select", "multi_select"], keywords: categoryKeywords, excluding: used) {
            schema.categoryProp = cat.name
            schema.categoryType = cat.type
            let options = ((cat.prop[cat.type] as? [String: Any])?["options"] as? [[String: Any]]) ?? []
            schema.categoryOptions = options.compactMap { $0["name"] as? String }
        }

        // 7. 标签 / 课程 / 分类列
        let tagKeywords = ["course", "category", "project", "area", "tag", "tags", "课程", "分类", "项目", "标签"]
        var tags: [String] = []
        for kw in tagKeywords {
            for e in entries where (e.type == "select" || e.type == "multi_select") && !used.contains(e.name) {
                let l = e.name.trimmingCharacters(in: .whitespaces).lowercased()
                if l == kw || l.contains(kw) {
                    tags.append(e.name)
                    used.insert(e.name)
                }
            }
        }
        schema.tagProps = tags

        return schema
    }
}

/// 从任意 Notion 每日记录数据库（如 Pomodoro Log）自动探测出的字段映射
struct NotionLogSchema: Equatable {
    var databaseTitle: String?
    var titleProp: String?
    var dateProp: String?
    var completedProp: String?
    var focusMinutesProp: String?
    var internalProp: String?
    var externalProp: String?
    var voidedProp: String?
    var tasksProp: String?

    static func detect(from json: [String: Any]) -> NotionLogSchema {
        var schema = NotionLogSchema()
        schema.databaseTitle = SchemaMatch.databaseTitle(from: json)
        let entries = SchemaMatch.entries(from: json)
        guard !entries.isEmpty else { return schema }
        var used = Set<String>()

        if let t = entries.first(where: { $0.type == "title" }) {
            schema.titleProp = t.name
            used.insert(t.name)
        }
        if let d = SchemaMatch.findMatching(entries, type: "date", keywords: ["date", "day", "日期", "时间"], excluding: used) {
            schema.dateProp = d.name
            used.insert(d.name)
        }
        if let p = SchemaMatch.findMatching(entries, type: "number",
                                            keywords: ["pomodoros", "pomodoro", "completed", "count", "番茄数", "番茄", "完成数", "完成"],
                                            excluding: used) {
            schema.completedProp = p.name
            used.insert(p.name)
        }
        if let m = SchemaMatch.findMatching(entries, type: "number",
                                            keywords: ["focus minutes", "minutes", "focus", "duration", "专注分钟", "专注时长", "分钟", "时长"],
                                            excluding: used) {
            schema.focusMinutesProp = m.name
            used.insert(m.name)
        }
        if let i = SchemaMatch.findMatching(entries, type: "number",
                                            keywords: ["internal interruptions", "internal breaks", "internal", "内部打断", "内打断"],
                                            excluding: used) {
            schema.internalProp = i.name
            used.insert(i.name)
        }
        if let e = SchemaMatch.findMatching(entries, type: "number",
                                            keywords: ["external interruptions", "external breaks", "external", "外部打断", "外打断"],
                                            excluding: used) {
            schema.externalProp = e.name
            used.insert(e.name)
        }
        if let v = SchemaMatch.findMatching(entries, type: "number",
                                            keywords: ["voided", "void", "abandoned", "作废", "放弃"],
                                            excluding: used) {
            schema.voidedProp = v.name
            used.insert(v.name)
        }
        if let s = SchemaMatch.findMatching(entries, type: "rich_text",
                                            keywords: ["tasks", "task summary", "summary", "notes", "任务", "任务明细", "摘要", "备注"],
                                            excluding: used) {
            schema.tasksProp = s.name
            used.insert(s.name)
        }

        return schema
    }
}

enum AppFiles {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Pomodoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 写入并把权限设为 600（文件里有令牌）
    static func writePrivate(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

final class NotionSync: ObservableObject {
    static let shared = NotionSync()

    @Published private(set) var config = NotionConfig()
    @Published private(set) var syncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var databaseTitle: String?

    @Published private(set) var logSyncing = false
    @Published private(set) var lastLogSync: Date?
    @Published private(set) var lastLogError: String?
    @Published private(set) var logDatabaseTitle: String?

    private weak var model: TimerModel?
    private var timer: Timer?
    private let fileURL = AppFiles.dir.appendingPathComponent("notion.json")
    private var cachedSchema: (key: String, schema: NotionSchema, useDataSource: Bool)?
    private var cachedLogSchema: (key: String, schema: NotionLogSchema, useDataSource: Bool)?

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let c = try? JSONDecoder().decode(NotionConfig.self, from: data) {
            config = c
        }
    }

    private static func cacheKey(for c: NotionConfig) -> String {
        "\(c.trimmedToken)|\(c.trimmedDataSourceID)|\(c.trimmedDatabaseID)"
    }

    private static func logCacheKey(for c: NotionConfig) -> String {
        "\(c.trimmedToken)|\(c.trimmedLogDataSourceID)|\(c.trimmedLogDatabaseID)"
    }

    /// 从 Notion 页面链接、32 位十六进制字符串或标准 UUID 中提取并规范化 ID
    static func extractID(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let base = trimmed.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? trimmed
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return trimmed }
        let range = NSRange(base.startIndex..., in: base)
        let matches = regex.matches(in: base, range: range)
        guard let last = matches.last, let swiftRange = Range(last.range, in: base) else {
            return trimmed
        }
        let hex = base[swiftRange].replacingOccurrences(of: "-", with: "").lowercased()
        guard hex.count == 32 else { return trimmed }
        let i0 = hex.startIndex
        let i1 = hex.index(i0, offsetBy: 8)
        let i2 = hex.index(i1, offsetBy: 4)
        let i3 = hex.index(i2, offsetBy: 4)
        let i4 = hex.index(i3, offsetBy: 4)
        return "\(hex[i0..<i1])-\(hex[i1..<i2])-\(hex[i2..<i3])-\(hex[i3..<i4])-\(hex[i4...])"
    }

    /// 启动：立即同步任务并冲刷每日记录，之后每 30 分钟检查一次
    func start(model: TimerModel) {
        guard self.model == nil else { return }
        self.model = model
        model.onTaskFinished = { [weak self] task in self?.taskFinished(task) }
        model.onDailyLogReady = { [weak self] in self?.flushPendingLogs(syncTodayIfActive: false) }
        model.onFocusCompleted = { [weak self] entry in self?.syncFocusCompleted(entry) }
        sync()
        flushPendingLogs(syncTodayIfActive: true)
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.model?.refreshDay()
            self?.sync()
            self?.flushPendingLogs(syncTodayIfActive: true)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func update(_ change: (inout NotionConfig) -> Void) {
        let oldKey = Self.cacheKey(for: config)
        let oldLogKey = Self.logCacheKey(for: config)
        change(&config)
        config.lookaheadDays = min(90, max(1, config.lookaheadDays))
        if let data = try? JSONEncoder().encode(config) { AppFiles.writePrivate(data, to: fileURL) }
        if Self.cacheKey(for: config) != oldKey {
            cachedSchema = nil
            databaseTitle = nil
        }
        if Self.logCacheKey(for: config) != oldLogKey {
            cachedLogSchema = nil
            logDatabaseTitle = nil
        }
    }

    // MARK: 拉取任务

    func sync(completion: ((Result<Int, Error>) -> Void)? = nil) {
        let cfg = config
        guard cfg.isConfigured else {
            completion?(.failure(SyncError.notConfigured))
            return
        }
        guard !syncing else {
            completion?(.failure(SyncError.busy))
            return
        }
        syncing = true
        Task {
            do {
                let resolved = try await resolveSchema(using: cfg)
                let items = try await fetchAll(using: cfg, schema: resolved.schema, useDataSource: resolved.useDataSource)
                await MainActor.run {
                    if Self.cacheKey(for: self.config) == Self.cacheKey(for: cfg) {
                        self.cachedSchema = (Self.cacheKey(for: cfg), resolved.schema, resolved.useDataSource)
                        self.databaseTitle = resolved.schema.databaseTitle
                    }
                    self.model?.mergeNotion(items)
                    self.lastSync = Date()
                    self.lastCount = items.count
                    self.lastError = nil
                    self.syncing = false
                    completion?(.success(items.count))
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.syncing = false
                    completion?(.failure(error))
                }
            }
        }
    }

    private func resolveDatabaseSchema<S>(
        dsID: String, dbID: String, token: String, parse: ([String: Any]) -> S
    ) async throws -> (schema: S, useDataSource: Bool) {
        let targetDB = !dbID.isEmpty ? dbID : dsID
        if !dsID.isEmpty {
            do {
                let json = try await request(method: "GET", path: "data_sources/\(dsID)",
                                             version: "2025-09-03", token: token)
                return (parse(json), true)
            } catch SyncError.http(let code, _) where (code == 400 || code == 404) && !targetDB.isEmpty {
                let json = try await request(method: "GET", path: "databases/\(targetDB)",
                                             version: "2022-06-28", token: token)
                return (parse(json), false)
            }
        } else {
            let json = try await request(method: "GET", path: "databases/\(targetDB)",
                                         version: "2022-06-28", token: token)
            return (parse(json), false)
        }
    }

    private func resolveSchema(using cfg: NotionConfig) async throws -> (schema: NotionSchema, useDataSource: Bool) {
        let key = Self.cacheKey(for: cfg)
        let existing = await MainActor.run { self.cachedSchema }
        if let existing, existing.key == key {
            return (existing.schema, existing.useDataSource)
        }
        return try await resolveDatabaseSchema(
            dsID: cfg.trimmedDataSourceID, dbID: cfg.trimmedDatabaseID, token: cfg.trimmedToken,
            parse: NotionSchema.detect(from:)
        )
    }

    private func resolveLogSchema(using cfg: NotionConfig) async throws -> (schema: NotionLogSchema, useDataSource: Bool) {
        let key = Self.logCacheKey(for: cfg)
        let existing = await MainActor.run { self.cachedLogSchema }
        if let existing, existing.key == key {
            return (existing.schema, existing.useDataSource)
        }
        return try await resolveDatabaseSchema(
            dsID: cfg.trimmedLogDataSourceID, dbID: cfg.trimmedLogDatabaseID, token: cfg.trimmedToken,
            parse: NotionLogSchema.detect(from:)
        )
    }

    private func postQuery(dsID: String, dbID: String, useDataSource: Bool,
                           token: String, body: [String: Any]) async throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: body)
        let targetDB = !dbID.isEmpty ? dbID : dsID
        if useDataSource && !dsID.isEmpty {
            do {
                return try await request(method: "POST", path: "data_sources/\(dsID)/query",
                                         version: "2025-09-03", token: token, body: payload)
            } catch SyncError.http(let code, _) where (code == 400 || code == 404) && !targetDB.isEmpty {
                return try await request(method: "POST", path: "databases/\(targetDB)/query",
                                         version: "2022-06-28", token: token, body: payload)
            }
        }
        return try await request(method: "POST", path: "databases/\(targetDB)/query",
                                 version: "2022-06-28", token: token, body: payload)
    }

    private func fetchAll(using cfg: NotionConfig, schema: NotionSchema, useDataSource: Bool) async throws -> [NotionTask] {
        var all: [NotionTask] = []
        var cursor: String?
        repeat {
            let (results, next) = try await queryPage(using: cfg, schema: schema, useDataSource: useDataSource, cursor: cursor)
            all += results.compactMap { Self.parse($0, schema: schema, excludedCategories: cfg.excludedCategories) }
            cursor = next
        } while cursor != nil && all.count < 500
        return all
    }

    private func queryPage(using cfg: NotionConfig, schema: NotionSchema,
                           useDataSource: Bool, cursor: String?) async throws -> ([[String: Any]], String?) {
        var body = Self.filterBody(lookahead: cfg.lookaheadDays, schema: schema, excludedCategories: cfg.excludedCategories)
        if let cursor { body["start_cursor"] = cursor }
        let json = try await postQuery(dsID: cfg.trimmedDataSourceID, dbID: cfg.trimmedDatabaseID,
                                       useDataSource: useDataSource, token: cfg.trimmedToken, body: body)
        let results = json["results"] as? [[String: Any]] ?? []
        let next = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        return (results, next)
    }

    private func request(method: String, path: String, version: String,
                         token: String, body: Data? = nil) async throws -> [String: Any] {
        guard let url = URL(string: "https://api.notion.com/v1/\(path)") else {
            throw SyncError.http(400, "数据库 ID 格式无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(version, forHTTPHeaderField: "Notion-Version")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard code == 200 else {
            throw SyncError.http(code, json["message"] as? String ?? "HTTP \(code)")
        }
        return json
    }

    /// 仅按实际存在的列构造筛选条件与排序
    static func filterBody(lookahead: Int, schema: NotionSchema, excludedCategories: [String] = []) -> [String: Any] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let until = cal.date(byAdding: .day, value: lookahead, to: today) ?? today
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"

        var andFilters: [[String: Any]] = []
        if let statusProp = schema.statusProp {
            switch schema.statusType {
            case "checkbox":
                andFilters.append(["property": statusProp, "checkbox": ["equals": false]])
            case "select":
                if !schema.openStatuses.isEmpty {
                    let ors = schema.openStatuses.map { ["property": statusProp, "select": ["equals": $0]] }
                    andFilters.append(ors.count == 1 ? ors[0] : ["or": ors])
                }
            default:
                if !schema.openStatuses.isEmpty {
                    let ors = schema.openStatuses.map { ["property": statusProp, "status": ["equals": $0]] }
                    andFilters.append(ors.count == 1 ? ors[0] : ["or": ors])
                }
            }
        }

        if let catProp = schema.categoryProp, !excludedCategories.isEmpty {
            for raw in excludedCategories {
                let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                let matched = schema.categoryOptions.first { $0.caseInsensitiveCompare(clean) == .orderedSame } ?? clean
                if schema.categoryType == "multi_select" {
                    andFilters.append(["property": catProp, "multi_select": ["does_not_contain": matched]])
                } else {
                    andFilters.append(["property": catProp, "select": ["does_not_equal": matched]])
                }
            }
        }

        var relevant: [[String: Any]] = []
        if let scheduledProp = schema.scheduledProp {
            relevant.append(["property": scheduledProp, "date": ["equals": f.string(from: today)]])
        }
        if let dueProp = schema.dueProp {
            relevant.append(["property": dueProp, "date": ["on_or_before": f.string(from: until)]])
        }
        if let top3Prop = schema.top3Prop {
            relevant.append(["property": top3Prop, "checkbox": ["equals": true]])
        }
        if !relevant.isEmpty {
            andFilters.append(relevant.count == 1 ? relevant[0] : ["or": relevant])
        }

        var body: [String: Any] = ["page_size": 100]
        if andFilters.count == 1 {
            body["filter"] = andFilters[0]
        } else if andFilters.count > 1 {
            body["filter"] = ["and": andFilters]
        }
        if let dueProp = schema.dueProp {
            body["sorts"] = [["property": dueProp, "direction": "ascending"]]
        }
        return body
    }

    static func parse(_ page: [String: Any], schema: NotionSchema, excludedCategories: [String] = []) -> NotionTask? {
        guard let id = page["id"] as? String,
              let props = page["properties"] as? [String: Any] else { return nil }

        if let catProp = schema.categoryProp, !excludedCategories.isEmpty,
           let p = props[catProp] as? [String: Any] {
            let excludedSet = Set(excludedCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
            var values: [String] = []
            if let s = (p["select"] as? [String: Any])?["name"] as? String { values.append(s) }
            if let arr = p["multi_select"] as? [[String: Any]] {
                values.append(contentsOf: arr.compactMap { $0["name"] as? String })
            }
            if values.contains(where: { excludedSet.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }) {
                return nil
            }
        }

        let titleObj: [String: Any]?
        if let key = schema.titleProp, let obj = props[key] as? [String: Any] {
            titleObj = obj
        } else {
            titleObj = props.values.compactMap { $0 as? [String: Any] }
                .first { ($0["type"] as? String) == "title" || $0["title"] is [[String: Any]] }
        }
        let title = ((titleObj?["title"] as? [[String: Any]]) ?? [])
            .compactMap { $0["plain_text"] as? String }.joined()
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        func selectOrStatus(_ name: String) -> String? {
            guard let p = props[name] as? [String: Any] else { return nil }
            if let s = (p["select"] as? [String: Any])?["name"] as? String { return s }
            if let s = (p["status"] as? [String: Any])?["name"] as? String { return s }
            if let arr = p["multi_select"] as? [[String: Any]], let first = arr.first?["name"] as? String { return first }
            return nil
        }
        func date(_ name: String) -> (Date, Bool)? {
            guard let s = ((props[name] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String else { return nil }
            return parseDate(s)
        }

        let priority = schema.priorityProp.flatMap(selectOrStatus).flatMap(parsePriority)
        let due = schema.dueProp.flatMap(date)
        let scheduled = schema.scheduledProp.flatMap(date)?.0
        let top3 = schema.top3Prop.flatMap { (props[$0] as? [String: Any])?["checkbox"] as? Bool } ?? false
        let tag = schema.tagProps.lazy.compactMap(selectOrStatus).first

        return NotionTask(id: id, url: page["url"] as? String, title: title,
                          priority: priority, due: due?.0, dueHasTime: due?.1 ?? false,
                          scheduled: scheduled, top3: top3, tag: tag)
    }

    static func parsePriority(_ raw: String) -> Int? {
        if let c = raw.first(where: \.isNumber), let n = Int(String(c)) {
            return min(3, max(0, n))
        }
        let l = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if l.contains("urgent") || l.contains("critical") || l.contains("紧急") || l.contains("最高") { return 0 }
        if l.contains("high") || l == "高" || l.contains("高优") { return 1 }
        if l.contains("medium") || l.contains("normal") || l.contains("mid") || l == "中" || l.contains("普通") { return 2 }
        if l.contains("low") || l == "低" { return 3 }
        return nil
    }

    /// "2026-11-25" → (当天 0 点, false)；"2026-11-25T18:00:00.000+08:00" → (时刻, true)
    static func parseDate(_ s: String) -> (Date, Bool)? {
        if s.count <= 10 {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s).map { ($0, false) }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return (d, true) }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s).map { ($0, true) }
    }

    // MARK: 每日记录同步（按日期 Upsert）

    func syncDailyLogNow(includeToday: Bool = true, completion: ((Result<DailyLogEntry, Error>) -> Void)? = nil) {
        let cfg = config
        guard cfg.isLogConfigured else {
            completion?(.failure(SyncError.logNotConfigured))
            return
        }
        guard !logSyncing else {
            completion?(.failure(SyncError.busy))
            return
        }
        logSyncing = true
        let pending = model?.pendingDailyLogs() ?? []
        let todayEntry = includeToday ? model?.currentDailyLog() : nil
        Task {
            do {
                var resolved = try await resolveLogSchema(using: cfg)
                for item in pending {
                    resolved = try await upsertDailyLog(item, using: cfg, resolved: resolved)
                    await MainActor.run { self.model?.removePendingDailyLog(day: item.day) }
                }
                let finalEntry: DailyLogEntry
                if let todayEntry {
                    resolved = try await upsertDailyLog(todayEntry, using: cfg, resolved: resolved)
                    finalEntry = todayEntry
                } else if let last = pending.last {
                    finalEntry = last
                } else {
                    finalEntry = await MainActor.run { self.model?.currentDailyLog() } ?? DailyLogEntry(
                        day: "", completed: 0, focusMinutes: 0, internalBreaks: 0, externalBreaks: 0, voided: 0, taskSummary: ""
                    )
                }
                let finalResolved = resolved
                await MainActor.run {
                    if Self.logCacheKey(for: self.config) == Self.logCacheKey(for: cfg) {
                        self.cachedLogSchema = (Self.logCacheKey(for: cfg), finalResolved.schema, finalResolved.useDataSource)
                        self.logDatabaseTitle = finalResolved.schema.databaseTitle
                    }
                    self.lastLogSync = Date()
                    self.lastLogError = nil
                    self.logSyncing = false
                    completion?(.success(finalEntry))
                }
            } catch {
                await MainActor.run {
                    self.lastLogError = error.localizedDescription
                    self.logSyncing = false
                    completion?(.failure(error))
                }
            }
        }
    }

    private func flushPendingLogs(syncTodayIfActive: Bool = false) {
        guard config.isLogConfigured else { return }
        let hasPending = !(model?.pendingDailyLogs().isEmpty ?? true)
        let todayActive = syncTodayIfActive && (model?.stats.hasActivity == true)
        guard hasPending || todayActive else { return }
        syncDailyLogNow(includeToday: todayActive)
    }

    private func syncFocusCompleted(_ entry: DailyLogEntry) {
        guard config.isLogConfigured else { return }
        if logSyncing {
            model?.enqueueDailyLog(entry)
            return
        }
        syncDailyLogNow(includeToday: true)
    }

    private func upsertDailyLog(
        _ entry: DailyLogEntry, using cfg: NotionConfig,
        resolved: (schema: NotionLogSchema, useDataSource: Bool)
    ) async throws -> (schema: NotionLogSchema, useDataSource: Bool) {
        let s = resolved.schema
        let dsID = cfg.trimmedLogDataSourceID
        let dbID = !cfg.trimmedLogDatabaseID.isEmpty ? cfg.trimmedLogDatabaseID : dsID

        var queryBody: [String: Any] = ["page_size": 1]
        if let dateProp = s.dateProp {
            queryBody["filter"] = ["property": dateProp, "date": ["equals": entry.day]]
        } else if let titleProp = s.titleProp {
            queryBody["filter"] = ["property": titleProp, "title": ["equals": entry.day]]
        } else {
            throw SyncError.http(400, "每日记录数据库缺少日期或标题列")
        }

        let queryResult = try await postQuery(dsID: dsID, dbID: dbID, useDataSource: resolved.useDataSource,
                                              token: cfg.trimmedToken, body: queryBody)
        let existingID = ((queryResult["results"] as? [[String: Any]])?.first)?["id"] as? String

        var props: [String: Any] = [:]
        if let p = s.titleProp { props[p] = ["title": [["text": ["content": entry.day]]]] }
        if let p = s.dateProp { props[p] = ["date": ["start": entry.day]] }
        if let p = s.completedProp { props[p] = ["number": entry.completed] }
        if let p = s.focusMinutesProp { props[p] = ["number": entry.focusMinutes] }
        if let p = s.internalProp { props[p] = ["number": entry.internalBreaks] }
        if let p = s.externalProp { props[p] = ["number": entry.externalBreaks] }
        if let p = s.voidedProp { props[p] = ["number": entry.voided] }
        if let p = s.tasksProp {
            let trimmed = String(entry.taskSummary.prefix(1900))
            props[p] = ["rich_text": trimmed.isEmpty ? [] : [["text": ["content": trimmed]]]]
        }

        if let pageID = existingID {
            let body = try JSONSerialization.data(withJSONObject: ["properties": props])
            _ = try await request(method: "PATCH", path: "pages/\(pageID)",
                                  version: "2022-06-28", token: cfg.trimmedToken, body: body)
        } else if resolved.useDataSource && !dsID.isEmpty {
            do {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "parent": ["type": "data_source_id", "data_source_id": dsID],
                    "properties": props,
                ])
                _ = try await request(method: "POST", path: "pages",
                                      version: "2025-09-03", token: cfg.trimmedToken, body: payload)
            } catch SyncError.http(let code, _) where (code == 400 || code == 404) && !dbID.isEmpty {
                let payload = try JSONSerialization.data(withJSONObject: [
                    "parent": ["database_id": dbID],
                    "properties": props,
                ])
                _ = try await request(method: "POST", path: "pages",
                                      version: "2022-06-28", token: cfg.trimmedToken, body: payload)
            }
        } else {
            let payload = try JSONSerialization.data(withJSONObject: [
                "parent": ["database_id": dbID],
                "properties": props,
            ])
            _ = try await request(method: "POST", path: "pages",
                                  version: "2022-06-28", token: cfg.trimmedToken, body: payload)
        }
        return resolved
    }

    // MARK: 回写任务完成状态

    private func taskFinished(_ task: TaskItem) {
        let cfg = config
        guard cfg.writeBack, cfg.isConfigured, task.isNotion, let pageID = task.notionID else { return }
        Task {
            let resolved = try? await resolveSchema(using: cfg)
            let props: [String: Any]
            if let s = resolved?.schema {
                guard let prop = s.statusProp else { return }
                switch s.statusType {
                case "checkbox":
                    props = [prop: ["checkbox": true]]
                case "select":
                    guard let done = s.doneStatus else { return }
                    props = [prop: ["select": ["name": done]]]
                default:
                    guard let done = s.doneStatus else { return }
                    props = [prop: ["status": ["name": done]]]
                }
            } else {
                props = ["Status": ["status": ["name": "Done"]]]
            }

            guard let body = try? JSONSerialization.data(withJSONObject: ["properties": props]) else { return }
            do {
                _ = try await request(method: "PATCH", path: "pages/\(pageID)",
                                      version: "2022-06-28", token: cfg.trimmedToken, body: body)
            } catch SyncError.http(let code, _) {
                await MainActor.run { self.lastError = "回写 Notion 失败（HTTP \(code)）" }
            } catch {
                await MainActor.run { self.lastError = "回写 Notion 失败：\(error.localizedDescription)" }
            }
        }
    }

    enum SyncError: LocalizedError {
        case notConfigured, logNotConfigured, busy, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "还没有填写 Notion 令牌和数据库 ID"
            case .logNotConfigured: return "还没有填写 Notion 令牌和每日记录数据库 ID"
            case .busy: return "正在同步中"
            case .http(let code, let msg):
                if code == 401 { return "令牌无效（401）" }
                if code == 404 { return "找不到数据库：请确认数据库 ID 正确，并在 Notion 里将其授权给这个 integration" }
                return msg
            }
        }
    }
}
