const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile, execFileSync } = require("child_process");
const { promisify } = require("util");
const execFileAsync = promisify(execFile);

const {
  Phase,
  DDL,
  TimerModel,
  parseDay,
  parseQuickAdd,
  localDayString,
} = require("../src/model");
const {
  NotionSchema,
  NotionLogSchema,
  NotionSync,
  extractID,
  parseCategories,
  filterBody,
  parseNotionPage,
} = require("../src/notion");
const { APIServer } = require("../src/api-server");

function makeTmpDir(prefix = "pomo-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function rmDir(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

function getPythonCmd() {
  for (const cmd of process.platform === "win32" ? ["python", "python3"] : ["python3", "python"]) {
    try {
      const out = execFileSync(cmd, ["--version"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
      if (out.includes("Python 3")) return cmd;
    } catch {
      // try next
    }
  }
  return null;
}

test("extractID normalizes Notion URLs, 32-hex strings, and UUIDs", () => {
  assert.equal(
    extractID("https://www.notion.so/workspace/Tasks-1234567890abcdef1234567890abcdef?v=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    "12345678-90ab-cdef-1234-567890abcdef"
  );
  assert.equal(
    extractID("https://notion.so/abcdef01-2345-6789-abcd-ef0123456789#hash"),
    "abcdef01-2345-6789-abcd-ef0123456789"
  );
  assert.equal(
    extractID("  ABCDEF0123456789ABCDEF0123456789  "),
    "abcdef01-2345-6789-abcd-ef0123456789"
  );
  assert.equal(
    extractID("ABCDEF01-2345-6789-ABCD-EF0123456789"),
    "abcdef01-2345-6789-abcd-ef0123456789"
  );
  assert.equal(extractID("   \n "), "");
});

test("NotionSchema.detect + filterBody + parseNotionPage across 3 templates", () => {
  // 1. Full English template
  const englishDB = {
    title: [{ plain_text: "My Tasks" }],
    properties: {
      "Task Name": { type: "title", title: {} },
      Status: {
        type: "status",
        status: {
          options: [
            { id: "1", name: "Not Started" },
            { id: "2", name: "In Progress" },
            { id: "3", name: "Done" },
          ],
          groups: [
            { name: "To-do", option_ids: ["1"] },
            { name: "In progress", option_ids: ["2"] },
            { name: "Complete", option_ids: ["3"] },
          ],
        },
      },
      "Due Date": { type: "date", date: {} },
      "Scheduled Date": { type: "date", date: {} },
      Priority: { type: "select", select: {} },
      "Top 3": { type: "checkbox", checkbox: {} },
      Course: { type: "select", select: {} },
    },
  };
  const sEn = NotionSchema.detect(englishDB);
  assert.equal(sEn.databaseTitle, "My Tasks");
  assert.equal(sEn.titleProp, "Task Name");
  assert.equal(sEn.statusProp, "Status");
  assert.equal(sEn.statusType, "status");
  assert.deepEqual(sEn.openStatuses, ["Not Started", "In Progress"]);
  assert.equal(sEn.doneStatus, "Done");
  assert.equal(sEn.dueProp, "Due Date");
  assert.equal(sEn.scheduledProp, "Scheduled Date");
  assert.equal(sEn.priorityProp, "Priority");
  assert.equal(sEn.top3Prop, "Top 3");
  assert.deepEqual(sEn.tagProps, ["Course"]);

  const enFilter = filterBody(7, sEn);
  assert.ok(enFilter.filter && enFilter.sorts);

  const enPage = {
    id: "p1",
    url: "https://notion.so/p1",
    properties: {
      "Task Name": { title: [{ plain_text: "Read paper" }] },
      Priority: { select: { name: "P1" } },
      "Due Date": { date: { start: "2026-11-25" } },
      "Scheduled Date": { date: { start: "2026-11-20" } },
      "Top 3": { checkbox: true },
      Course: { select: { name: "Robotics" } },
    },
  };
  const parsedEn = parseNotionPage(enPage, sEn);
  assert.equal(parsedEn.title, "Read paper");
  assert.equal(parsedEn.priority, 1);
  assert.equal(parsedEn.top3, true);
  assert.equal(parsedEn.tag, "Robotics");

  // 2. Minimal template (Name + Done checkbox only)
  const minimalDB = {
    title: [{ plain_text: "Simple Todo" }],
    properties: {
      Name: { type: "title", title: {} },
      Done: { type: "checkbox", checkbox: {} },
    },
  };
  const sMin = NotionSchema.detect(minimalDB);
  assert.equal(sMin.titleProp, "Name");
  assert.equal(sMin.statusProp, "Done");
  assert.equal(sMin.statusType, "checkbox");
  assert.equal(sMin.dueProp, null);
  assert.equal(sMin.scheduledProp, null);
  assert.equal(sMin.priorityProp, null);
  assert.equal(sMin.top3Prop, null);
  assert.deepEqual(sMin.tagProps, []);

  const minFilter = filterBody(7, sMin);
  assert.equal(minFilter.sorts, undefined);
  assert.deepEqual(minFilter.filter, { property: "Done", checkbox: { equals: false } });

  const parsedMin = parseNotionPage(
    { id: "p2", properties: { Name: { title: [{ plain_text: "Buy coffee" }] } } },
    sMin
  );
  assert.equal(parsedMin.title, "Buy coffee");
  assert.equal(parsedMin.priority, null);
  assert.equal(parsedMin.due, null);

  // 3. Chinese template
  const zhDB = {
    title: [{ plain_text: "每日任务" }],
    properties: {
      任务: { type: "title", title: {} },
      状态: {
        type: "status",
        status: {
          options: [
            { id: "a", name: "待办" },
            { id: "b", name: "进行中" },
            { id: "c", name: "已完成" },
          ],
          groups: [
            { name: "To-do", option_ids: ["a"] },
            { name: "In progress", option_ids: ["b"] },
            { name: "Complete", option_ids: ["c"] },
          ],
        },
      },
      截止日期: { type: "date", date: {} },
      计划日期: { type: "date", date: {} },
      优先级: { type: "select", select: {} },
      今日重点: { type: "checkbox", checkbox: {} },
      项目: { type: "multi_select", multi_select: {} },
    },
  };
  const sZh = NotionSchema.detect(zhDB);
  assert.equal(sZh.titleProp, "任务");
  assert.equal(sZh.statusProp, "状态");
  assert.equal(sZh.doneStatus, "已完成");
  assert.deepEqual(sZh.openStatuses, ["待办", "进行中"]);
  assert.equal(sZh.dueProp, "截止日期");
  assert.equal(sZh.scheduledProp, "计划日期");
  assert.equal(sZh.priorityProp, "优先级");
  assert.equal(sZh.top3Prop, "今日重点");
  assert.deepEqual(sZh.tagProps, ["项目"]);

  const parsedZh = parseNotionPage(
    {
      id: "p3",
      properties: {
        任务: { title: [{ plain_text: "整理代码" }] },
        优先级: { select: { name: "高" } },
        今日重点: { checkbox: true },
        项目: { multi_select: [{ name: "开源" }] },
      },
    },
    sZh
  );
  assert.equal(parsedZh.title, "整理代码");
  assert.equal(parsedZh.priority, 1);
  assert.equal(parsedZh.top3, true);
  assert.equal(parsedZh.tag, "开源");
});

test("NotionSync falls back from data_sources 404 to databases and writes back checkbox", async () => {
  const dir = makeTmpDir();
  try {
    const model = new TimerModel({ dataDir: dir });
    const calls = [];
    const mockFetch = async (url, opts) => {
      calls.push({ method: opts.method, url, body: opts.body ? JSON.parse(opts.body) : null });
      if (url.includes("/data_sources/")) {
        return { status: 404, json: async () => ({ message: "Not found" }) };
      }
      if (opts.method === "GET" && url.includes("/databases/")) {
        return {
          status: 200,
          json: async () => ({
            title: [{ plain_text: "Project Board" }],
            properties: {
              Name: { type: "title", title: {} },
              Done: { type: "checkbox", checkbox: {} },
            },
          }),
        };
      }
      if (opts.method === "POST" && url.includes("/databases/") && url.endsWith("/query")) {
        return {
          status: 200,
          json: async () => ({
            results: [
              { id: "page-1", url: "https://notion.so/page-1", properties: { Name: { title: [{ plain_text: "Write docs" }] } } },
            ],
            has_more: false,
          }),
        };
      }
      if (opts.method === "PATCH" && url.endsWith("/pages/page-1")) {
        return { status: 200, json: async () => ({ ok: true }) };
      }
      throw new Error("Unexpected URL: " + url);
    };

    const sync = new NotionSync({ dataDir: dir, model, fetchFn: mockFetch });
    sync.update({
      token: "test-token",
      dataSourceID: "12345678-90ab-cdef-1234-567890abcdef",
      databaseID: "12345678-90ab-cdef-1234-567890abcdef",
      writeBack: true,
    });
    const count = await sync.sync();
    assert.equal(count, 1);
    assert.equal(sync.databaseTitle, "Project Board");
    assert.equal(model.tasks.length, 1);
    assert.equal(model.tasks[0].title, "Write docs");

    await sync.taskFinished(model.tasks[0]);
    const patchCall = calls.find((c) => c.method === "PATCH");
    assert.ok(patchCall);
    assert.deepEqual(patchCall.body, { properties: { Done: { checkbox: true } } });
    model.dispose();
  } finally {
    rmDir(dir);
  }
});

test("task deadlines reject malformed dates and validate the inferred calendar year", () => {
  const today = new Date(2027, 10, 23);
  for (const input of ["2027--11-25", "-11/25", "11.25.", "2027-02-29", "2026-02-30"]) {
    assert.equal(parseDay(input, today), null, input);
  }
  for (const [input, expected] of [
    ["Today", "2027-11-23"], ["明天", "2027-11-24"], ["11/23", "2027-11-23"],
    ["11.22", "2028-11-22"], ["2-29", "2028-02-29"], ["2028-02-29", "2028-02-29"],
  ]) {
    assert.equal(localDayString(parseDay(input, today)), expected, input);
  }
  assert.equal(parseDay("2-29", new Date(2028, 2, 1)), null);
  const task = parseQuickAdd("写周报 @2027--11-25");
  assert.equal(task.title, "写周报 @2027--11-25");
  assert.equal(task.due, null);
});

test("TimerModel quick-add, settingsChanged, interruptions, voided skip, and cross-day startup", () => {
  const dir = makeTmpDir();
  try {
    const parsed = parseQuickAdd("写周报 ×3 P1 @明天");
    assert.equal(parsed.title, "写周报");
    assert.equal(parsed.estimate, 3);
    assert.equal(parsed.priority, 1);
    assert.ok(/^\d{4}-\d{2}-\d{2}$/.test(parsed.due));

    const m = new TimerModel({ dataDir: dir });
    assert.equal(m.remaining, 25 * 60);

    // Unstarted settings change updates remaining
    m.updateSettings({ focusMinutes: 30 });
    assert.equal(m.remaining, 30 * 60);

    // Paused settings change keeps elapsed progress & clamps shorter duration
    m.start();
    m.pause();
    const pausedRem = m.remaining;
    assert.equal(m.hasStarted, true);
    m.updateSettings({ focusMinutes: 40 });
    assert.ok(Math.abs(m.remaining - pausedRem) < 0.2);
    m.updateSettings({ focusMinutes: 10 });
    assert.ok(Math.abs(m.remaining - 10 * 60) < 0.2);

    // Interruptions log & undo
    m.logInterruption(true);
    m.logInterruption(false);
    assert.equal(m.sessionInternal, 1);
    assert.equal(m.sessionExternal, 1);
    assert.equal(m.undoInterruption(true), true);
    assert.equal(m.undoInterruption(true), false);
    assert.equal(m.stats.internalBreaks, 0);
    assert.equal(m.stats.externalBreaks, 1);

    // Skip mid-focus increments voided
    m.skip();
    assert.equal(m.stats.voided, 1);
    assert.equal(m.phase, Phase.shortBreak);
    m.dispose();

    // Cross-day startup cleanup
    const stateFile = path.join(dir, "state.json");
    fs.writeFileSync(
      stateFile,
      JSON.stringify({
        stats: { day: "2000-01-01", completed: 5, voided: 1, internalBreaks: 2, externalBreaks: 1, focusSeconds: 7500 },
        tasks: [
          { id: "T1", title: "Done yesterday", estimate: 1, done: 1, finished: true },
          { id: "T2", title: "Still todo", estimate: 2, done: 0, finished: false },
        ],
      })
    );

    const m2 = new TimerModel({ dataDir: dir });
    assert.equal(m2.stats.day, localDayString());
    assert.equal(m2.stats.completed, 0);
    assert.equal(m2.tasks.length, 1);
    assert.equal(m2.tasks[0].title, "Still todo");
    assert.ok(DDL.describe({ due: "2000-01-01" }).level === 0);
    m2.dispose();
  } finally {
    rmDir(dir);
  }
});

test("APIServer full endpoints + tools/pomo CLI integration", async () => {
  const dir = makeTmpDir();
  const model = new TimerModel({ dataDir: dir });
  const notion = new NotionSync({ dataDir: dir, model });
  const server = new APIServer({ dataDir: dir, model, notion });
  try {
    const port = await server.start(0);
    const base = `http://127.0.0.1:${port}/v1`;
    const authHeaders = {
      Authorization: `Bearer ${server.config.token}`,
      "Content-Type": "application/json",
    };

    // Health without auth
    const health = await fetch(`${base}/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(await health.json(), { ok: true, app: "Pomodoro" });

    // Unauthorized without token
    const unauth = await fetch(`${base}/status`);
    assert.equal(unauth.status, 401);

    // Invalid due -> 400
    const badDue = await fetch(`${base}/tasks`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ title: "Bad date", due: "not-a-date" }),
    });
    assert.equal(badDue.status, 400);

    // Create, patch, select, complete
    const created = await fetch(`${base}/tasks`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ title: "API 任务", estimate: 2, priority: "P1", due: "明天", select: true }),
    });
    assert.equal(created.status, 201);
    const createdObj = await created.json();
    assert.equal(createdObj.current, true);

    const patched = await fetch(`${base}/tasks/1`, {
      method: "PATCH",
      headers: authHeaders,
      body: JSON.stringify({ due: null, priority: "P0" }),
    });
    assert.equal(patched.status, 200);
    const patchedObj = await patched.json();
    assert.equal(patchedObj.priority, "P0");
    assert.equal(patchedObj.due, undefined);

    // Timer + interruptions + undo + 409
    const started = await fetch(`${base}/timer/start`, { method: "POST", headers: authHeaders });
    assert.equal(started.status, 200);
    assert.equal((await started.json()).running, true);

    const int1 = await fetch(`${base}/interruptions`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ kind: "internal" }),
    });
    assert.equal(int1.status, 200);

    const undo1 = await fetch(`${base}/interruptions`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ kind: "internal", undo: true }),
    });
    assert.equal(undo1.status, 200);

    const undo2 = await fetch(`${base}/interruptions`, {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({ kind: "internal", undo: true }),
    });
    assert.equal(undo2.status, 409);

    // tools/pomo CLI test (async so Node event loop can serve the HTTP request)
    const py = getPythonCmd();
    if (py) {
      const pomoScript = path.resolve(__dirname, "..", "..", "tools", "pomo");
      const env = { ...process.env, POMODORO_DATA_DIR: dir, POMODORO_PORT: String(port) };
      const { stdout: hOut } = await execFileAsync(py, [pomoScript, "health"], { env, encoding: "utf8" });
      assert.match(hOut, /OK \(Pomodoro\)/);

      const { stdout: addOut } = await execFileAsync(py, [pomoScript, "add", "CLI 任务", "-e", "2", "-p", "P1"], {
        env,
        encoding: "utf8",
      });
      assert.match(addOut, /CLI 任务/);

      const { stdout: statusRaw } = await execFileAsync(py, [pomoScript, "--json", "status"], {
        env,
        encoding: "utf8",
      });
      const statusJson = JSON.parse(statusRaw);
      assert.equal(statusJson.running, true);
    }

    // Reset today stats & delete task
    const resetRes = await fetch(`${base}/stats/reset`, { method: "POST", headers: authHeaders });
    assert.equal(resetRes.status, 200);

    // Unconfigured Pomodoro Log -> 409
    const uncfgLog = await fetch(`${base}/notion/log-today`, { method: "POST", headers: authHeaders });
    assert.equal(uncfgLog.status, 409);

    const delRes = await fetch(`${base}/tasks/1`, { method: "DELETE", headers: authHeaders });
    assert.equal(delRes.status, 200);
  } finally {
    await server.stop();
    model.dispose();
    rmDir(dir);
  }
});

test("parseCategories & Category/Event exclusion in schema, filterBody, and parseNotionPage", () => {
  assert.deepEqual(parseCategories("Event, 会议 , ，Activity\n"), ["Event", "会议", "Activity"]);
  assert.deepEqual(parseCategories(""), []);

  // Select property: Category
  const dbSelect = {
    title: [{ plain_text: "Master Tasks" }],
    properties: {
      Name: { type: "title", title: {} },
      Category: { type: "select", select: { options: [{ name: "Task" }, { name: "Event" }] } },
    },
  };
  const sSel = NotionSchema.detect(dbSelect);
  assert.equal(sSel.categoryProp, "Category");
  assert.equal(sSel.categoryType, "select");
  const fbSel = filterBody(7, sSel, ["Event"]);
  assert.deepEqual(fbSel.filter, { property: "Category", select: { does_not_equal: "Event" } });

  const eventPage = {
    id: "ev-1",
    properties: { Name: { title: [{ plain_text: "Club Event" }] }, Category: { select: { name: "event" } } },
  };
  const taskPage = {
    id: "tk-1",
    properties: { Name: { title: [{ plain_text: "Real Task" }] }, Category: { select: { name: "Task" } } },
  };
  assert.equal(parseNotionPage(eventPage, sSel, ["Event"]), null);
  assert.equal(parseNotionPage(taskPage, sSel, ["Event"]).title, "Real Task");

  // Multi-select property: 标签
  const dbMulti = {
    title: [{ plain_text: "板" }],
    properties: {
      Name: { type: "title", title: {} },
      分类: { type: "multi_select", multi_select: { options: [{ name: "Event" }, { name: "Work" }] } },
    },
  };
  const sMulti = NotionSchema.detect(dbMulti);
  assert.equal(sMulti.categoryProp, "分类");
  assert.equal(sMulti.categoryType, "multi_select");
  const fbMulti = filterBody(7, sMulti, ["Event"]);
  assert.deepEqual(fbMulti.filter, { property: "分类", multi_select: { does_not_contain: "Event" } });
  const multiEventPage = {
    id: "ev-2",
    properties: { Name: { title: [{ plain_text: "Demo Day" }] }, 分类: { multi_select: [{ name: "Event" }] } },
  };
  assert.equal(parseNotionPage(multiEventPage, sMulti, ["Event"]), null);
});

test("NotionLogSchema.detect (EN & ZH), cross-day pendingDailyLogs rollover, and upsert + log-today endpoint", async () => {
  const sEn = NotionLogSchema.detect({
    title: [{ plain_text: "Pomodoro Log" }],
    properties: {
      Day: { type: "title", title: {} },
      Date: { type: "date", date: {} },
      Pomodoros: { type: "number", number: {} },
      "Focus Minutes": { type: "number", number: {} },
      "Internal Interruptions": { type: "number", number: {} },
      "External Interruptions": { type: "number", number: {} },
      Voided: { type: "number", number: {} },
      Tasks: { type: "rich_text", rich_text: {} },
    },
  });
  assert.equal(sEn.titleProp, "Day");
  assert.equal(sEn.dateProp, "Date");
  assert.equal(sEn.completedProp, "Pomodoros");
  assert.equal(sEn.focusMinutesProp, "Focus Minutes");
  assert.equal(sEn.internalProp, "Internal Interruptions");
  assert.equal(sEn.externalProp, "External Interruptions");
  assert.equal(sEn.voidedProp, "Voided");
  assert.equal(sEn.tasksProp, "Tasks");

  const sZh = NotionLogSchema.detect({
    title: [{ plain_text: "每日番茄" }],
    properties: {
      标题: { type: "title", title: {} },
      日期: { type: "date", date: {} },
      番茄数: { type: "number", number: {} },
      专注分钟: { type: "number", number: {} },
      内打断: { type: "number", number: {} },
      外打断: { type: "number", number: {} },
      作废: { type: "number", number: {} },
      任务: { type: "rich_text", rich_text: {} },
    },
  });
  assert.equal(sZh.titleProp, "标题");
  assert.equal(sZh.dateProp, "日期");
  assert.equal(sZh.completedProp, "番茄数");
  assert.equal(sZh.tasksProp, "任务");

  const dir = makeTmpDir();
  try {
    // Yesterday active stats should be queued on startup; zero-activity should not
    const stateFile = path.join(dir, "state.json");
    fs.writeFileSync(
      stateFile,
      JSON.stringify({
        stats: {
          day: "2026-11-18",
          completed: 3,
          voided: 1,
          internalBreaks: 2,
          externalBreaks: 0,
          focusSeconds: 4500,
          taskPomodoros: { "Write paper": 2, "Review PR": 1 },
        },
        tasks: [{ id: "T1", title: "Write paper", estimate: 3, done: 2, finished: false }],
      })
    );

    const model = new TimerModel({ dataDir: dir });
    assert.equal(model.pendingDailyLogs.length, 1);
    assert.equal(model.pendingDailyLogs[0].day, "2026-11-18");
    assert.equal(model.pendingDailyLogs[0].completed, 3);
    assert.equal(model.pendingDailyLogs[0].focusMinutes, 75);
    assert.match(model.pendingDailyLogs[0].taskSummary, /Write paper \(2🍅\)/);

    // Verify refreshDay rollover archives today's active stats too
    model.stats.completed = 1;
    model.stats.focusSeconds = 1500;
    model.stats.taskPomodoros = { "Write paper": 1 };
    model.stats.day = "2026-11-19";
    model.refreshDay();
    assert.equal(model.pendingDailyLogs.length, 2);
    assert.equal(model.pendingDailyLogs[1].day, "2026-11-19");

    // Verify focus completion increments taskPomodoros & emits focusCompleted
    let emitted = null;
    model.on("focusCompleted", (entry) => { emitted = entry; });
    model.updateSettings({ focusMinutes: 1 });
    model._advance(true);
    assert.ok(emitted);
    assert.equal(emitted.completed, 1);
    assert.equal(model.stats.taskPomodoros["Write paper"], 1);
    assert.match(emitted.taskSummary, /Write paper/);

    // Mock Notion fetch for upsert: first day returns empty query -> POST /pages; second returns existing -> PATCH
    const reqLog = [];
    const createdPages = new Set();
    const mockFetch = async (url, opts) => {
      const body = opts.body ? JSON.parse(opts.body) : null;
      reqLog.push({ method: opts.method, url, body });
      if (opts.method === "GET" && url.includes("/data_sources/")) {
        return {
          status: 200,
          json: async () => ({
            title: [{ plain_text: "Pomodoro Log" }],
            properties: {
              Day: { type: "title", title: {} },
              Date: { type: "date", date: {} },
              Pomodoros: { type: "number", number: {} },
              "Focus Minutes": { type: "number", number: {} },
              "Internal Interruptions": { type: "number", number: {} },
              "External Interruptions": { type: "number", number: {} },
              Voided: { type: "number", number: {} },
              Tasks: { type: "rich_text", rich_text: {} },
            },
          }),
        };
      }
      if (opts.method === "POST" && url.endsWith("/query")) {
        const day = body?.filter?.date?.equals;
        if (day === "2026-11-19" || createdPages.has(day)) {
          return { status: 200, json: async () => ({ results: [{ id: `row-${day}` }] }) };
        }
        return { status: 200, json: async () => ({ results: [] }) };
      }
      if (opts.method === "POST" && url.endsWith("/pages")) {
        const day = body?.properties?.Date?.date?.start;
        createdPages.add(day);
        return { status: 200, json: async () => ({ id: `row-${day}` }) };
      }
      if (opts.method === "PATCH" && url.includes("/pages/")) {
        return { status: 200, json: async () => ({ id: "patched" }) };
      }
      throw new Error(`Unexpected ${opts.method} ${url}`);
    };

    const sync = new NotionSync({ dataDir: dir, model, fetchFn: mockFetch });
    sync.update({
      token: "test-token",
      logDataSourceID: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      logDatabaseID: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    });

    await sync.syncDailyLogNow(false);
    assert.equal(model.pendingDailyLogs.length, 0);
    assert.ok(reqLog.some((r) => r.method === "POST" && r.url.endsWith("/pages") && r.body.properties.Date.date.start === "2026-11-18"));
    assert.ok(reqLog.some((r) => r.method === "PATCH" && r.url.endsWith("/pages/row-2026-11-19")));

    // HTTP POST /v1/notion/log-today + CLI pomo log-today
    const server = new APIServer({ dataDir: dir, model, notion: sync });
    const port = await server.start(0);
    try {
      const authHeaders = { Authorization: `Bearer ${server.config.token}` };
      const res = await fetch(`http://127.0.0.1:${port}/v1/notion/log-today`, { method: "POST", headers: authHeaders });
      assert.equal(res.status, 200);
      const json = await res.json();
      assert.equal(json.ok, true);
      assert.equal(json.completed, 1);
      assert.ok(createdPages.has(localDayString()));

      const py = getPythonCmd();
      if (py) {
        const pomoScript = path.resolve(__dirname, "..", "..", "tools", "pomo");
        const env = { ...process.env, POMODORO_DATA_DIR: dir, POMODORO_PORT: String(port) };
        const { stdout } = await execFileAsync(py, [pomoScript, "log-today"], { env, encoding: "utf8" });
        assert.match(stdout, new RegExp(localDayString()));
      }
    } finally {
      await server.stop();
    }
    model.dispose();
  } finally {
    rmDir(dir);
  }
});

test("Quick-add tags & top3, inline priority/top3 actions, 7-day history, windowBounds, and CLI history/clear-done", async () => {
  const dir = makeTmpDir();
  const model = new TimerModel({ dataDir: dir });
  const server = new APIServer({ dataDir: dir, model });
  try {
    const p1 = parseQuickAdd("读论文 #Robotics ×3 P1 @明天 !");
    assert.equal(p1.title, "读论文");
    assert.equal(p1.tag, "Robotics");
    assert.equal(p1.estimate, 3);
    assert.equal(p1.priority, 1);
    assert.equal(p1.top3, true);

    const p2 = parseQuickAdd("写实验报告 ★ #课程");
    assert.equal(p2.title, "写实验报告");
    assert.equal(p2.top3, true);
    assert.equal(p2.tag, "课程");

    const t = model.addQuickTask("整理数据 #AI ×2 !");
    assert.equal(t.title, "整理数据");
    assert.equal(t.tag, "AI");
    assert.equal(t.top3, true);
    assert.equal(t.priority, undefined);

    model.toggleTop3(t.id);
    assert.equal(Boolean(model.tasks[0].top3), false);
    model.toggleTop3(t.id);
    assert.equal(Boolean(model.tasks[0].top3), true);

    // Cycle priority: null -> 1 -> 2 -> 3 -> 0 -> null
    model.cyclePriority(t.id);
    assert.equal(model.tasks[0].priority, 1);
    model.cyclePriority(t.id);
    assert.equal(model.tasks[0].priority, 2);
    model.cyclePriority(t.id);
    assert.equal(model.tasks[0].priority, 3);
    model.cyclePriority(t.id);
    assert.equal(model.tasks[0].priority, 0);
    model.cyclePriority(t.id);
    assert.equal(model.tasks[0].priority, undefined);

    // Window bounds persistence
    model.setWindowBounds({ x: 120.4, y: 80.6, width: 480, height: 680 });
    assert.deepEqual(model.windowBounds, { x: 120, y: 81, width: 480, height: 680 });

    // Complete a pomodoro and check history
    model.updateSettings({ focusMinutes: 25 });
    model._advance(true);
    const hist = model.getRecentHistory(7);
    assert.equal(hist.days.length, 7);
    assert.equal(hist.summary.totalCompleted, 1);
    assert.equal(hist.summary.totalFocusMinutes, 25);
    assert.equal(hist.summary.activeDays, 1);
    assert.match(hist.days[6].taskSummary, /整理数据 \(1🍅\)/);

    // Reopen model from disk to verify history & windowBounds persisted
    const model2 = new TimerModel({ dataDir: dir });
    assert.deepEqual(model2.windowBounds, { x: 120, y: 81, width: 480, height: 680 });
    assert.equal(model2.getRecentHistory(7).summary.totalCompleted, 1);
    model2.dispose();

    // Test API endpoints: GET /v1/stats/history, POST /v1/tasks/clear-finished, tag in POST/PATCH
    const port = await server.start(0);
    const base = `http://127.0.0.1:${port}/v1`;
    const authHeaders = {
      Authorization: `Bearer ${server.config.token}`,
      "Content-Type": "application/json",
    };

    const histRes = await fetch(`${base}/stats/history?days=7`, { headers: authHeaders });
    assert.equal(histRes.status, 200);
    const histJson = await histRes.json();
    assert.equal(histJson.days.length, 7);
    assert.equal(histJson.summary.totalCompleted, 1);

    const py = getPythonCmd();
    if (py) {
      const pomoScript = path.resolve(__dirname, "..", "..", "tools", "pomo");
      const env = { ...process.env, POMODORO_DATA_DIR: dir, POMODORO_PORT: String(port) };

      const { stdout: addTagOut } = await execFileAsync(
        py,
        [pomoScript, "add", "阅读文献", "-g", "Paper", "--top3"],
        { env, encoding: "utf8" }
      );
      assert.match(addTagOut, /Paper/);

      const { stdout: histCliOut } = await execFileAsync(py, [pomoScript, "history", "-d", "7"], {
        env,
        encoding: "utf8",
      });
      assert.match(histCliOut, /近 7 天汇总：1 个番茄/);
      assert.match(histCliOut, /整理数据/);

      await execFileAsync(py, [pomoScript, "done", "1"], { env, encoding: "utf8" });
      const { stdout: clearOut } = await execFileAsync(py, [pomoScript, "clear-done"], {
        env,
        encoding: "utf8",
      });
      assert.match(clearOut, /已清除已完成任务（剩余 1 条待办）/);
    } else {
      model.toggleFinished(t.id);
      const clrRes = await fetch(`${base}/tasks/clear-finished`, { method: "POST", headers: authHeaders });
      assert.equal(clrRes.status, 200);
      assert.equal((await clrRes.json()).tasks.length, 0);
    }
  } finally {
    await server.stop();
    model.dispose();
    rmDir(dir);
  }
});
