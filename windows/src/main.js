const path = require("path");
const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  nativeImage,
  nativeTheme,
  ipcMain,
  screen,
  powerSaveBlocker,
  shell,
  clipboard,
} = require("electron");
const { TimerModel, PHASE_TITLES } = require("./model");
const { NotionSync, extractID, parseCategories } = require("./notion");
const { APIServer } = require("./api-server");

const NORMAL_SIZE = { width: 440, height: 640 };
const MINI_SIZE = { width: 320, height: 104 };

const allowMulti = process.env.POMODORO_ALLOW_MULTI === "1";
if (!allowMulti && !app.requestSingleInstanceLock()) {
  app.quit();
}

let win = null;
let tray = null;
let model = null;
let notion = null;
let api = null;
let blockerId = null;

let isMini = false;
let isFullScreen = false;
let autoFullScreened = false;
let fullScreenPending = false;
let fullScreenTimer = null;
let afterExitFullScreen = null;
let savedBounds = null;
let lastPrimaryBounds = null;
let lastTooltip = "";
let lastMenuSignature = "";
let shuttingDown = false;

function isCompactSize(bounds) {
  return bounds.height < 190 || bounds.width < 240;
}

function getDisplays() {
  const primary = screen.getPrimaryDisplay();
  const all = screen.getAllDisplays();
  const secondary = all.find((d) => d.id !== primary.id) || null;
  return { primary, secondary, all };
}

function getCurrentDisplay() {
  if (!win || win.isDestroyed()) return screen.getPrimaryDisplay();
  return screen.getDisplayMatching(win.getBounds());
}

function isOnSecondary() {
  const { primary, all } = getDisplays();
  if (all.length <= 1) return false;
  return getCurrentDisplay().id !== primary.id;
}

function centeredBounds(size, workArea) {
  const w = Math.min(size.width, workArea.width);
  const h = Math.min(size.height, workArea.height);
  return {
    x: Math.round(workArea.x + (workArea.width - w) / 2),
    y: Math.round(workArea.y + (workArea.height - h) / 2),
    width: w,
    height: h,
  };
}

function constrainBounds(bounds, workArea) {
  const width = Math.min(bounds.width, workArea.width);
  const height = Math.min(bounds.height, workArea.height);
  const x = Math.max(workArea.x, Math.min(bounds.x, workArea.x + workArea.width - width));
  const y = Math.max(workArea.y, Math.min(bounds.y, workArea.y + workArea.height - height));
  return { x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) };
}

function getWindowState() {
  const { secondary } = getDisplays();
  return {
    isMini,
    isFullScreen,
    isOnSecondary: isOnSecondary(),
    secondaryAvailable: Boolean(secondary),
  };
}

function getFullState() {
  return {
    timer: model.getSnapshot(),
    notion: notion.getStatus(),
    api: api.getStatus(),
    windowState: getWindowState(),
    systemDark: nativeTheme.shouldUseDarkColors,
    platform: process.platform,
  };
}

function broadcastState() {
  if (win && !win.isDestroyed()) {
    win.webContents.send("pomo:state", getFullState());
  }
  updateTray();
  syncPowerBlocker();
}

function syncPowerBlocker() {
  if (!model) return;
  if (model.isRunning) {
    if (blockerId === null) {
      blockerId = powerSaveBlocker.start("prevent-display-sleep");
    }
  } else if (blockerId !== null) {
    if (powerSaveBlocker.isStarted(blockerId)) {
      powerSaveBlocker.stop(blockerId);
    }
    blockerId = null;
  }
}

function applyOnTop() {
  if (!win || win.isDestroyed() || !model) return;
  const onTop = Boolean(isMini || model.settings.alwaysOnTop);
  win.setAlwaysOnTop(onTop, "floating");
}

function rememberPrimaryBounds() {
  if (!win || win.isDestroyed()) return;
  if (isFullScreen || isMini || isOnSecondary()) return;
  const b = win.getBounds();
  if (!isCompactSize(b)) {
    lastPrimaryBounds = b;
  }
}

function requestAutoFullScreen() {
  if (fullScreenPending) return;
  fullScreenPending = true;
  if (fullScreenTimer) clearTimeout(fullScreenTimer);
  fullScreenTimer = setTimeout(() => {
    fullScreenTimer = null;
    if (!win || win.isDestroyed() || !isOnSecondary() || isFullScreen) {
      fullScreenPending = false;
      return;
    }
    autoFullScreened = true;
    win.setFullScreen(true);
    setTimeout(() => {
      fullScreenPending = false;
    }, 1500);
  }, 350);
}

function handleScreenStateChange() {
  if (!win || win.isDestroyed() || !model) return;
  const onSec = isOnSecondary();
  if (onSec) {
    if (isMini) {
      isMini = false;
      applyOnTop();
    }
    if (model.settings.autoFullScreenOnSecondary && !isFullScreen) {
      requestAutoFullScreen();
    }
  } else if (isFullScreen && autoFullScreened) {
    win.setFullScreen(false);
  }
  broadcastState();
}

function sendToSecondary() {
  if (!win || win.isDestroyed()) return;
  const { secondary } = getDisplays();
  if (!secondary) return;
  if (isFullScreen) {
    afterExitFullScreen = () => sendToSecondary();
    win.setFullScreen(false);
    return;
  }
  if (isMini) setMini(false);
  rememberPrimaryBounds();
  win.setBounds(centeredBounds(NORMAL_SIZE, secondary.workArea));
  requestAutoFullScreen();
  broadcastState();
}

function sendToPrimary() {
  if (!win || win.isDestroyed()) return;
  if (isFullScreen) {
    afterExitFullScreen = () => sendToPrimary();
    autoFullScreened = false;
    win.setFullScreen(false);
    return;
  }
  const { primary } = getDisplays();
  const wa = primary.workArea;
  const target = lastPrimaryBounds ? constrainBounds(lastPrimaryBounds, wa) : centeredBounds(NORMAL_SIZE, wa);
  win.setBounds(target);
  broadcastState();
}

function setMini(on) {
  if (!win || win.isDestroyed()) return;
  if (on) {
    if (isMini || isFullScreen) return;
    const current = win.getBounds();
    savedBounds = isCompactSize(current) ? null : current;
    isMini = true;
    applyOnTop();
    const wa = getCurrentDisplay().workArea;
    win.setBounds({
      x: Math.round(wa.x + wa.width - MINI_SIZE.width - 16),
      y: Math.round(wa.y + 16),
      width: MINI_SIZE.width,
      height: MINI_SIZE.height,
    });
  } else {
    const current = win.getBounds();
    const wa = getCurrentDisplay().workArea;
    let target = null;
    if (isMini && savedBounds && !isCompactSize(savedBounds)) {
      target = savedBounds;
    } else if (lastPrimaryBounds && !isCompactSize(lastPrimaryBounds)) {
      target = lastPrimaryBounds;
    } else {
      target = {
        x: current.x + current.width - NORMAL_SIZE.width,
        y: current.y,
        width: NORMAL_SIZE.width,
        height: NORMAL_SIZE.height,
      };
    }
    isMini = false;
    savedBounds = null;
    applyOnTop();
    win.setBounds(constrainBounds(target, wa));
  }
  broadcastState();
}

function showMainWindow() {
  if (!win || win.isDestroyed()) return;
  if (win.isMinimized()) win.restore();
  if (!win.isVisible()) win.show();
  win.focus();
}

function getTrayIcon() {
  if (process.platform === "win32") {
    return nativeImage.createFromPath(path.join(__dirname, "..", "assets", "icon.ico"));
  }
  return nativeImage
    .createFromPath(path.join(__dirname, "..", "assets", "tray.png"))
    .resize({ width: 18, height: 18 });
}

function syncTrayEnabled() {
  if (!model) return;
  if (!model.settings.showInTray) {
    if (tray) {
      tray.destroy();
      tray = null;
      lastTooltip = "";
      lastMenuSignature = "";
    }
    return;
  }
  if (!tray) {
    tray = new Tray(getTrayIcon());
    tray.on("click", () => showMainWindow());
    lastTooltip = "";
    lastMenuSignature = "";
  }
  updateTray();
}

function updateTray() {
  if (!tray || !model) return;
  const snap = model.getSnapshot();
  const curTask = snap.tasks.find((t) => t.id === snap.currentTaskID);
  const stateWord = snap.running ? "进行中" : snap.paused ? "已暂停" : "未开始";
  let tip = `番茄钟 · ${snap.phaseTitle} ${snap.timeText}（${stateWord}）`;
  if (snap.phase === "focus" && curTask) {
    tip += `\n当前任务：${curTask.title}`;
  }
  if (tip !== lastTooltip) {
    lastTooltip = tip;
    tray.setToolTip(tip);
  }

  const ws = getWindowState();
  const sig = JSON.stringify([
    snap.phase,
    snap.running,
    snap.paused,
    curTask?.title || "",
    ws.isMini,
    ws.isOnSecondary,
    ws.secondaryAvailable,
  ]);
  if (sig === lastMenuSignature) return;
  lastMenuSignature = sig;

  const toggleLabel = snap.running
    ? "暂停"
    : snap.paused
      ? "继续"
      : snap.phase === "focus"
        ? "开始专注"
        : "开始休息";

  const template = [
    { label: `${PHASE_TITLES[snap.phase]} · ${stateWord}`, enabled: false },
    ...(snap.phase === "focus" && curTask ? [{ label: `当前：${curTask.title}`, enabled: false }] : []),
    { type: "separator" },
    { label: toggleLabel, click: () => model.toggle() },
    { label: "重置", click: () => model.reset() },
    { label: snap.phase === "focus" ? "放弃本番茄" : "结束休息", click: () => model.skip() },
    ...(snap.phase === "focus"
      ? [
          { label: "记录内部打断（-）", click: () => model.logInterruption(true) },
          { label: "记录外部打断（=）", click: () => model.logInterruption(false) },
        ]
      : []),
    { type: "separator" },
    { label: "显示主窗口", click: () => showMainWindow() },
    {
      label: "迷你悬浮窗",
      type: "checkbox",
      checked: ws.isMini,
      click: () => {
        showMainWindow();
        setMini(!isMini);
      },
    },
    ...(ws.secondaryAvailable
      ? [
          ws.isOnSecondary
            ? { label: "移回主屏", click: () => sendToPrimary() }
            : { label: "发送到副屏并全屏", click: () => sendToSecondary() },
        ]
      : []),
    { type: "separator" },
    { label: "退出番茄钟", click: () => app.quit() },
  ];
  tray.setContextMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  const appearance = model.settings.appearance;
  const dark = appearance === "dark" || (appearance === "system" && nativeTheme.shouldUseDarkColors);
  win = new BrowserWindow({
    width: NORMAL_SIZE.width,
    height: NORMAL_SIZE.height,
    minWidth: 260,
    minHeight: 84,
    frame: false,
    backgroundColor: dark ? "#1F1C18" : "#F7F2E7",
    title: "番茄钟",
    icon: path.join(__dirname, "..", "assets", process.platform === "win32" ? "icon.ico" : "icon.png"),
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, "renderer", "index.html"));

  win.once("ready-to-show", () => {
    if (!win || win.isDestroyed()) return;
    applyOnTop();
    win.show();
    broadcastState();
  });

  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//i.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });

  win.on("focus", () => {
    win?.flashFrame(false);
  });

  win.on("moved", () => {
    rememberPrimaryBounds();
    handleScreenStateChange();
  });

  win.on("resized", () => {
    if (!win || win.isDestroyed()) return;
    const compact = isCompactSize(win.getBounds());
    if (compact !== isMini) {
      isMini = compact;
      applyOnTop();
      broadcastState();
    }
    rememberPrimaryBounds();
  });

  win.on("enter-full-screen", () => {
    isFullScreen = true;
    fullScreenPending = false;
    broadcastState();
  });

  win.on("leave-full-screen", () => {
    isFullScreen = false;
    autoFullScreened = false;
    if (afterExitFullScreen) {
      const fn = afterExitFullScreen;
      afterExitFullScreen = null;
      setTimeout(fn, 250);
    }
    broadcastState();
  });

  win.on("closed", () => {
    win = null;
  });
}

function registerIPC() {
  ipcMain.handle("pomo:get-state", () => getFullState());

  ipcMain.handle("pomo:timer", (_e, action) => {
    if (action === "toggle") model.toggle();
    else if (action === "start") model.start();
    else if (action === "pause") model.pause();
    else if (action === "reset") model.reset();
    else if (action === "skip") model.skip();
  });

  ipcMain.handle("pomo:timer-phase", (_e, phase) => model.selectPhase(phase));
  ipcMain.handle("pomo:interrupt", (_e, { isInternal, undo }) => {
    if (undo) model.undoInterruption(Boolean(isInternal));
    else model.logInterruption(Boolean(isInternal));
  });
  ipcMain.handle("pomo:reset-today", () => model.resetToday());

  ipcMain.handle("pomo:task-add-quick", (_e, raw) => model.addQuickTask(raw));
  ipcMain.handle("pomo:task-select", (_e, id) => model.selectTask(id));
  ipcMain.handle("pomo:task-toggle", (_e, id) => model.toggleFinished(id));
  ipcMain.handle("pomo:task-remove", (_e, id) => model.removeTask(id));
  ipcMain.handle("pomo:task-estimate", (_e, { id, delta }) => model.adjustEstimate(id, delta));
  ipcMain.handle("pomo:task-clear-finished", () => model.clearFinished());

  ipcMain.handle("pomo:settings-update", (_e, patch) => {
    model.updateSettings(patch);
    broadcastState();
  });

  ipcMain.handle("pomo:notion-save-sync", async (_e, { token, tokenKeep, target, excludedText }) => {
    const cleanTarget = String(target || "").trim();
    notion.update((cfg) => {
      if (!tokenKeep) {
        cfg.token = String(token || "").trim();
      }
      if (cleanTarget !== (cfg.dataSourceID || cfg.databaseID)) {
        const extracted = extractID(cleanTarget);
        cfg.dataSourceID = extracted;
        cfg.databaseID = extracted;
      }
      if (typeof excludedText === "string") {
        cfg.excludedCategories = parseCategories(excludedText);
      }
    });
    try {
      await notion.sync();
    } catch {
      // error status is stored on notion.lastError and broadcast to UI
    }
    return notion.getStatus();
  });

  ipcMain.handle("pomo:notion-log-save-sync", async (_e, { token, tokenKeep, logTarget }) => {
    const cleanTarget = String(logTarget || "").trim();
    notion.update((cfg) => {
      if (!tokenKeep) {
        cfg.token = String(token || "").trim();
      }
      if (cleanTarget !== (cfg.logDataSourceID || cfg.logDatabaseID)) {
        const extracted = extractID(cleanTarget);
        cfg.logDataSourceID = extracted;
        cfg.logDatabaseID = extracted;
      }
    });
    if (notion.getStatus().logConfigured) {
      try {
        await notion.syncDailyLogNow(true);
      } catch {
        // error status is stored on notion.lastLogError and broadcast to UI
      }
    }
    return notion.getStatus();
  });

  ipcMain.handle("pomo:notion-log-now", async () => {
    try {
      await notion.syncDailyLogNow(true);
    } catch {
      // error status is broadcast
    }
    return notion.getStatus();
  });

  ipcMain.handle("pomo:notion-sync", async () => {
    try {
      await notion.sync();
    } catch {
      // error status is broadcast
    }
    return notion.getStatus();
  });

  ipcMain.handle("pomo:notion-update", (_e, patch) => {
    notion.update(patch);
    return notion.getStatus();
  });

  ipcMain.handle("pomo:api-copy-token", () => {
    clipboard.writeText(api.config.token);
    return true;
  });

  ipcMain.handle("pomo:win-secondary", () => sendToSecondary());
  ipcMain.handle("pomo:win-primary", () => sendToPrimary());
  ipcMain.handle("pomo:win-mini", (_e, on) => setMini(Boolean(on)));
  ipcMain.handle("pomo:win-fullscreen", () => {
    if (!win || win.isDestroyed()) return;
    autoFullScreened = false;
    win.setFullScreen(!isFullScreen);
  });
  ipcMain.handle("pomo:win-minimize", () => win?.minimize());
  ipcMain.handle("pomo:win-close", () => app.quit());
  ipcMain.handle("pomo:open-external", (_e, url) => {
    if (typeof url === "string" && /^https?:\/\//i.test(url)) {
      return shell.openExternal(url);
    }
    return false;
  });
}

app.on("second-instance", () => showMainWindow());

app.whenReady().then(async () => {
  model = new TimerModel();
  notion = new NotionSync({ model });
  api = new APIServer({ model, notion });

  try {
    await api.start();
  } catch (err) {
    console.error("API server failed to start:", err.message);
  }

  model.on("change", () => broadcastState());
  model.on("traySettingChanged", () => syncTrayEnabled());
  model.on("onTopChanged", () => applyOnTop());
  model.on("phaseComplete", (info) => {
    if (win && !win.isDestroyed()) {
      if (!win.isFocused()) win.flashFrame(true);
      win.webContents.send("pomo:phase-complete", info);
    }
    broadcastState();
  });
  notion.on("change", () => broadcastState());

  nativeTheme.on("updated", () => broadcastState());
  screen.on("display-added", () => handleScreenStateChange());
  screen.on("display-removed", () => handleScreenStateChange());

  registerIPC();
  syncTrayEnabled();
  createWindow();
  notion.start(model);
});

app.on("window-all-closed", () => {
  app.quit();
});

app.on("before-quit", async (e) => {
  if (shuttingDown) return;
  shuttingDown = true;
  e.preventDefault();
  try {
    if (fullScreenTimer) clearTimeout(fullScreenTimer);
    if (blockerId !== null && powerSaveBlocker.isStarted(blockerId)) {
      powerSaveBlocker.stop(blockerId);
      blockerId = null;
    }
    if (tray) {
      tray.destroy();
      tray = null;
    }
    notion?.stop();
    model?.dispose();
    if (api) await api.stop();
  } finally {
    app.exit(0);
  }
});
