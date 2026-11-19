const http = require("http");
const crypto = require("crypto");
const path = require("path");
const { getDataDir, readJSON, writeJSON } = require("./store");
const { Phase, parseDay, localDayString } = require("./model");
const { parseNotionDate } = require("./notion");

function randomToken() {
  return crypto.randomBytes(32).toString("hex");
}

function parsePriorityInput(v) {
  if (typeof v === "number" && Number.isFinite(v)) {
    return Math.min(3, Math.max(0, Math.trunc(v)));
  }
  if (typeof v === "string") {
    const m = v.match(/[0-9]/);
    if (m) return Math.min(3, Math.max(0, Number(m[0])));
  }
  return null;
}

function parseDueInput(s) {
  if (s.includes("T")) {
    const d = parseNotionDate(s);
    if (!d) return null;
    return { due: s, dueHasTime: true };
  }
  const d = parseDay(s);
  if (!d) return null;
  return { due: localDayString(d), dueHasTime: false };
}

function validateDue(raw) {
  if (raw === undefined || raw === null) return { value: null, error: null };
  if (typeof raw !== "string") return { value: null, error: "due 需要是日期字符串或 null" };
  const trimmed = raw.trim();
  if (!trimmed) return { value: null, error: null };
  const parsed = parseDueInput(trimmed);
  if (!parsed) {
    return { value: null, error: "due 日期格式无效（支持 2026-11-25、11-25、明天 或 ISO 8601）" };
  }
  return { value: parsed, error: null };
}

function findTask(ref, model) {
  const sorted = model.sortedTasks;
  if (/^\d+$/.test(ref)) {
    const n = Number(ref);
    if (n >= 1 && n <= sorted.length) return sorted[n - 1];
  }
  const k = ref.toLowerCase();
  const hits = sorted.filter((t) => t.id.toLowerCase().startsWith(k));
  return hits.length === 1 ? hits[0] : null;
}

class APIServer {
  constructor({ dataDir = null, model, notion = null } = {}) {
    this.dataDir = getDataDir(dataDir);
    this.filePath = path.join(this.dataDir, "api.json");
    this.model = model;
    this.notion = notion;

    const existing = readJSON(this.filePath, null);
    if (existing && typeof existing.token === "string" && existing.token) {
      this.config = {
        port: Number(existing.port) || 47625,
        token: existing.token,
      };
    } else {
      this.config = { port: 47625, token: randomToken() };
      writeJSON(this.filePath, this.config, 0o600);
    }

    this.server = null;
    this.running = false;
    this.lastError = null;
    this.boundPort = this.config.port;
  }

  getStatus() {
    return {
      running: this.running,
      port: this.boundPort,
      token: this.config.token,
      lastError: this.lastError,
    };
  }

  start(overridePort = null) {
    if (this.server) return Promise.resolve(this.boundPort);
    const envPort = process.env.POMODORO_PORT !== undefined ? Number(process.env.POMODORO_PORT) : null;
    const listenPort = overridePort !== null ? overridePort : (Number.isFinite(envPort) ? envPort : this.config.port);

    return new Promise((resolve, reject) => {
      const server = http.createServer((req, res) => {
        this._handle(req, res).catch((err) => {
          this._send(res, 500, { error: err?.message || "内部错误" });
        });
      });

      server.on("error", (err) => {
        this.running = false;
        this.lastError = err.message;
        if (!this.server) reject(err);
      });

      server.listen(listenPort, "127.0.0.1", () => {
        this.server = server;
        this.running = true;
        this.lastError = null;
        this.boundPort = server.address().port;
        resolve(this.boundPort);
      });
    });
  }

  stop() {
    return new Promise((resolve) => {
      if (!this.server) {
        this.running = false;
        return resolve();
      }
      const srv = this.server;
      this.server = null;
      this.running = false;
      srv.close(() => resolve());
    });
  }

  _readBody(req) {
    return new Promise((resolve, reject) => {
      const chunks = [];
      let total = 0;
      req.on("data", (chunk) => {
        total += chunk.length;
        if (total > 1000000) {
          req.destroy();
          reject(new Error("请求体过大"));
          return;
        }
        chunks.push(chunk);
      });
      req.on("end", () => {
        const raw = Buffer.concat(chunks).toString("utf8");
        if (!raw.trim()) return resolve({});
        try {
          const parsed = JSON.parse(raw);
          resolve(parsed && typeof parsed === "object" ? parsed : {});
        } catch {
          resolve({});
        }
      });
      req.on("error", reject);
    });
  }

  _send(res, status, obj) {
    const body = JSON.stringify(obj, null, 2);
    res.writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Length": Buffer.byteLength(body, "utf8"),
      Connection: "close",
    });
    res.end(body);
  }

  async _handle(req, res) {
    const method = (req.method || "GET").toUpperCase();
    const rawUrl = (req.url || "/").split("?")[0];
    const parts = rawUrl.split("/").filter(Boolean).map((s) => {
      try {
        return decodeURIComponent(s);
      } catch {
        return s;
      }
    });

    if (method === "GET" && parts.length === 2 && parts[0] === "v1" && parts[1] === "health") {
      return this._send(res, 200, { ok: true, app: "Pomodoro" });
    }

    if (req.headers.authorization !== `Bearer ${this.config.token}`) {
      return this._send(res, 401, { error: "缺少或错误的令牌（Authorization: Bearer <token>）" });
    }

    if (!this.model) return this._send(res, 500, { error: "应用未就绪" });
    if (parts[0] !== "v1") return this._send(res, 404, { error: "未知路径" });

    const rest = parts.slice(1);
    const json = method === "GET" || method === "DELETE" ? {} : await this._readBody(req);

    if (method === "GET" && rest[0] === "status" && rest.length === 1) {
      return this._send(res, 200, this.model.getStatusDTO());
    }

    if (method === "GET" && rest[0] === "tasks" && rest.length === 1) {
      return this._send(res, 200, { tasks: this.model.sortedTasks.map((t) => this.model.taskDTO(t)) });
    }

    if (method === "POST" && rest[0] === "tasks" && rest.length === 1) {
      if (typeof json.title !== "string") return this._send(res, 400, { error: "需要 title" });
      const dueCheck = validateDue(json.due);
      if (dueCheck.error) return this._send(res, 400, { error: dueCheck.error });
      const task = this.model.addTask({
        title: json.title,
        estimate: typeof json.estimate === "number" ? json.estimate : 1,
        priority: parsePriorityInput(json.priority),
        due: dueCheck.value?.due || null,
        dueHasTime: dueCheck.value?.dueHasTime || false,
        top3: json.top3 === true,
        note: typeof json.note === "string" ? json.note : null,
      });
      if (!task) return this._send(res, 400, { error: "title 不能为空" });
      if (json.select === true) this.model.selectTask(task.id);
      const updated = this.model.tasks.find((t) => t.id === task.id) || task;
      return this._send(res, 201, this.model.taskDTO(updated));
    }

    if (rest[0] === "tasks" && (rest.length === 2 || rest.length === 3)) {
      const task = findTask(rest[1], this.model);
      if (!task) return this._send(res, 404, { error: `找不到任务 ${rest[1]}` });
      const action = rest.length === 3 ? rest[2] : "";

      if (method === "GET" && action === "") {
        return this._send(res, 200, this.model.taskDTO(task));
      }
      if (method === "PATCH" && action === "") {
        let duePatch;
        const hasDue = Object.prototype.hasOwnProperty.call(json, "due");
        if (hasDue) {
          const dueCheck = validateDue(json.due);
          if (dueCheck.error) return this._send(res, 400, { error: dueCheck.error });
          duePatch = dueCheck.value;
        }
        const updated = this.model.updateTask(task.id, (t) => {
          if (typeof json.title === "string" && json.title) t.title = json.title;
          if (typeof json.estimate === "number") t.estimate = json.estimate;
          if (Object.prototype.hasOwnProperty.call(json, "priority")) {
            const p = parsePriorityInput(json.priority);
            if (p !== null) t.priority = p;
            else delete t.priority;
          }
          if (hasDue) {
            if (duePatch) {
              t.due = duePatch.due;
              t.dueHasTime = duePatch.dueHasTime;
            } else {
              delete t.due;
              delete t.dueHasTime;
            }
          }
          if (typeof json.top3 === "boolean") {
            if (json.top3) t.top3 = true;
            else delete t.top3;
          }
          if (typeof json.note === "string") t.note = json.note;
          if (typeof json.finished === "boolean") t.finished = json.finished;
        });
        return this._send(res, 200, this.model.taskDTO(updated || task));
      }
      if (method === "DELETE" && action === "") {
        this.model.removeTask(task.id);
        return this._send(res, 200, { ok: true });
      }
      if (method === "POST" && action === "select") {
        this.model.selectTask(task.id);
        const cur = this.model.tasks.find((t) => t.id === task.id) || task;
        return this._send(res, 200, this.model.taskDTO(cur));
      }
      if (method === "POST" && action === "complete") {
        if (!task.finished) this.model.toggleFinished(task.id);
        const cur = this.model.tasks.find((t) => t.id === task.id) || task;
        return this._send(res, 200, this.model.taskDTO(cur));
      }
      return this._send(res, 404, { error: "未知操作" });
    }

    if (method === "POST" && rest[0] === "timer" && rest.length === 2) {
      const cmd = rest[1];
      if (cmd === "start") this.model.start();
      else if (cmd === "pause") this.model.pause();
      else if (cmd === "toggle") this.model.toggle();
      else if (cmd === "reset") this.model.reset();
      else if (cmd === "skip") this.model.skip();
      else if (cmd === "phase") {
        const map = {
          focus: Phase.focus,
          short: Phase.shortBreak,
          shortBreak: Phase.shortBreak,
          long: Phase.longBreak,
          longBreak: Phase.longBreak,
        };
        const ph = typeof json.phase === "string" ? map[json.phase] : null;
        if (!ph) return this._send(res, 400, { error: "phase 取值：focus / short / long" });
        this.model.selectPhase(ph);
      } else {
        return this._send(res, 404, { error: "未知计时操作" });
      }
      return this._send(res, 200, this.model.getStatusDTO());
    }

    if (method === "POST" && rest[0] === "interruptions" && rest.length === 1) {
      const kind = typeof json.kind === "string" ? json.kind : "internal";
      if (this.model.phase !== Phase.focus) {
        return this._send(res, 409, { error: "只能在专注阶段记录打断" });
      }
      if (json.undo === true) {
        if (!this.model.undoInterruption(kind !== "external")) {
          return this._send(res, 409, {
            error: `这个番茄里没有可撤销的${kind === "external" ? "外部" : "内部"}打断`,
          });
        }
      } else {
        this.model.logInterruption(kind !== "external");
      }
      return this._send(res, 200, this.model.getStatusDTO());
    }

    if (method === "POST" && rest[0] === "stats" && rest[1] === "reset" && rest.length === 2) {
      this.model.resetToday();
      return this._send(res, 200, this.model.getStatusDTO());
    }

    if (method === "POST" && rest[0] === "notion" && rest[1] === "sync" && rest.length === 2) {
      if (!this.notion) return this._send(res, 500, { ok: false, error: "Notion 同步未就绪" });
      try {
        const count = await this.notion.sync();
        return this._send(res, 200, {
          ok: true,
          count,
          tasks: this.model.sortedTasks.map((t) => this.model.taskDTO(t)),
        });
      } catch (err) {
        return this._send(res, 409, { ok: false, error: err?.message || String(err) });
      }
    }

    return this._send(res, 404, { error: "未知路径，见 docs/API.md" });
  }
}

module.exports = {
  APIServer,
  validateDue,
  findTask,
};
