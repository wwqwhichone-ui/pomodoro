const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("pomo", {
  getInitialState: () => ipcRenderer.invoke("pomo:get-state"),
  onState: (handler) => {
    const fn = (_event, state) => handler(state);
    ipcRenderer.on("pomo:state", fn);
    return () => ipcRenderer.removeListener("pomo:state", fn);
  },
  onPhaseComplete: (handler) => {
    const fn = (_event, info) => handler(info);
    ipcRenderer.on("pomo:phase-complete", fn);
    return () => ipcRenderer.removeListener("pomo:phase-complete", fn);
  },

  toggle: () => ipcRenderer.invoke("pomo:timer", "toggle"),
  start: () => ipcRenderer.invoke("pomo:timer", "start"),
  pause: () => ipcRenderer.invoke("pomo:timer", "pause"),
  reset: () => ipcRenderer.invoke("pomo:timer", "reset"),
  skip: () => ipcRenderer.invoke("pomo:timer", "skip"),
  selectPhase: (phase) => ipcRenderer.invoke("pomo:timer-phase", phase),
  logInterruption: (isInternal) => ipcRenderer.invoke("pomo:interrupt", { isInternal, undo: false }),
  undoInterruption: (isInternal) => ipcRenderer.invoke("pomo:interrupt", { isInternal, undo: true }),
  resetToday: () => ipcRenderer.invoke("pomo:reset-today"),

  addQuickTask: (raw) => ipcRenderer.invoke("pomo:task-add-quick", raw),
  selectTask: (id) => ipcRenderer.invoke("pomo:task-select", id),
  toggleFinished: (id) => ipcRenderer.invoke("pomo:task-toggle", id),
  removeTask: (id) => ipcRenderer.invoke("pomo:task-remove", id),
  adjustEstimate: (id, delta) => ipcRenderer.invoke("pomo:task-estimate", { id, delta }),
  toggleTop3: (id) => ipcRenderer.invoke("pomo:task-top3", id),
  cyclePriority: (id) => ipcRenderer.invoke("pomo:task-priority", id),
  renameTask: (id, title) => ipcRenderer.invoke("pomo:task-rename", { id, title }),
  clearFinished: () => ipcRenderer.invoke("pomo:task-clear-finished"),

  updateSettings: (patch) => ipcRenderer.invoke("pomo:settings-update", patch),

  saveAndSyncNotion: (payload) => ipcRenderer.invoke("pomo:notion-save-sync", payload),
  saveAndSyncLog: (payload) => ipcRenderer.invoke("pomo:notion-log-save-sync", payload),
  syncNotion: () => ipcRenderer.invoke("pomo:notion-sync"),
  syncDailyLogNow: () => ipcRenderer.invoke("pomo:notion-log-now"),
  updateNotionConfig: (patch) => ipcRenderer.invoke("pomo:notion-update", patch),

  copyApiToken: () => ipcRenderer.invoke("pomo:api-copy-token"),

  sendToSecondary: () => ipcRenderer.invoke("pomo:win-secondary"),
  sendToPrimary: () => ipcRenderer.invoke("pomo:win-primary"),
  setMini: (on) => ipcRenderer.invoke("pomo:win-mini", Boolean(on)),
  toggleFullScreen: () => ipcRenderer.invoke("pomo:win-fullscreen"),
  minimizeWindow: () => ipcRenderer.invoke("pomo:win-minimize"),
  closeWindow: () => ipcRenderer.invoke("pomo:win-close"),
  openExternal: (url) => ipcRenderer.invoke("pomo:open-external", url),
});
