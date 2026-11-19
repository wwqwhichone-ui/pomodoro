// Notion 同步：自动探测任意任务数据库结构，拉取「今天要做 / 近期到期 / 已逾期 / 置顶」且未完成的任务。
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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        dataSourceID = try c.decodeIfPresent(String.self, forKey: .dataSourceID) ?? ""
        databaseID = try c.decodeIfPresent(String.self, forKey: .databaseID) ?? ""
        writeBack = try c.decodeIfPresent(Bool.self, forKey: .writeBack) ?? false
        let days = try c.decodeIfPresent(Int.self, forKey: .lookaheadDays) ?? 7
        lookaheadDays = min(90, max(1, days))
    }

    var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDataSourceID: String { dataSourceID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDatabaseID: String { databaseID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var targetInput: String { !trimmedDataSourceID.isEmpty ? trimmedDataSourceID : trimmedDatabaseID }
    var isConfigured: Bool { !trimmedToken.isEmpty && (!trimmedDataSourceID.isEmpty || !trimmedDatabaseID.isEmpty) }
}

/// 从任意 Notion 数据库自动探测出的字段映射
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
    var tagProps: [String] = []

    static func detect(from json: [String: Any]) -> NotionSchema {
        var schema = NotionSchema()

        if let titleArr = json["title"] as? [[String: Any]] {
            let t = titleArr.compactMap { $0["plain_text"] as? String }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { schema.databaseTitle = t }
        }

        guard let props = json["properties"] as? [String: [String: Any]] else { return schema }
        let entries = props.map { (name: $0.key, prop: $0.value, type: ($0.value["type"] as? String ?? "")) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var used = Set<String>()

        // 1. 标题列（Notion 数据库必有且只有一个 title 列）
        if let titleEntry = entries.first(where: { $0.type == "title" }) {
            schema.titleProp = titleEntry.name
            used.insert(titleEntry.name)
        }

        // 2. 状态列：status -> select -> checkbox
        let statusKeywords = ["status", "状态", "state", "进度"]
        let doneKeywords = ["done", "completed", "complete", "finished", "已完成", "完成"]
        let closedKeywords = doneKeywords + ["archived", "cancelled", "canceled", "已归档", "已取消"]

        if let stEntry = findMatching(entries, type: "status", keywords: statusKeywords, excluding: used)
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
        } else if let selEntry = findMatching(entries, type: "select", keywords: statusKeywords, excluding: used) {
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
        } else if let chkEntry = findMatching(entries, type: "checkbox", keywords: doneKeywords, excluding: used) {
            schema.statusProp = chkEntry.name
            schema.statusType = "checkbox"
            used.insert(chkEntry.name)
        }

        // 3. 截止日期列（避开 scheduled / do date / 计划 避免子串误判）
        let dueKeywords = ["due date", "due", "ddl", "deadline", "截止日期", "截止时间", "截止", "date", "日期"]
        let scheduledGuard = ["scheduled", "do date", "plan", "计划", "开始"]
        if let due = findMatching(entries, type: "date", keywords: dueKeywords, excluding: used,
                                  avoidInSubstring: scheduledGuard) {
            schema.dueProp = due.name
            used.insert(due.name)
        }

        // 4. 计划日期列
        let scheduledKeywords = ["scheduled date", "scheduled", "do date", "plan date", "计划日期", "安排日期", "计划", "开始日期"]
        if let sched = findMatching(entries, type: "date", keywords: scheduledKeywords, excluding: used) {
            schema.scheduledProp = sched.name
            used.insert(sched.name)
        }

        // 5. 优先级列
        let priorityKeywords = ["priority", "优先级", "紧急", "级别"]
        if let prio = findMatching(entries, types: ["select", "status"], keywords: priorityKeywords, excluding: used) {
            schema.priorityProp = prio.name
            used.insert(prio.name)
        }

        // 6. 置顶 / Top 3 列
        let top3Keywords = ["top 3", "top3", "focus", "pinned", "important", "重点", "置顶", "今日重点"]
        if let top3 = findMatching(entries, type: "checkbox", keywords: top3Keywords, excluding: used) {
            schema.top3Prop = top3.name
            used.insert(top3.name)
        }

        // 7. 标签 / 课程 / 分类列（按关键词优先顺序收集）
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

    private typealias PropEntry = (name: String, prop: [String: Any], type: String)

    private static func findMatching(_ entries: [PropEntry], type: String, keywords: [String],
                                     excluding used: Set<String>, avoidInSubstring: [String] = []) -> PropEntry? {
        findMatching(entries, types: [type], keywords: keywords, excluding: used, avoidInSubstring: avoidInSubstring)
    }

    private static func findMatching(_ entries: [PropEntry], types: [String], keywords: [String],
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

    private weak var model: TimerModel?
    private var timer: Timer?
    private let fileURL = AppFiles.dir.appendingPathComponent("notion.json")
    private var cachedSchema: (key: String, schema: NotionSchema, useDataSource: Bool)?

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let c = try? JSONDecoder().decode(NotionConfig.self, from: data) {
            config = c
        }
    }

    private static func cacheKey(for c: NotionConfig) -> String {
        "\(c.trimmedToken)|\(c.trimmedDataSourceID)|\(c.trimmedDatabaseID)"
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

    /// 启动：立即同步一次，之后每 30 分钟一次（同时负责跨天检查）
    func start(model: TimerModel) {
        guard self.model == nil else { return }
        self.model = model
        model.onTaskFinished = { [weak self] task in self?.taskFinished(task) }
        sync()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.model?.refreshDay()
            self?.sync()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func update(_ change: (inout NotionConfig) -> Void) {
        let oldKey = Self.cacheKey(for: config)
        change(&config)
        config.lookaheadDays = min(90, max(1, config.lookaheadDays))
        if let data = try? JSONEncoder().encode(config) { AppFiles.writePrivate(data, to: fileURL) }
        if Self.cacheKey(for: config) != oldKey {
            cachedSchema = nil
            databaseTitle = nil
        }
    }

    // MARK: 拉取

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

    private func resolveSchema(using cfg: NotionConfig) async throws -> (schema: NotionSchema, useDataSource: Bool) {
        let key = Self.cacheKey(for: cfg)
        let existing = await MainActor.run { self.cachedSchema }
        if let existing, existing.key == key {
            return (existing.schema, existing.useDataSource)
        }

        let dsID = cfg.trimmedDataSourceID
        let dbID = !cfg.trimmedDatabaseID.isEmpty ? cfg.trimmedDatabaseID : dsID

        if !dsID.isEmpty {
            do {
                let json = try await request(method: "GET", path: "data_sources/\(dsID)",
                                             version: "2025-09-03", token: cfg.trimmedToken)
                return (NotionSchema.detect(from: json), true)
            } catch SyncError.http(let code, _) where (code == 400 || code == 404) && !dbID.isEmpty {
                let json = try await request(method: "GET", path: "databases/\(dbID)",
                                             version: "2022-06-28", token: cfg.trimmedToken)
                return (NotionSchema.detect(from: json), false)
            }
        } else {
            let json = try await request(method: "GET", path: "databases/\(dbID)",
                                         version: "2022-06-28", token: cfg.trimmedToken)
            return (NotionSchema.detect(from: json), false)
        }
    }

    private func fetchAll(using cfg: NotionConfig, schema: NotionSchema, useDataSource: Bool) async throws -> [NotionTask] {
        var all: [NotionTask] = []
        var cursor: String?
        repeat {
            let (results, next) = try await queryPage(using: cfg, schema: schema, useDataSource: useDataSource, cursor: cursor)
            all += results.compactMap { Self.parse($0, schema: schema) }
            cursor = next
        } while cursor != nil && all.count < 500
        return all
    }

    private func queryPage(using cfg: NotionConfig, schema: NotionSchema,
                           useDataSource: Bool, cursor: String?) async throws -> ([[String: Any]], String?) {
        var body = Self.filterBody(lookahead: cfg.lookaheadDays, schema: schema)
        if let cursor { body["start_cursor"] = cursor }
        let payload = try JSONSerialization.data(withJSONObject: body)

        let dsID = cfg.trimmedDataSourceID
        let dbID = !cfg.trimmedDatabaseID.isEmpty ? cfg.trimmedDatabaseID : dsID

        let json: [String: Any]
        if useDataSource && !dsID.isEmpty {
            do {
                json = try await request(method: "POST", path: "data_sources/\(dsID)/query",
                                         version: "2025-09-03", token: cfg.trimmedToken, body: payload)
            } catch SyncError.http(let code, _) where (code == 400 || code == 404) && !dbID.isEmpty {
                json = try await request(method: "POST", path: "databases/\(dbID)/query",
                                         version: "2022-06-28", token: cfg.trimmedToken, body: payload)
            }
        } else {
            json = try await request(method: "POST", path: "databases/\(dbID)/query",
                                     version: "2022-06-28", token: cfg.trimmedToken, body: payload)
        }
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
    static func filterBody(lookahead: Int, schema: NotionSchema) -> [String: Any] {
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

    static func parse(_ page: [String: Any], schema: NotionSchema) -> NotionTask? {
        guard let id = page["id"] as? String,
              let props = page["properties"] as? [String: Any] else { return nil }

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

    // MARK: 回写

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
        case notConfigured, busy, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "还没有填写 Notion 令牌和数据库 ID"
            case .busy: return "正在同步中"
            case .http(let code, let msg):
                if code == 401 { return "令牌无效（401）" }
                if code == 404 { return "找不到数据库：请确认数据库 ID 正确，并在 Notion 里将其授权给这个 integration" }
                return msg
            }
        }
    }
}
