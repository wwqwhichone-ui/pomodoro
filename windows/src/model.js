const { EventEmitter } = require("events");
const crypto = require("crypto");
const path = require("path");
const { getDataDir, readJSON, writeJSON } = require("./store");

const Phase = {
  focus: "focus",
  shortBreak: "shortBreak",
  longBreak: "longBreak",
};

const PHASE_LIST = [Phase.focus, Phase.shortBreak, Phase.longBreak];

const PHASE_TITLES = {
  [Phase.focus]: "专注",
  [Phase.shortBreak]: "短休息",
  [Phase.longBreak]: "长休息",
};

const BreakTips = {
  short: [
    "起身走两步，活动一下肩颈",
    "喝口水，补充一下水分",
    "看看窗外远处，放松眼睛",
    "闭上眼，做三次深呼吸",
    "伸个懒腰，舒展一下身体",
    "别刷手机，让大脑真正休息",
  ],
  long: [
    "出去走走，散个步",
    "吃点东西，补充能量",
    "回顾一下这一组番茄完成了什么",
    "离开座位，彻底放空一会儿",
    "和人聊聊天，换换脑子",
  ],
};

const DEFAULT_SETTINGS = {
  focusMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  longBreakEvery: 4,
  autoStartNext: false,
  playSound: true,
  alwaysOnTop: false,
  autoFullScreenOnSecondary: true,
  appearance: "light",
  showInTray: true,
};

function pad2(n) {
  return String(n).padStart(2, "0");
}

function localDayString(date = new Date()) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

function startOfLocalDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0);
}

function formatHM(date) {
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

function formatDuration(seconds) {
  const m = Math.floor(seconds / 60);
  return m >= 60 ? `${Math.floor(m / 60)} 小时 ${m % 60} 分` : `${m} 分钟`;
}

function parseStoredDate(val) {
  if (!val) return null;
  if (val instanceof Date) return Number.isNaN(val.getTime()) ? null : val;
  const s = String(val).trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    const [y, m, d] = s.split("-").map(Number);
    const dt = new Date(y, m - 1, d, 0, 0, 0, 0);
    return dt.getFullYear() === y && dt.getMonth() === m - 1 && dt.getDate() === d ? dt : null;
  }
  const dt = new Date(s);
  return Number.isNaN(dt.getTime()) ? null : dt;
}

function formatLocalISO(date) {
  const off = -date.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  const abs = Math.abs(off);
  const hh = pad2(Math.floor(abs / 60));
  const mm = pad2(abs % 60);
  return (
    `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}` +
    `T${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}${sign}${hh}:${mm}`
  );
}

function parseDay(raw, now = new Date()) {
  const s = String(raw || "").trim();
  if (!s) return null;
  const today = startOfLocalDay(now);
  const lower = s.toLowerCase();
  if (s === "今天" || lower === "today") return today;
  if (s === "明天" || lower === "tomorrow") {
    return new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
  }
  if (s === "后天") {
    return new Date(today.getFullYear(), today.getMonth(), today.getDate() + 2);
  }
  const parts = s.split(/[-/.]/);
  if (parts.some((p) => !/^\d+$/.test(p))) return null;
  const nums = parts.map(Number);
  let y = today.getFullYear();
  let m;
  let d;
  if (nums.length === 2) {
    [m, d] = nums;
    const month = today.getMonth() + 1;
    if (m < month || (m === month && d < today.getDate())) y++;
  } else if (nums.length === 3) {
    [y, m, d] = nums;
  } else {
    return null;
  }
  if (y < 1970 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const candidate = new Date(y, m - 1, d, 0, 0, 0, 0);
  if (candidate.getFullYear() !== y || candidate.getMonth() !== m - 1 || candidate.getDate() !== d) {
    return null;
  }
  return candidate;
}

function parseQuickAdd(raw) {
  let title = String(raw || "").trim();
  let estimate = 1;
  let priority = null;
  let due = null;
  let changed = true;
  while (changed) {
    changed = false;
    const estMatch = title.match(/\s*[x×X*]\s*(\d{1,2})$/);
    if (estMatch) {
      const n = Number(estMatch[1]);
      if (n > 0) {
        estimate = Math.min(n, 12);
        title = title.slice(0, estMatch.index).trim();
        changed = true;
      }
    }
    const prioMatch = title.match(/(^|\s+)[Pp]([0-3])$/);
    if (prioMatch) {
      priority = Number(prioMatch[2]);
      title = title.slice(0, prioMatch.index).trim();
      changed = true;
    }
    const dueMatch = title.match(/(^|\s+)@(\S+)$/);
    if (dueMatch) {
      const d = parseDay(dueMatch[2]);
      if (d) {
        due = localDayString(d);
        title = title.slice(0, dueMatch.index).trim();
        changed = true;
      }
    }
  }
  return { title, estimate, priority, due };
}

function getDueMoment(task) {
  if (!task || !task.due) return null;
  const d = parseStoredDate(task.due);
  if (!d) return null;
  if (task.dueHasTime) return d;
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

const DDL = {
  describe(task, now = new Date()) {
    const due = parseStoredDate(task?.due);
    const moment = getDueMoment(task);
    if (!due || !moment) return null;
    const today0 = startOfLocalDay(now);
    const due0 = startOfLocalDay(due);
    const days = Math.round((due0.getTime() - today0.getTime()) / (24 * 3600 * 1000));
    const hm = task.dueHasTime ? ` ${formatHM(due)}` : "";
    if (moment.getTime() < now.getTime()) {
      return { text: days < 0 ? `已逾期 ${-days} 天` : "已逾期", level: 0 };
    }
    const soon = moment.getTime() - now.getTime() < 24 * 3600 * 1000;
    if (days === 0) return { text: `今天${hm} 截止`, level: 1 };
    if (days === 1) return { text: `明天${hm} 截止`, level: soon ? 1 : 2 };
    if (days >= 2 && days <= 3) return { text: `剩 ${days} 天`, level: 2 };
    return { text: `${due.getMonth() + 1}月${due.getDate()}日 截止`, level: 3 };
  },
};

function makeEmptyStats(day = localDayString()) {
  return {
    day,
    completed: 0,
    voided: 0,
    internalBreaks: 0,
    externalBreaks: 0,
    focusSeconds: 0,
    taskPomodoros: {},
  };
}

function hasStatsActivity(s) {
  if (!s) return false;
  return (
    (s.completed || 0) > 0 ||
    (s.focusSeconds || 0) >= 60 ||
    (s.internalBreaks || 0) > 0 ||
    (s.externalBreaks || 0) > 0 ||
    (s.voided || 0) > 0
  );
}

function makeDailyLog(s) {
  const map = s?.taskPomodoros && typeof s.taskPomodoros === "object" ? s.taskPomodoros : {};
  const taskSummary = Object.entries(map)
    .sort((a, b) => (b[1] !== a[1] ? b[1] - a[1] : a[0].localeCompare(b[0])))
    .map(([title, cnt]) => `${title} (${cnt}🍅)`)
    .join("、");
  return {
    day: s.day,
    completed: s.completed || 0,
    focusMinutes: Math.floor((s.focusSeconds || 0) / 60),
    internalBreaks: s.internalBreaks || 0,
    externalBreaks: s.externalBreaks || 0,
    voided: s.voided || 0,
    taskSummary,
  };
}

class TimerModel extends EventEmitter {
  constructor(options = {}) {
    super();
    this.dataDir = getDataDir(options.dataDir);
    this.stateFile = path.join(this.dataDir, "state.json");

    const saved = readJSON(this.stateFile, {});
    this.settings = { ...DEFAULT_SETTINGS, ...(saved.settings || {}) };
    this._clampSettings();

    this.pendingDailyLogs = Array.isArray(saved.pendingDailyLogs)
      ? saved.pendingDailyLogs.map((x) => ({ ...x }))
      : [];

    const today = localDayString();
    let rolledOver = false;
    if (saved.stats && typeof saved.stats === "object") {
      if (saved.stats.day === today) {
        this.stats = { ...makeEmptyStats(today), ...saved.stats };
      } else {
        if (hasStatsActivity(saved.stats)) {
          this._enqueueDailyLogInMemory(makeDailyLog(saved.stats));
        }
        this.stats = makeEmptyStats(today);
        rolledOver = true;
      }
    } else {
      this.stats = makeEmptyStats(today);
    }

    this.tasks = Array.isArray(saved.tasks) ? saved.tasks.map((t) => ({ ...t })) : [];
    if (rolledOver) {
      this.tasks = this.tasks.filter((t) => !t.finished);
    }
    this.currentTaskID = typeof saved.currentTaskID === "string" ? saved.currentTaskID : null;

    this.phase = Phase.focus;
    this.isRunning = false;
    this.sessionTouched = false;
    this.streak = 0;
    this.finishToken = 0;
    this.sessionInternal = 0;
    this.sessionExternal = 0;
    this.breakTip = BreakTips.short[0];
    this.endDate = null;
    this.ticker = null;
    this.remaining = this.duration(Phase.focus);

    if (rolledOver) {
      this._save();
    }
  }

  _clampSettings() {
    this.settings.focusMinutes = Math.min(120, Math.max(1, Number(this.settings.focusMinutes) || 25));
    this.settings.shortBreakMinutes = Math.min(60, Math.max(1, Number(this.settings.shortBreakMinutes) || 5));
    this.settings.longBreakMinutes = Math.min(60, Math.max(1, Number(this.settings.longBreakMinutes) || 15));
    this.settings.longBreakEvery = Math.min(10, Math.max(2, Number(this.settings.longBreakEvery) || 4));
    this.settings.autoStartNext = Boolean(this.settings.autoStartNext);
    this.settings.playSound = this.settings.playSound !== false;
    this.settings.alwaysOnTop = Boolean(this.settings.alwaysOnTop);
    this.settings.autoFullScreenOnSecondary = this.settings.autoFullScreenOnSecondary !== false;
    this.settings.showInTray = this.settings.showInTray !== false;
    if (!["light", "dark", "system"].includes(this.settings.appearance)) {
      this.settings.appearance = "light";
    }
  }

  _save() {
    writeJSON(this.stateFile, {
      settings: this.settings,
      tasks: this.tasks,
      currentTaskID: this.currentTaskID,
      stats: this.stats,
      pendingDailyLogs: this.pendingDailyLogs,
    });
  }

  _enqueueDailyLogInMemory(entry) {
    this.pendingDailyLogs = this.pendingDailyLogs.filter((x) => x.day !== entry.day);
    this.pendingDailyLogs.push(entry);
    this.pendingDailyLogs.sort((a, b) => a.day.localeCompare(b.day));
  }

  enqueueDailyLog(entry) {
    this._enqueueDailyLogInMemory(entry);
    this._save();
  }

  removePendingDailyLog(day) {
    this.pendingDailyLogs = this.pendingDailyLogs.filter((x) => x.day !== day);
    this._save();
  }

  currentDailyLog() {
    this.ensureToday();
    return makeDailyLog(this.stats);
  }

  _emitChange() {
    this.emit("change", this.getSnapshot());
  }

  duration(p = this.phase) {
    let mins;
    if (p === Phase.focus) mins = this.settings.focusMinutes;
    else if (p === Phase.shortBreak) mins = this.settings.shortBreakMinutes;
    else mins = this.settings.longBreakMinutes;
    return Math.max(1, Number(mins) || 25) * 60;
  }

  get total() {
    return this.duration(this.phase);
  }

  get longEvery() {
    return Math.max(1, Number(this.settings.longBreakEvery) || 4);
  }

  get progress() {
    return Math.min(1, Math.max(0, 1 - this.remaining / this.total));
  }

  get hasStarted() {
    return this.isRunning || this.sessionTouched;
  }

  get projectedEnd() {
    if (this.endDate) return new Date(this.endDate);
    return new Date(Date.now() + this.remaining * 1000);
  }

  get currentTask() {
    return this.tasks.find((t) => t.id === this.currentTaskID) || null;
  }

  get timeText() {
    const s = Math.max(0, Math.ceil(this.remaining));
    return `${pad2(Math.floor(s / 60))}:${pad2(s % 60)}`;
  }

  get sortedTasks() {
    return this.tasks
      .map((task, idx) => ({ task, idx }))
      .sort((a, b) => {
        if (Boolean(a.task.finished) !== Boolean(b.task.finished)) {
          return a.task.finished ? 1 : -1;
        }
        const topA = a.task.top3 ? 0 : 1;
        const topB = b.task.top3 ? 0 : 1;
        if (topA !== topB) return topA - topB;

        const prioA = a.task.priority ?? 9;
        const prioB = b.task.priority ?? 9;
        if (prioA !== prioB) return prioA - prioB;

        const dueA = getDueMoment(a.task)?.getTime() ?? Number.MAX_VALUE;
        const dueB = getDueMoment(b.task)?.getTime() ?? Number.MAX_VALUE;
        if (dueA !== dueB) return dueA - dueB;

        return a.idx - b.idx;
      })
      .map((x) => x.task);
  }

  toggle() {
    if (this.isRunning) this.pause();
    else this.start();
  }

  start() {
    if (this.isRunning) return;
    this.ensureToday();
    if (this.remaining <= 0) this.remaining = this.total;
    this.endDate = Date.now() + this.remaining * 1000;
    this.sessionTouched = true;
    this.isRunning = true;
    if (this.ticker) clearInterval(this.ticker);
    this.ticker = setInterval(() => this.tick(), 200);
    if (typeof this.ticker.unref === "function") this.ticker.unref();
    this._emitChange();
  }

  pause() {
    if (!this.isRunning) return;
    if (this.endDate !== null) {
      this.remaining = Math.max(0, (this.endDate - Date.now()) / 1000);
    }
    this._stopTicker();
    this._emitChange();
  }

  reset() {
    this._stopTicker();
    this._enter(this.phase);
    this._emitChange();
  }

  skip() {
    if (this.phase === Phase.focus && this.hasStarted) {
      this.ensureToday();
      this.stats.voided += 1;
      this._save();
    }
    this._advance(false);
  }

  selectPhase(p) {
    if (!PHASE_LIST.includes(p)) return;
    this._stopTicker();
    this._enter(p);
    this._emitChange();
  }

  updateSettings(patch = {}) {
    const prevTray = this.settings.showInTray;
    const prevOnTop = this.settings.alwaysOnTop;
    Object.assign(this.settings, patch);
    this._clampSettings();
    this._save();
    this.settingsChanged();
    if (prevTray !== this.settings.showInTray) {
      this.emit("traySettingChanged", this.settings.showInTray);
    }
    if (prevOnTop !== this.settings.alwaysOnTop) {
      this.emit("onTopChanged", this.settings.alwaysOnTop);
    }
  }

  settingsChanged() {
    if (!this.isRunning && !this.sessionTouched) {
      this.remaining = this.total;
    } else if (!this.isRunning) {
      this.remaining = Math.min(this.remaining, this.total);
    }
    this._emitChange();
  }

  logInterruption(isInternal) {
    if (this.phase !== Phase.focus) return;
    this.ensureToday();
    if (isInternal) {
      this.sessionInternal += 1;
      this.stats.internalBreaks += 1;
    } else {
      this.sessionExternal += 1;
      this.stats.externalBreaks += 1;
    }
    this._save();
    this._emitChange();
  }

  undoInterruption(isInternal) {
    if (this.phase !== Phase.focus) return false;
    this.ensureToday();
    if (isInternal) {
      if (this.sessionInternal <= 0) return false;
      this.sessionInternal -= 1;
      this.stats.internalBreaks = Math.max(0, this.stats.internalBreaks - 1);
    } else {
      if (this.sessionExternal <= 0) return false;
      this.sessionExternal -= 1;
      this.stats.externalBreaks = Math.max(0, this.stats.externalBreaks - 1);
    }
    this._save();
    this._emitChange();
    return true;
  }

  resetToday() {
    this.stats = makeEmptyStats(localDayString());
    this.streak = 0;
    this.sessionInternal = 0;
    this.sessionExternal = 0;
    this._save();
    this._emitChange();
  }

  addQuickTask(raw) {
    const parsed = parseQuickAdd(raw);
    return this.addTask(parsed);
  }

  addTask({ title, estimate = 1, priority = null, due = null, dueHasTime = false, top3 = false, note = null } = {}) {
    const cleanTitle = String(title || "").trim();
    if (!cleanTitle) return null;
    const t = {
      id: crypto.randomUUID().toUpperCase(),
      title: cleanTitle,
      estimate: Math.min(12, Math.max(1, Number(estimate) || 1)),
      done: 0,
      finished: false,
    };
    if (priority !== null && priority !== undefined) {
      t.priority = Math.min(3, Math.max(0, Number(priority)));
    }
    if (due) {
      if (due instanceof Date) {
        t.due = dueHasTime ? formatLocalISO(due) : localDayString(due);
        t.dueHasTime = Boolean(dueHasTime);
      } else {
        t.due = String(due);
        t.dueHasTime = Boolean(dueHasTime);
      }
    }
    if (top3) t.top3 = true;
    if (note !== null && note !== undefined) t.note = String(note);

    this.tasks.push(t);
    const cur = this.currentTask;
    if (!cur || cur.finished) this._autoSelect();
    this._save();
    this._emitChange();
    return this.tasks.find((x) => x.id === t.id) || null;
  }

  updateTask(id, updater) {
    const idx = this.tasks.findIndex((t) => t.id === id);
    if (idx === -1) return null;
    const wasFinished = Boolean(this.tasks[idx].finished);
    const copy = { ...this.tasks[idx] };
    updater(copy);
    copy.estimate = Math.min(12, Math.max(1, Number(copy.estimate) || 1));
    this.tasks[idx] = copy;
    if (!wasFinished && copy.finished) {
      this._didFinish(copy);
    }
    this._save();
    this._emitChange();
    return this.tasks[idx];
  }

  selectTask(id) {
    this.currentTaskID = id;
    this._save();
    this._emitChange();
  }

  toggleFinished(id) {
    const idx = this.tasks.findIndex((t) => t.id === id);
    if (idx === -1) return null;
    this.tasks[idx].finished = !this.tasks[idx].finished;
    if (this.tasks[idx].finished) {
      this._didFinish(this.tasks[idx]);
    }
    this._save();
    this._emitChange();
    return this.tasks[idx];
  }

  removeTask(id) {
    this.tasks = this.tasks.filter((t) => t.id !== id);
    if (this.currentTaskID === id) this._autoSelect();
    this._save();
    this._emitChange();
  }

  adjustEstimate(id, delta) {
    const idx = this.tasks.findIndex((t) => t.id === id);
    if (idx === -1) return;
    this.tasks[idx].estimate = Math.min(12, Math.max(1, (this.tasks[idx].estimate || 1) + delta));
    this._save();
    this._emitChange();
  }

  clearFinished() {
    this.tasks = this.tasks.filter((t) => !t.finished);
    if (!this.currentTask) this._autoSelect();
    this._save();
    this._emitChange();
  }

  mergeNotion(items) {
    const result = this.tasks.map((t) => ({ ...t }));
    for (const it of items) {
      const idx = result.findIndex((t) => t.notionID === it.id);
      const dueStr = it.due ? (it.dueHasTime ? formatLocalISO(it.due) : localDayString(it.due)) : undefined;
      const schedStr = it.scheduled ? localDayString(it.scheduled) : undefined;
      if (idx !== -1) {
        result[idx].title = it.title;
        if (it.priority !== null && it.priority !== undefined) result[idx].priority = it.priority;
        else delete result[idx].priority;
        if (dueStr) {
          result[idx].due = dueStr;
          result[idx].dueHasTime = Boolean(it.dueHasTime);
        } else {
          delete result[idx].due;
          delete result[idx].dueHasTime;
        }
        if (schedStr) result[idx].scheduled = schedStr;
        else delete result[idx].scheduled;
        if (it.top3) result[idx].top3 = true;
        else delete result[idx].top3;
        if (it.url) result[idx].notionURL = it.url;
        else delete result[idx].notionURL;
        if (it.tag) result[idx].tag = it.tag;
        else delete result[idx].tag;
      } else {
        const t = {
          id: crypto.randomUUID().toUpperCase(),
          title: it.title,
          estimate: 1,
          done: 0,
          finished: false,
          source: "notion",
          notionID: it.id,
        };
        if (it.url) t.notionURL = it.url;
        if (it.priority !== null && it.priority !== undefined) t.priority = it.priority;
        if (dueStr) {
          t.due = dueStr;
          t.dueHasTime = Boolean(it.dueHasTime);
        }
        if (schedStr) t.scheduled = schedStr;
        if (it.top3) t.top3 = true;
        if (it.tag) t.tag = it.tag;
        result.push(t);
      }
    }

    const alive = new Set(items.map((x) => x.id));
    this.tasks = result.filter((t) => {
      if (t.source !== "notion") return true;
      if (alive.has(t.notionID || "")) return true;
      if (t.id === this.currentTaskID && this.isRunning) return true;
      if (t.finished) return true;
      return false;
    });
    const cur = this.currentTask;
    if (!cur || cur.finished) this._autoSelect();
    this._save();
    this._emitChange();
  }

  refreshDay() {
    if (this.ensureToday()) {
      this._emitChange();
    }
  }

  ensureToday() {
    const today = localDayString();
    if (this.stats.day !== today) {
      const old = this.stats;
      const active = hasStatsActivity(old);
      if (active) {
        this._enqueueDailyLogInMemory(makeDailyLog(old));
      }
      this.stats = makeEmptyStats(today);
      this.tasks = this.tasks.filter((t) => !t.finished);
      if (!this.currentTask) this._autoSelect();
      this._save();
      if (active) {
        this.emit("dailyLogReady");
      }
      return true;
    }
    return false;
  }

  _didFinish(task) {
    if (this.currentTaskID === task.id) this._autoSelect();
    this.emit("taskFinished", task);
  }

  _autoSelect() {
    const next = this.sortedTasks.find((t) => !t.finished);
    this.currentTaskID = next ? next.id : null;
  }

  _enter(p) {
    this.phase = p;
    this.sessionTouched = false;
    this.remaining = this.duration(p);
    if (p === Phase.focus) {
      this.sessionInternal = 0;
      this.sessionExternal = 0;
    } else {
      const pool = p === Phase.longBreak ? BreakTips.long : BreakTips.short;
      this.breakTip = pool[Math.floor(Math.random() * pool.length)] || "";
    }
  }

  _stopTicker() {
    if (this.ticker) {
      clearInterval(this.ticker);
      this.ticker = null;
    }
    this.endDate = null;
    this.isRunning = false;
  }

  tick() {
    if (this.endDate === null) return;
    const r = (this.endDate - Date.now()) / 1000;
    if (r <= 0) {
      this.remaining = 0;
      this._advance(true);
    } else {
      const prevSec = Math.ceil(this.remaining);
      this.remaining = r;
      if (Math.ceil(r) !== prevSec) {
        this._emitChange();
      }
    }
  }

  _advance(completed) {
    const finishedPhase = this.phase;
    const finishedDuration = this.total;
    this._stopTicker();
    let next;
    if (finishedPhase === Phase.focus) {
      if (completed) {
        this.ensureToday();
        this.stats.completed += 1;
        this.stats.focusSeconds += finishedDuration;
        this.streak += 1;
        if (this.currentTaskID) {
          const idx = this.tasks.findIndex((t) => t.id === this.currentTaskID);
          if (idx !== -1) {
            this.tasks[idx].done = (this.tasks[idx].done || 0) + 1;
            const title = this.tasks[idx].title;
            const map = { ...(this.stats.taskPomodoros || {}) };
            map[title] = (map[title] || 0) + 1;
            this.stats.taskPomodoros = map;
          }
        }
        this._save();
        this.emit("focusCompleted", makeDailyLog(this.stats));
      }
      next = this.streak >= this.longEvery ? Phase.longBreak : Phase.shortBreak;
    } else {
      if (finishedPhase === Phase.longBreak) this.streak = 0;
      next = Phase.focus;
    }
    this._enter(next);

    if (completed) {
      this.finishToken += 1;
      this.emit("phaseComplete", {
        completedPhase: finishedPhase,
        nextPhase: next,
        sound: this.settings.playSound,
        autoStart: this.settings.autoStartNext,
      });
      if (this.settings.autoStartNext) {
        this.start();
        return;
      }
    }
    this._emitChange();
  }

  taskDTO(t) {
    const d = {
      id: t.id,
      title: t.title,
      estimate: t.estimate,
      done: t.done,
      finished: Boolean(t.finished),
      current: t.id === this.currentTaskID,
      source: t.source || "local",
      top3: Boolean(t.top3),
    };
    if (t.priority !== null && t.priority !== undefined) d.priority = `P${t.priority}`;
    if (t.due) d.due = t.due;
    const ddl = DDL.describe(t);
    if (ddl) d.ddl = ddl.text;
    if (t.scheduled) d.scheduled = t.scheduled;
    if (t.note !== undefined && t.note !== null) d.note = t.note;
    if (t.tag) d.tag = t.tag;
    if (t.notionURL) d.notionUrl = t.notionURL;
    return d;
  }

  getStatusDTO() {
    const s = {
      phase: this.phase,
      phaseTitle: PHASE_TITLES[this.phase],
      running: this.isRunning,
      paused: !this.isRunning && this.hasStarted,
      remainingSeconds: Math.max(0, Math.ceil(this.remaining)),
      remaining: this.timeText,
      totalSeconds: Math.round(this.total),
      streak: this.streak,
      longBreakEvery: this.longEvery,
      today: {
        completed: this.stats.completed,
        focusMinutes: Math.floor((this.stats.focusSeconds || 0) / 60),
        voided: this.stats.voided,
        internalInterruptions: this.stats.internalBreaks,
        externalInterruptions: this.stats.externalBreaks,
      },
      session: {
        internal: this.sessionInternal,
        external: this.sessionExternal,
      },
    };
    if (this.isRunning) s.endsAt = formatLocalISO(this.projectedEnd);
    if (this.currentTask) s.currentTask = this.taskDTO(this.currentTask);
    return s;
  }

  getSnapshot() {
    return {
      phase: this.phase,
      phaseTitle: PHASE_TITLES[this.phase],
      running: this.isRunning,
      paused: !this.isRunning && this.hasStarted,
      hasStarted: this.hasStarted,
      remaining: this.remaining,
      total: this.total,
      timeText: this.timeText,
      progress: this.progress,
      projectedEndHM: formatHM(this.projectedEnd),
      streak: this.streak,
      longEvery: this.longEvery,
      finishToken: this.finishToken,
      breakTip: this.breakTip,
      sessionInternal: this.sessionInternal,
      sessionExternal: this.sessionExternal,
      stats: { ...this.stats },
      settings: { ...this.settings },
      currentTaskID: this.currentTaskID,
      tasks: this.sortedTasks.map((t) => ({
        ...t,
        ddlInfo: DDL.describe(t),
      })),
    };
  }

  dispose() {
    this._stopTicker();
    this.removeAllListeners();
  }
}

module.exports = {
  Phase,
  PHASE_LIST,
  PHASE_TITLES,
  BreakTips,
  DEFAULT_SETTINGS,
  DDL,
  TimerModel,
  hasStatsActivity,
  makeDailyLog,
  localDayString,
  formatHM,
  formatDuration,
  formatLocalISO,
  parseDay,
  parseQuickAdd,
  parseStoredDate,
};
