const { EventEmitter } = require("events");
const path = require("path");
const { getDataDir, readJSON, writeJSON } = require("./store");
const { localDayString, parseStoredDate } = require("./model");

function normalizeConfig(raw = {}) {
  const days = Number(raw.lookaheadDays);
  return {
    token: typeof raw.token === "string" ? raw.token : "",
    dataSourceID: typeof raw.dataSourceID === "string" ? raw.dataSourceID : "",
    databaseID: typeof raw.databaseID === "string" ? raw.databaseID : "",
    writeBack: Boolean(raw.writeBack),
    lookaheadDays: Number.isFinite(days) ? Math.min(90, Math.max(1, Math.round(days))) : 7,
  };
}

function configHelpers(cfg) {
  const trimmedToken = cfg.token.trim();
  const trimmedDataSourceID = cfg.dataSourceID.trim();
  const trimmedDatabaseID = cfg.databaseID.trim();
  const targetInput = trimmedDataSourceID || trimmedDatabaseID;
  const isConfigured = Boolean(trimmedToken && (trimmedDataSourceID || trimmedDatabaseID));
  return { trimmedToken, trimmedDataSourceID, trimmedDatabaseID, targetInput, isConfigured };
}

function extractID(raw) {
  const trimmed = String(raw || "").trim();
  if (!trimmed) return "";
  const base = trimmed.split(/[?#]/)[0] || trimmed;
  const matches = base.match(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32}/g);
  if (!matches || matches.length === 0) return trimmed;
  const hex = matches[matches.length - 1].replace(/-/g, "").toLowerCase();
  if (hex.length !== 32) return trimmed;
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function findMatching(entries, types, keywords, used, avoidInSubstring = []) {
  const candidates = entries.filter((e) => types.includes(e.type) && !used.has(e.name));
  for (const kw of keywords) {
    const exact = candidates.find((e) => e.name.trim().toLowerCase() === kw);
    if (exact) return exact;
  }
  for (const kw of keywords) {
    const sub = candidates.find((e) => {
      const l = e.name.trim().toLowerCase();
      if (!l.includes(kw)) return false;
      return !avoidInSubstring.some((guard) => l.includes(guard));
    });
    if (sub) return sub;
  }
  return null;
}

const NotionSchema = {
  detect(json) {
    const schema = {
      databaseTitle: null,
      titleProp: null,
      statusProp: null,
      statusType: null,
      openStatuses: [],
      doneStatus: null,
      dueProp: null,
      scheduledProp: null,
      priorityProp: null,
      top3Prop: null,
      tagProps: [],
    };

    if (Array.isArray(json?.title)) {
      const t = json.title.map((x) => x?.plain_text || "").join("").trim();
      if (t) schema.databaseTitle = t;
    }

    const props = json?.properties;
    if (!props || typeof props !== "object") return schema;

    const entries = Object.entries(props)
      .map(([name, prop]) => ({ name, prop: prop || {}, type: prop?.type || "" }))
      .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "accent" }));
    const used = new Set();

    // 1. 标题列
    const titleEntry = entries.find((e) => e.type === "title");
    if (titleEntry) {
      schema.titleProp = titleEntry.name;
      used.add(titleEntry.name);
    }

    // 2. 状态列：status -> select -> checkbox
    const statusKeywords = ["status", "状态", "state", "进度"];
    const doneKeywords = ["done", "completed", "complete", "finished", "已完成", "完成"];
    const closedKeywords = [...doneKeywords, "archived", "cancelled", "canceled", "已归档", "已取消"];

    const stEntry =
      findMatching(entries, ["status"], statusKeywords, used) ||
      entries.find((e) => e.type === "status" && !used.has(e.name));

    if (stEntry) {
      schema.statusProp = stEntry.name;
      schema.statusType = "status";
      used.add(stEntry.name);
      const stObj = stEntry.prop.status || {};
      const options = Array.isArray(stObj.options) ? stObj.options : [];
      const allNames = options.map((o) => o?.name).filter(Boolean);
      const groups = Array.isArray(stObj.groups) ? stObj.groups : [];
      const completeIDs = new Set();
      for (const g of groups) {
        const gName = String(g?.name || "").trim().toLowerCase();
        if (gName === "complete" || gName === "done" || gName === "已完成") {
          for (const id of g?.option_ids || []) completeIDs.add(id);
        }
      }
      if (completeIDs.size > 0) {
        const completeNames = options.filter((o) => completeIDs.has(o?.id)).map((o) => o?.name).filter(Boolean);
        schema.doneStatus =
          completeNames.find((n) => {
            const l = n.trim().toLowerCase();
            return l === "done" || l === "已完成";
          }) || completeNames[0] || null;
        schema.openStatuses = options.filter((o) => !completeIDs.has(o?.id)).map((o) => o?.name).filter(Boolean);
      } else {
        schema.doneStatus =
          allNames.find((n) => {
            const l = n.trim().toLowerCase();
            return doneKeywords.some((k) => l === k || l.includes(k));
          }) || null;
        schema.openStatuses = allNames.filter((n) => {
          const l = n.trim().toLowerCase();
          return !closedKeywords.some((k) => l === k || l.includes(k));
        });
      }
    } else {
      const selEntry = findMatching(entries, ["select"], statusKeywords, used);
      if (selEntry) {
        schema.statusProp = selEntry.name;
        schema.statusType = "select";
        used.add(selEntry.name);
        const options = Array.isArray(selEntry.prop.select?.options) ? selEntry.prop.select.options : [];
        const allNames = options.map((o) => o?.name).filter(Boolean);
        schema.doneStatus =
          allNames.find((n) => {
            const l = n.trim().toLowerCase();
            return doneKeywords.some((k) => l === k || l.includes(k));
          }) || null;
        schema.openStatuses = allNames.filter((n) => {
          const l = n.trim().toLowerCase();
          return !closedKeywords.some((k) => l === k || l.includes(k));
        });
      } else {
        const chkEntry = findMatching(entries, ["checkbox"], doneKeywords, used);
        if (chkEntry) {
          schema.statusProp = chkEntry.name;
          schema.statusType = "checkbox";
          used.add(chkEntry.name);
        }
      }
    }

    // 3. 截止日期列
    const dueKeywords = ["due date", "due", "ddl", "deadline", "截止日期", "截止时间", "截止", "date", "日期"];
    const scheduledGuard = ["scheduled", "do date", "plan", "计划", "开始"];
    const dueEntry = findMatching(entries, ["date"], dueKeywords, used, scheduledGuard);
    if (dueEntry) {
      schema.dueProp = dueEntry.name;
      used.add(dueEntry.name);
    }

    // 4. 计划日期列
    const scheduledKeywords = ["scheduled date", "scheduled", "do date", "plan date", "计划日期", "安排日期", "计划", "开始日期"];
    const schedEntry = findMatching(entries, ["date"], scheduledKeywords, used);
    if (schedEntry) {
      schema.scheduledProp = schedEntry.name;
      used.add(schedEntry.name);
    }

    // 5. 优先级列
    const priorityKeywords = ["priority", "优先级", "紧急", "级别"];
    const prioEntry = findMatching(entries, ["select", "status"], priorityKeywords, used);
    if (prioEntry) {
      schema.priorityProp = prioEntry.name;
      used.add(prioEntry.name);
    }

    // 6. 置顶列
    const top3Keywords = ["top 3", "top3", "focus", "pinned", "important", "重点", "置顶", "今日重点"];
    const top3Entry = findMatching(entries, ["checkbox"], top3Keywords, used);
    if (top3Entry) {
      schema.top3Prop = top3Entry.name;
      used.add(top3Entry.name);
    }

    // 7. 标签列
    const tagKeywords = ["course", "category", "project", "area", "tag", "tags", "课程", "分类", "项目", "标签"];
    for (const kw of tagKeywords) {
      for (const e of entries) {
        if ((e.type === "select" || e.type === "multi_select") && !used.has(e.name)) {
          const l = e.name.trim().toLowerCase();
          if (l === kw || l.includes(kw)) {
            schema.tagProps.push(e.name);
            used.add(e.name);
          }
        }
      }
    }

    return schema;
  },
};

function filterBody(lookahead, schema) {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const until = new Date(today.getFullYear(), today.getMonth(), today.getDate() + lookahead);
  const todayStr = localDayString(today);
  const untilStr = localDayString(until);

  const andFilters = [];
  if (schema.statusProp) {
    if (schema.statusType === "checkbox") {
      andFilters.push({ property: schema.statusProp, checkbox: { equals: false } });
    } else if (schema.statusType === "select") {
      if (schema.openStatuses.length > 0) {
        const ors = schema.openStatuses.map((s) => ({ property: schema.statusProp, select: { equals: s } }));
        andFilters.push(ors.length === 1 ? ors[0] : { or: ors });
      }
    } else if (schema.openStatuses.length > 0) {
      const ors = schema.openStatuses.map((s) => ({ property: schema.statusProp, status: { equals: s } }));
      andFilters.push(ors.length === 1 ? ors[0] : { or: ors });
    }
  }

  const relevant = [];
  if (schema.scheduledProp) {
    relevant.push({ property: schema.scheduledProp, date: { equals: todayStr } });
  }
  if (schema.dueProp) {
    relevant.push({ property: schema.dueProp, date: { on_or_before: untilStr } });
  }
  if (schema.top3Prop) {
    relevant.push({ property: schema.top3Prop, checkbox: { equals: true } });
  }
  if (relevant.length > 0) {
    andFilters.push(relevant.length === 1 ? relevant[0] : { or: relevant });
  }

  const body = { page_size: 100 };
  if (andFilters.length === 1) body.filter = andFilters[0];
  else if (andFilters.length > 1) body.filter = { and: andFilters };
  if (schema.dueProp) {
    body.sorts = [{ property: schema.dueProp, direction: "ascending" }];
  }
  return body;
}

function parsePriority(raw) {
  if (!raw) return null;
  const digit = String(raw).match(/[0-9]/);
  if (digit) {
    return Math.min(3, Math.max(0, Number(digit[0])));
  }
  const l = String(raw).trim().toLowerCase();
  if (l.includes("urgent") || l.includes("critical") || l.includes("紧急") || l.includes("最高")) return 0;
  if (l.includes("high") || l === "高" || l.includes("高优")) return 1;
  if (l.includes("medium") || l.includes("normal") || l.includes("mid") || l === "中" || l.includes("普通")) return 2;
  if (l.includes("low") || l === "低") return 3;
  return null;
}

function parseNotionDate(s) {
  if (!s) return null;
  const str = String(s).trim();
  const hasTime = str.length > 10 || str.includes("T");
  const d = parseStoredDate(str);
  return d ? { date: d, hasTime } : null;
}

function parseNotionPage(page, schema) {
  const id = page?.id;
  const props = page?.properties;
  if (!id || !props || typeof props !== "object") return null;

  let titleObj = schema.titleProp ? props[schema.titleProp] : null;
  if (!titleObj) {
    titleObj = Object.values(props).find((v) => v && (v.type === "title" || Array.isArray(v.title)));
  }
  const title = (Array.isArray(titleObj?.title) ? titleObj.title : [])
    .map((x) => x?.plain_text || "")
    .join("");
  if (!title.trim()) return null;

  const selectOrStatus = (name) => {
    const p = props[name];
    if (!p) return null;
    if (p.select?.name) return p.select.name;
    if (p.status?.name) return p.status.name;
    if (Array.isArray(p.multi_select) && p.multi_select[0]?.name) return p.multi_select[0].name;
    return null;
  };

  const getDate = (name) => {
    const start = props[name]?.date?.start;
    return start ? parseNotionDate(start) : null;
  };

  const prioRaw = schema.priorityProp ? selectOrStatus(schema.priorityProp) : null;
  const priority = prioRaw !== null ? parsePriority(prioRaw) : null;
  const due = schema.dueProp ? getDate(schema.dueProp) : null;
  const scheduled = schema.scheduledProp ? getDate(schema.scheduledProp)?.date || null : null;
  const top3 = schema.top3Prop ? Boolean(props[schema.top3Prop]?.checkbox) : false;

  let tag = null;
  for (const tp of schema.tagProps || []) {
    const val = selectOrStatus(tp);
    if (val) {
      tag = val;
      break;
    }
  }

  return {
    id,
    url: page.url || null,
    title,
    priority,
    due: due ? due.date : null,
    dueHasTime: due ? due.hasTime : false,
    scheduled,
    top3,
    tag,
  };
}

class SyncHttpError extends Error {
  constructor(code, msg) {
    let text = msg;
    if (code === 401) text = "令牌无效（401）";
    else if (code === 404) text = "找不到数据库：请确认数据库 ID 正确，并在 Notion 里将其授权给这个 integration";
    super(text);
    this.code = code;
  }
}

class NotionSync extends EventEmitter {
  constructor({ dataDir = null, model = null, fetchFn = null } = {}) {
    super();
    this.dataDir = getDataDir(dataDir);
    this.filePath = path.join(this.dataDir, "notion.json");
    this.model = model;
    this.fetchFn = fetchFn || globalThis.fetch;
    this.config = normalizeConfig(readJSON(this.filePath, {}));
    this.syncing = false;
    this.lastSync = null;
    this.lastCount = 0;
    this.lastError = null;
    this.databaseTitle = null;
    this.cachedSchema = null;
    this.timer = null;
  }

  _cacheKey(c = this.config) {
    const h = configHelpers(c);
    return `${h.trimmedToken}|${h.trimmedDataSourceID}|${h.trimmedDatabaseID}`;
  }

  _emitChange() {
    this.emit("change", this.getStatus());
  }

  getStatus() {
    const h = configHelpers(this.config);
    return {
      configured: h.isConfigured,
      targetInput: h.targetInput,
      hasToken: Boolean(h.trimmedToken),
      lookaheadDays: this.config.lookaheadDays,
      writeBack: this.config.writeBack,
      syncing: this.syncing,
      lastSyncHM: this.lastSync ? `${String(this.lastSync.getHours()).padStart(2, "0")}:${String(this.lastSync.getMinutes()).padStart(2, "0")}` : null,
      lastCount: this.lastCount,
      lastError: this.lastError,
      databaseTitle: this.databaseTitle,
    };
  }

  start(model = this.model) {
    if (model) this.model = model;
    if (this.model && !this._boundFinish) {
      this._boundFinish = (task) => this.taskFinished(task);
      this.model.on("taskFinished", this._boundFinish);
    }
    if (configHelpers(this.config).isConfigured) {
      this.sync().catch(() => {});
    }
    if (!this.timer) {
      this.timer = setInterval(() => {
        this.model?.refreshDay();
        if (configHelpers(this.config).isConfigured) {
          this.sync().catch(() => {});
        }
      }, 30 * 60 * 1000);
      if (typeof this.timer.unref === "function") this.timer.unref();
    }
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (this.model && this._boundFinish) {
      this.model.off("taskFinished", this._boundFinish);
      this._boundFinish = null;
    }
  }

  update(patchOrFn) {
    const oldKey = this._cacheKey();
    const copy = { ...this.config };
    if (typeof patchOrFn === "function") patchOrFn(copy);
    else Object.assign(copy, patchOrFn);
    this.config = normalizeConfig(copy);
    writeJSON(this.filePath, this.config, 0o600);
    if (this._cacheKey() !== oldKey) {
      this.cachedSchema = null;
      this.databaseTitle = null;
    }
    this._emitChange();
  }

  async sync() {
    const cfg = { ...this.config };
    const h = configHelpers(cfg);
    if (!h.isConfigured) {
      throw new Error("还没有填写 Notion 令牌和数据库 ID");
    }
    if (this.syncing) {
      throw new Error("正在同步中");
    }
    this.syncing = true;
    this._emitChange();
    try {
      const resolved = await this.resolveSchema(cfg);
      const items = await this.fetchAll(cfg, resolved.schema, resolved.useDataSource);
      if (this._cacheKey() === this._cacheKey(cfg)) {
        this.cachedSchema = { key: this._cacheKey(cfg), ...resolved };
        this.databaseTitle = resolved.schema.databaseTitle;
      }
      this.model?.mergeNotion(items);
      this.lastSync = new Date();
      this.lastCount = items.length;
      this.lastError = null;
      this.syncing = false;
      this._emitChange();
      return items.length;
    } catch (err) {
      this.lastError = err?.message || String(err);
      this.syncing = false;
      this._emitChange();
      throw err;
    }
  }

  async resolveSchema(cfg = this.config) {
    const key = this._cacheKey(cfg);
    if (this.cachedSchema && this.cachedSchema.key === key) {
      return { schema: this.cachedSchema.schema, useDataSource: this.cachedSchema.useDataSource };
    }
    const h = configHelpers(cfg);
    const dsID = h.trimmedDataSourceID;
    const dbID = h.trimmedDatabaseID || dsID;

    if (dsID) {
      try {
        const json = await this._request("GET", `data_sources/${dsID}`, "2025-09-03", h.trimmedToken);
        return { schema: NotionSchema.detect(json), useDataSource: true };
      } catch (err) {
        if ((err.code === 400 || err.code === 404) && dbID) {
          const json = await this._request("GET", `databases/${dbID}`, "2022-06-28", h.trimmedToken);
          return { schema: NotionSchema.detect(json), useDataSource: false };
        }
        throw err;
      }
    } else {
      const json = await this._request("GET", `databases/${dbID}`, "2022-06-28", h.trimmedToken);
      return { schema: NotionSchema.detect(json), useDataSource: false };
    }
  }

  async fetchAll(cfg, schema, useDataSource) {
    const all = [];
    let cursor = null;
    do {
      const { results, next } = await this.queryPage(cfg, schema, useDataSource, cursor);
      for (const page of results) {
        const parsed = parseNotionPage(page, schema);
        if (parsed) all.push(parsed);
      }
      cursor = next;
    } while (cursor && all.length < 500);
    return all;
  }

  async queryPage(cfg, schema, useDataSource, cursor) {
    const h = configHelpers(cfg);
    const body = filterBody(cfg.lookaheadDays, schema);
    if (cursor) body.start_cursor = cursor;
    const dsID = h.trimmedDataSourceID;
    const dbID = h.trimmedDatabaseID || dsID;

    let json;
    if (useDataSource && dsID) {
      try {
        json = await this._request("POST", `data_sources/${dsID}/query`, "2025-09-03", h.trimmedToken, body);
      } catch (err) {
        if ((err.code === 400 || err.code === 404) && dbID) {
          json = await this._request("POST", `databases/${dbID}/query`, "2022-06-28", h.trimmedToken, body);
        } else {
          throw err;
        }
      }
    } else {
      json = await this._request("POST", `databases/${dbID}/query`, "2022-06-28", h.trimmedToken, body);
    }

    const results = Array.isArray(json.results) ? json.results : [];
    const next = json.has_more === true ? json.next_cursor || null : null;
    return { results, next };
  }

  async _request(method, endpoint, version, token, body = null) {
    const url = `https://api.notion.com/v1/${endpoint}`;
    const headers = {
      Authorization: `Bearer ${token}`,
      "Notion-Version": version,
    };
    const opts = { method, headers, signal: AbortSignal.timeout(20000) };
    if (body !== null) {
      headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    const resp = await this.fetchFn(url, opts);
    let json = {};
    try {
      json = await resp.json();
    } catch {
      json = {};
    }
    if (resp.status !== 200) {
      throw new SyncHttpError(resp.status, json.message || `HTTP ${resp.status}`);
    }
    return json;
  }

  async taskFinished(task) {
    const cfg = { ...this.config };
    const h = configHelpers(cfg);
    if (!cfg.writeBack || !h.isConfigured || task?.source !== "notion" || !task.notionID) return;
    try {
      let resolved = null;
      try {
        resolved = await this.resolveSchema(cfg);
      } catch {
        resolved = null;
      }
      let props;
      if (resolved?.schema) {
        const s = resolved.schema;
        if (!s.statusProp) return;
        if (s.statusType === "checkbox") {
          props = { [s.statusProp]: { checkbox: true } };
        } else if (s.statusType === "select") {
          if (!s.doneStatus) return;
          props = { [s.statusProp]: { select: { name: s.doneStatus } } };
        } else {
          if (!s.doneStatus) return;
          props = { [s.statusProp]: { status: { name: s.doneStatus } } };
        }
      } else {
        props = { Status: { status: { name: "Done" } } };
      }
      await this._request("PATCH", `pages/${task.notionID}`, "2022-06-28", h.trimmedToken, { properties: props });
    } catch (err) {
      this.lastError = err?.code ? `回写 Notion 失败（HTTP ${err.code}）` : `回写 Notion 失败：${err?.message || err}`;
      this._emitChange();
    }
  }
}

module.exports = {
  NotionSchema,
  NotionSync,
  extractID,
  filterBody,
  parseNotionPage,
  parsePriority,
  parseNotionDate,
  normalizeConfig,
  configHelpers,
};
