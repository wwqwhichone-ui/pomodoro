// 本机 AI 接口：只监听回环地址 127.0.0.1，所有请求（除 /v1/health）需带
//   Authorization: Bearer <token>
// 端口与令牌在 ~/Library/Application Support/Pomodoro/api.json（权限 600），tools/pomo 命令行会自动读取。
// 接口文档见 docs/API.md。
import Foundation
import Network

struct APIConfig: Codable {
    var port: UInt16 = 47625
    var token: String = APIConfig.randomToken()

    static func randomToken() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

final class APIServer: ObservableObject {
    static let shared = APIServer()

    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    private(set) var config = APIConfig()

    private var listener: NWListener?
    private weak var model: TimerModel?
    private let queue = DispatchQueue(label: "pomodoro.api")
    private let fileURL = AppFiles.dir.appendingPathComponent("api.json")

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let c = try? JSONDecoder().decode(APIConfig.self, from: data) {
            config = c
        } else if let data = try? JSONEncoder().encode(config) {
            AppFiles.writePrivate(data, to: fileURL)
        }
    }

    func start(model: TimerModel) {
        guard listener == nil else { return }
        self.model = model
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: config.port)!)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.running = true; self?.lastError = nil
                    case .failed(let e): self?.running = false; self?.lastError = e.localizedDescription
                    case .cancelled: self?.running = false
                    default: break
                    }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: 连接与 HTTP 解析

    private struct Request {
        var method: String
        var path: [String]
        var headers: [String: String]
        var body: Data
        var json: [String: Any] { ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:] }
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > 1_000_000 || error != nil {
                conn.cancel()
                return
            }
            if let req = Self.parse(buf) {
                DispatchQueue.main.async {
                    self.route(req) { status, obj in
                        self.queue.async { self.send(conn, status: status, obj: obj) }
                    }
                }
            } else if done {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    /// 头部和正文都到齐才返回请求
    private static func parse(_ buf: Data) -> Request? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: buf[..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buf[sep.upperBound...]
        guard body.count >= length else { return nil }
        let rawPath = String(first[1]).split(separator: "?").first.map(String.init) ?? "/"
        let path = rawPath.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        return Request(method: String(first[0]).uppercased(), path: path, headers: headers,
                       body: Data(body.prefix(length)))
    }

    private func send(_ conn: NWConnection, status: Int, obj: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        let reason = [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized",
                      404: "Not Found", 409: "Conflict", 500: "Internal Server Error"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: 路由（在主线程执行）

    private func route(_ req: Request, reply: @escaping (Int, Any) -> Void) {
        let p = req.path
        if p == ["v1", "health"] { return reply(200, ["ok": true, "app": "Pomodoro"]) }
        guard req.headers["authorization"] == "Bearer \(config.token)" else {
            return reply(401, ["error": "缺少或错误的令牌（Authorization: Bearer <token>）"])
        }
        guard let model else { return reply(500, ["error": "应用未就绪"]) }
        guard p.first == "v1" else { return reply(404, ["error": "未知路径"]) }
        let rest = Array(p.dropFirst())

        switch (req.method, rest.first, rest.count) {
        case ("GET", "status", 1):
            reply(200, Self.status(model))

        case ("GET", "tasks", 1):
            reply(200, ["tasks": model.sortedTasks.map { Self.dto($0, model) }])

        case ("POST", "tasks", 1):
            let j = req.json
            guard let title = j["title"] as? String else { return reply(400, ["error": "需要 title"]) }
            let dueCheck = Self.validateDue(j["due"])
            if let err = dueCheck.error { return reply(400, ["error": err]) }
            let due = dueCheck.value
            let task = model.addTask(title: title,
                                     estimate: j["estimate"] as? Int ?? 1,
                                     priority: Self.priority(j["priority"]),
                                     due: due?.0, dueHasTime: due?.1 ?? false,
                                     top3: j["top3"] as? Bool ?? false,
                                     note: j["note"] as? String)
            if let task {
                if j["select"] as? Bool == true { model.selectTask(task.id) }
                reply(201, Self.dto(task, model))
            } else {
                reply(400, ["error": "title 不能为空"])
            }

        case (_, "tasks", 2), (_, "tasks", 3):
            guard let task = Self.find(rest[1], in: model) else { return reply(404, ["error": "找不到任务 \(rest[1])"]) }
            let action = rest.count == 3 ? rest[2] : ""
            switch (req.method, action) {
            case ("GET", ""):
                reply(200, Self.dto(task, model))
            case ("PATCH", ""):
                let j = req.json
                var due: (Date, Bool)?
                if j.keys.contains("due") {
                    let dueCheck = Self.validateDue(j["due"])
                    if let err = dueCheck.error { return reply(400, ["error": err]) }
                    due = dueCheck.value
                }
                model.updateTask(task.id) { t in
                    if let v = j["title"] as? String, !v.isEmpty { t.title = v }
                    if let v = j["estimate"] as? Int { t.estimate = v }
                    if j.keys.contains("priority") { t.priority = Self.priority(j["priority"]) }
                    if j.keys.contains("due") { t.due = due?.0; t.dueHasTime = due.map { $0.1 } }
                    if let v = j["top3"] as? Bool { t.top3 = v ? true : nil }
                    if let v = j["note"] as? String { t.note = v }
                    if let v = j["finished"] as? Bool { t.finished = v }
                }
                reply(200, Self.dto(model.tasks.first { $0.id == task.id } ?? task, model))
            case ("DELETE", ""):
                model.removeTask(task.id)
                reply(200, ["ok": true])
            case ("POST", "select"):
                model.selectTask(task.id)
                reply(200, Self.dto(task, model))
            case ("POST", "complete"):
                if !task.finished { model.toggleFinished(task.id) }
                reply(200, Self.dto(model.tasks.first { $0.id == task.id } ?? task, model))
            default:
                reply(404, ["error": "未知操作"])
            }

        case ("POST", "timer", 2):
            switch rest[1] {
            case "start": model.start()
            case "pause": model.pause()
            case "toggle": model.toggle()
            case "reset": model.reset()
            case "skip": model.skip()
            case "phase":
                let map: [String: Phase] = ["focus": .focus, "short": .shortBreak, "shortBreak": .shortBreak,
                                            "long": .longBreak, "longBreak": .longBreak]
                guard let ph = (req.json["phase"] as? String).flatMap({ map[$0] }) else {
                    return reply(400, ["error": "phase 取值：focus / short / long"])
                }
                model.select(ph)
            default: return reply(404, ["error": "未知计时操作"])
            }
            reply(200, Self.status(model))

        case ("POST", "interruptions", 1):
            let kind = req.json["kind"] as? String ?? "internal"
            guard model.phase == .focus else { return reply(409, ["error": "只能在专注阶段记录打断"]) }
            if req.json["undo"] as? Bool == true {
                guard model.undoInterruption(internal: kind != "external") else {
                    return reply(409, ["error": "这个番茄里没有可撤销的\(kind == "external" ? "外部" : "内部")打断"])
                }
            } else {
                model.logInterruption(internal: kind != "external")
            }
            reply(200, Self.status(model))

        case ("POST", "stats", 2) where rest[1] == "reset":
            model.resetToday()
            reply(200, Self.status(model))

        case ("POST", "notion", 2) where rest[1] == "sync":
            NotionSync.shared.sync { result in
                switch result {
                case .success(let n): reply(200, ["ok": true, "count": n, "tasks": model.sortedTasks.map { Self.dto($0, model) }])
                case .failure(let e): reply(409, ["ok": false, "error": e.localizedDescription])
                }
            }

        case ("POST", "notion", 2) where rest[1] == "log-today":
            NotionSync.shared.syncDailyLogNow(includeToday: true) { result in
                switch result {
                case .success(let entry):
                    reply(200, [
                        "ok": true,
                        "day": entry.day,
                        "completed": entry.completed,
                        "focusMinutes": entry.focusMinutes,
                        "internalInterruptions": entry.internalBreaks,
                        "externalInterruptions": entry.externalBreaks,
                        "voided": entry.voided,
                        "tasks": entry.taskSummary,
                    ])
                case .failure(let e):
                    reply(409, ["ok": false, "error": e.localizedDescription])
                }
            }

        default:
            reply(404, ["error": "未知路径，见 docs/API.md"])
        }
    }

    // MARK: 序列化

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func status(_ m: TimerModel) -> [String: Any] {
        var s: [String: Any] = [
            "phase": m.phase.rawValue,
            "phaseTitle": m.phase.title,
            "running": m.isRunning,
            "paused": !m.isRunning && m.hasStarted,
            "remainingSeconds": Int(m.remaining.rounded(.up)),
            "remaining": m.timeText,
            "totalSeconds": Int(m.total),
            "streak": m.streak,
            "longBreakEvery": m.longEvery,
            "today": [
                "completed": m.stats.completed,
                "focusMinutes": Int(m.stats.focusSeconds / 60),
                "voided": m.stats.voided,
                "internalInterruptions": m.stats.internalBreaks,
                "externalInterruptions": m.stats.externalBreaks,
            ],
            "session": ["internal": m.sessionInternal, "external": m.sessionExternal],
        ]
        if m.isRunning { s["endsAt"] = iso.string(from: m.projectedEnd) }
        if let t = m.currentTask { s["currentTask"] = dto(t, m) }
        return s
    }

    private static func dto(_ t: TaskItem, _ m: TimerModel) -> [String: Any] {
        var d: [String: Any] = [
            "id": t.id.uuidString,
            "title": t.title,
            "estimate": t.estimate,
            "done": t.done,
            "finished": t.finished,
            "current": t.id == m.currentTaskID,
            "source": t.source ?? "local",
            "top3": t.isTop3,
        ]
        if let p = t.priority { d["priority"] = "P\(p)" }
        if let due = t.due { d["due"] = t.dueHasTime == true ? iso.string(from: due) : ymd.string(from: due) }
        if let ddl = DDL.describe(t) { d["ddl"] = ddl.text }
        if let s = t.scheduled { d["scheduled"] = ymd.string(from: s) }
        if let v = t.note { d["note"] = v }
        if let v = t.tag { d["tag"] = v }
        if let v = t.notionURL { d["notionUrl"] = v }
        return d
    }

    /// 按完整 UUID、UUID 前缀，或排序后的序号（1 起）查找任务
    private static func find(_ key: String, in m: TimerModel) -> TaskItem? {
        let sorted = m.sortedTasks
        if let n = Int(key), n >= 1, n <= sorted.count { return sorted[n - 1] }
        let k = key.lowercased()
        let hits = sorted.filter { $0.id.uuidString.lowercased().hasPrefix(k) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// "P1" / "p1" / 1 → 1
    private static func priority(_ v: Any?) -> Int? {
        if let n = v as? Int { return min(3, max(0, n)) }
        if let s = v as? String, let c = s.first(where: \.isNumber), let n = Int(String(c)) { return min(3, n) }
        return nil
    }

    private static func validateDue(_ raw: Any?) -> (value: (Date, Bool)?, error: String?) {
        guard let raw, !(raw is NSNull) else { return (nil, nil) }
        guard let s = raw as? String else { return (nil, "due 需要是日期字符串") }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        guard let parsed = parseDue(trimmed) else {
            return (nil, "due 日期格式无效（支持 2026-11-25、11-25、明天 或 ISO 8601）")
        }
        return (parsed, nil)
    }

    /// "2026-11-25" / "11-25" / "明天" / ISO 时刻
    private static func parseDue(_ s: String) -> (Date, Bool)? {
        if s.contains("T"), let d = NotionSync.parseDate(s) { return d }
        return TimerModel.parseDay(s).map { ($0, false) }
    }
}
