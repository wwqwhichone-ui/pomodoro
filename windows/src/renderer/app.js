(() => {
  const appEl = document.getElementById("app");
  const popoverLayer = document.getElementById("popover-layer");
  const grainCanvas = document.getElementById("paper-grain");
  const flashOverlay = document.getElementById("flash-overlay");

  let state = null;
  let activePopover = null; // null | "settings" | "tasks"
  let settingsTab = 0; // 0: 计时, 1: 同步与接口, 2: 方法
  let confirmResetToday = false;
  let copiedToken = false;
  let expandCurrentTitle = false;
  let lastCurrentTaskID = null;
  const expandedFinishedIDs = new Set();

  let notionTokenDraft = "";
  let notionTargetDraft = "";
  let lastLayoutKind = null;
  let lastGrainKey = "";
  let taskDraft = "";
  let audioCtx = null;

  // SVG icon helpers (crisp 1.6px stroke matching SF Symbols)
  const ICONS = {
    play: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4.2 2.8a.6.6 0 0 1 .9-.52l8.1 4.86a.6.6 0 0 1 0 1.04l-8.1 4.86A.6.6 0 0 1 4.2 12.5V2.8z"/></svg>',
    pause: '<svg viewBox="0 0 16 16" fill="currentColor"><rect x="3.5" y="2.5" width="3.2" height="11" rx="0.8"/><rect x="9.3" y="2.5" width="3.2" height="11" rx="0.8"/></svg>',
    reset: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3.2 7.5A4.8 4.8 0 1 1 4.6 11"/><path d="M3.2 3.8v3.8h3.8"/></svg>',
    skip: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M3 3.2a.5.5 0 0 1 .76-.43l6.6 4.05a.5.5 0 0 1 0 .86l-6.6 4.05A.5.5 0 0 1 3 11.3V3.2z"/><rect x="11.5" y="3" width="1.8" height="10" rx="0.6"/></svg>',
    check: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3.2 8.4l3.1 3.2 6.5-7"/></svg>',
    plus: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M8 3.2v9.6M3.2 8h9.6"/></svg>',
    minus: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M3.4 8h9.2"/></svg>',
    star: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5l1.95 4.02 4.43.62-3.22 3.12.78 4.41L8 11.56l-3.94 2.11.78-4.41L1.62 6.14l4.43-.62L8 1.5z"/></svg>',
    sync: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M13 4.8A5.4 5.4 0 0 0 3.7 4.4"/><path d="M3 2.5v2.7h2.7"/><path d="M3 11.2a5.4 5.4 0 0 0 9.3.4"/><path d="M13 13.5v-2.7h-2.7"/></svg>',
    warn: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2.4L14.2 13H1.8L8 2.4z"/><path d="M8 6.4v3.4"/><circle cx="8" cy="11.4" r="0.6" fill="currentColor"/></svg>',
    display: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><rect x="1.8" y="3" width="12.4" height="8.4" rx="1.2"/><path d="M5.5 13.5h5"/></svg>',
    laptop: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><rect x="2.6" y="3" width="10.8" height="7.5" rx="1"/><path d="M1.4 12.6h13.2"/></svg>',
    pip: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="12" height="10" rx="1.4"/><rect x="7.5" y="7.5" width="5" height="3.8" rx="0.6" fill="currentColor" fill-opacity="0.25"/></svg>',
    pin: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 3h5l-.8 4.2 1.8 1.8H4.5l1.8-1.8L5.5 3z"/><path d="M8 9v4.5"/></svg>',
    pinFill: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M5.2 2.5h5.6l-.8 4.4 2 2H4l2-2-.8-4.4z"/><path d="M7.3 8.8h1.4v4.7H7.3z"/></svg>',
    expand: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5L9.2 6.8M2.5 13.5l4.3-4.3"/></svg>',
    collapse: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M13.2 6.2H9.8V2.8M2.8 9.8h3.4v3.4M9.8 6.2l3.7-3.7M6.2 9.8l-3.7 3.7"/></svg>',
    sliders: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M2.5 4.2h11M2.5 8h11M2.5 11.8h11"/><circle cx="5.5" cy="4.2" r="1.3" fill="var(--bg)"/><circle cx="10.5" cy="8" r="1.3" fill="var(--bg)"/><circle cx="6.8" cy="11.8" r="1.3" fill="var(--bg)"/></svg>',
    minimize: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M3.5 8.5h9"/></svg>',
    close: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M4 4l8 8M12 4l-8 8"/></svg>',
    list: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M5.2 4.2h8M5.2 8h8M5.2 11.8h8"/><circle cx="2.7" cy="4.2" r="0.7" fill="currentColor"/><circle cx="2.7" cy="8" r="0.7" fill="currentColor"/><circle cx="2.7" cy="11.8" r="0.7" fill="currentColor"/></svg>',
    chevronDown: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6l4 4 4-4"/></svg>',
    arrowRight: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8h10M9 4l4 4-4 4"/></svg>',
    arrowDownRight: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4l8 8M12 6v6H6"/></svg>',
    arrowUpRight: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12l8-8M6 4h6v6"/></svg>',
    undo: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 4.5H3v2.5"/><path d="M3.2 4.7a5 5 0 1 1-.2 5.8"/></svg>',
    copy: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><rect x="5.5" y="5.5" width="7.5" height="8" rx="1.2"/><path d="M3.2 10.5V3.8A1.3 1.3 0 0 1 4.5 2.5h5.8"/></svg>',
  };

  function esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function svgIcon(name, size) {
    return `<span style="display:inline-flex;width:${size}px;height:${size}px;align-items:center;justify-content:center;flex-shrink:0;">${ICONS[name] || ""}</span>`;
  }

  function formatDuration(sec) {
    const m = Math.floor((sec || 0) / 60);
    return m >= 60 ? `${Math.floor(m / 60)} 小时 ${m % 60} 分` : `${m} 分钟`;
  }

  function isDarkTheme() {
    if (!state) return false;
    const app = state.timer.settings.appearance;
    if (app === "dark") return true;
    if (app === "light") return false;
    return Boolean(state.systemDark);
  }

  function drawPaperGrain() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const dark = isDarkTheme();
    const key = `${w}x${h}:${dark}`;
    if (key === lastGrainKey) return;
    lastGrainKey = key;

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    grainCanvas.width = Math.max(1, Math.floor(w * dpr));
    grainCanvas.height = Math.max(1, Math.floor(h * dpr));
    const ctx = grainCanvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    let seed = 0x9e3779b97f4a7c15n;
    const mask = (1n << 64n) - 1n;
    const mul = 6364136223846793005n;
    const inc = 1442695040888963407n;
    const rnd = () => {
      seed = (seed * mul + inc) & mask;
      return Number(seed >> 33n) / 2147483648;
    };

    const n = Math.min(18000, Math.floor((w * h) / 140));
    const baseRGB = dark ? "255,255,255" : "90,74,48";
    for (let i = 0; i < n; i++) {
      const x = rnd() * w;
      const y = rnd() * h;
      const a = 0.025 + rnd() * 0.04;
      ctx.fillStyle = `rgba(${baseRGB},${a.toFixed(3)})`;
      ctx.fillRect(x, y, 1, 1);
    }
  }

  function playChime() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      if (!audioCtx) audioCtx = new Ctx();
      if (audioCtx.state === "suspended") audioCtx.resume();
      const now = audioCtx.currentTime;
      for (let i = 0; i < 3; i++) {
        const start = now + i * 0.85;
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = "sine";
        osc.frequency.setValueAtTime(1046.5, start);
        gain.gain.setValueAtTime(0.0001, start);
        gain.gain.exponentialRampToValueAtTime(0.16, start + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.72);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start(start);
        osc.stop(start + 0.75);
      }
    } catch {
      // ignore audio errors
    }
  }

  function flashScreen() {
    for (let i = 0; i < 3; i++) {
      setTimeout(() => {
        flashOverlay.classList.add("active");
        setTimeout(() => flashOverlay.classList.remove("active"), 260);
      }, i * 600);
    }
  }

  function getLayoutKind(w, h) {
    if (h < 190 || w < 240) return "mini";
    return w / Math.max(h, 1) >= 1.12 ? "landscape" : "portrait";
  }

  // MARK: Component HTML builders

  function renderToolbar(s) {
    const ws = state.windowState;
    const t = state.timer;
    const iconSize = 28 * s;
    const symSize = 12.5 * s;
    const btnStyle = `width:${iconSize}px;height:${iconSize}px;`;
    const dimmed = t.running && activePopover !== "settings" ? "dimmed" : "";

    const parts = [];
    if (ws.isOnSecondary) {
      parts.push(`<button class="tool-icon pressable no-drag" data-act="win-primary" title="移回主屏" style="${btnStyle}">${svgIcon("laptop", symSize)}</button>`);
    } else if (ws.secondaryAvailable) {
      parts.push(`<button class="tool-icon pressable no-drag" data-act="win-secondary" title="发送到副屏并全屏" style="${btnStyle}">${svgIcon("display", symSize)}</button>`);
    }
    if (!ws.isFullScreen) {
      parts.push(`<button class="tool-icon pressable no-drag" data-act="win-mini" title="迷你悬浮窗" style="${btnStyle}">${svgIcon("pip", symSize)}</button>`);
      const pinIcon = t.settings.alwaysOnTop ? "pinFill" : "pin";
      const pinTitle = t.settings.alwaysOnTop ? "取消置顶" : "窗口置顶";
      parts.push(`<button class="tool-icon pressable no-drag" data-act="toggle-ontop" title="${pinTitle}" style="${btnStyle}">${svgIcon(pinIcon, symSize)}</button>`);
    }
    parts.push(`<button class="tool-icon pressable no-drag" data-act="win-fullscreen" title="全屏 / 退出全屏（F11）" style="${btnStyle}">${svgIcon(ws.isFullScreen ? "collapse" : "expand", symSize)}</button>`);
    parts.push(`<button class="tool-icon pressable no-drag" data-act="open-settings" title="设置" style="${btnStyle}">${svgIcon("sliders", symSize)}</button>`);
    if (!ws.isFullScreen) {
      parts.push(`<button class="tool-icon pressable no-drag" data-act="win-minimize" title="最小化" style="${btnStyle}">${svgIcon("minimize", symSize)}</button>`);
      parts.push(`<button class="tool-icon pressable no-drag close-btn" data-act="win-close" title="关闭" style="${btnStyle}">${svgIcon("close", symSize)}</button>`);
    }

    return `<div class="toolbar no-drag ${dimmed}" style="gap:${6 * s}px;">${parts.join("")}</div>`;
  }

  function renderPhasePicker(fontSize) {
    const cur = state.timer.phase;
    const items = [
      ["focus", "专注"],
      ["shortBreak", "短休息"],
      ["longBreak", "长休息"],
    ];
    return `<div class="capsule-tabs no-drag" style="gap:${fontSize * 0.3}px;">${items
      .map(([id, title]) => {
        const active = cur === id ? "active" : "";
        return `<button class="capsule-tab ${active}" data-act="phase" data-phase="${id}" style="font-size:${fontSize}px;padding:${fontSize * 0.42}px ${fontSize * 0.95}px;">${title}</button>`;
      })
      .join("")}</div>`;
  }

  function renderRingView(D) {
    const t = state.timer;
    const p = t.progress;
    const line = Math.max(2.5, D * 0.012);
    const r = (D - line) / 2;
    const cx = D / 2;
    const cy = D / 2;
    const C = 2 * Math.PI * r;
    const gap = p > 0.004 && p < 0.996 ? 0.007 : 0;

    const doneLen = Math.max(0, (p - gap) * C);
    const doneOffset = -((gap / 2) * C);
    const restStart = Math.min(1, p + gap / 2);
    const restEnd = 1 - gap / 2;
    const restLen = Math.max(0, (restEnd - restStart) * C);
    const restOffset = -(restStart * C);

    const innerR = (D * 0.74) / 2;
    const totalMinutes = Math.max(1, Math.round(t.total / 60));
    const step = totalMinutes <= 30 ? 5 : totalMinutes <= 60 ? 10 : 15;
    const markR = D * 0.43;
    const marks = [];
    for (let m = 0; m < totalMinutes; m += step) {
      const f = m / totalMinutes;
      const a = f * 2 * Math.PI - Math.PI / 2;
      const mx = cx + Math.cos(a) * markR;
      const my = cy + Math.sin(a) * markR;
      const passed = f <= p && p > 0;
      marks.push(
        `<text x="${mx.toFixed(1)}" y="${my.toFixed(1)}" text-anchor="middle" dominant-baseline="central" font-size="${(D * 0.03).toFixed(1)}" font-weight="500" fill="${passed ? "var(--ink)" : "var(--faint)"}" style="font-variant-numeric:tabular-nums;">${m}</text>`
      );
    }

    const label =
      t.phase === "focus"
        ? `专注 · 第 ${t.stats.completed + 1} 个番茄`
        : t.phase === "shortBreak"
          ? "短休息"
          : "长休息";
    const statusIcon = t.running ? "arrowDownRight" : t.hasStarted ? "pause" : "arrowRight";
    const statusText = t.running
      ? `预计 ${t.projectedEndHM} 结束`
      : t.hasStarted
        ? "已暂停"
        : t.phase === "focus"
          ? "准备专注"
          : "准备休息";
    const statusColor = t.running ? "var(--accent)" : "var(--gray)";
    const curTask = t.tasks.find((x) => x.id === t.currentTaskID);
    const caption = t.phase === "focus" ? (curTask ? curTask.title : "一次只做一件事") : t.breakTip;

    return `
      <div class="ring-wrap" style="width:${D}px;height:${D}px;">
        <svg class="ring-svg" viewBox="0 0 ${D} ${D}">
          <g transform="rotate(-90 ${cx} ${cy})">
            ${
              restLen > 0.5
                ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="var(--ink)" stroke-width="${line}" stroke-dasharray="${restLen.toFixed(2)} ${C.toFixed(2)}" stroke-dashoffset="${restOffset.toFixed(2)}" />`
                : ""
            }
            ${
              doneLen > 0.5
                ? `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="var(--accent)" stroke-width="${line}" stroke-dasharray="${doneLen.toFixed(2)} ${C.toFixed(2)}" stroke-dashoffset="${doneOffset.toFixed(2)}" />`
                : ""
            }
          </g>
          <circle cx="${cx}" cy="${cy}" r="${innerR}" fill="none" stroke="var(--line)" stroke-width="1" />
          ${marks.join("")}
        </svg>
        <div class="ring-center" style="gap:${D * 0.012}px;max-width:${D * 0.58}px;">
          <div style="font-size:${D * 0.043}px;font-weight:500;color:var(--gray);">${esc(label)}</div>
          <div class="display-num" data-slot="ring-time" style="font-size:${D * 0.27}px;color:var(--ink);">${t.timeText}</div>
          <div class="ring-status" style="gap:${D * 0.012}px;font-size:${D * 0.043}px;color:${statusColor};">
            ${svgIcon(statusIcon, D * 0.036)}
            <span>${esc(statusText)}</span>
          </div>
          <div class="serif-text ring-caption" style="font-size:${D * 0.05}px;margin-top:${D * 0.03}px;max-width:${D * 0.56}px;">${esc(caption)}</div>
        </div>
      </div>`;
  }

  function renderControls(D) {
    const t = state.timer;
    const h = D * 0.15;
    const primaryTitle = t.running
      ? "暂停"
      : t.hasStarted
        ? "继续"
        : t.phase === "focus"
          ? "开始专注"
          : "开始休息";
    const skipHelp = t.phase === "focus" ? "放弃这个番茄（中途放弃记为作废）" : "结束休息";

    return `
      <div class="controls-row no-drag" style="gap:${D * 0.05}px;">
        <button class="outline-circle-btn pressable" data-act="reset" title="重置（Ctrl+R）" style="width:${h}px;height:${h}px;border-width:${Math.max(1, h * 0.028)}px;">
          ${svgIcon("reset", h * 0.4)}
        </button>
        <button class="primary-pill-btn pressable" data-act="toggle" title="开始 / 暂停（空格）" style="height:${h}px;min-width:${h * 2.9}px;padding:0 ${h * 0.62}px;gap:${h * 0.18}px;font-size:${h * 0.33}px;">
          ${svgIcon(t.running ? "pause" : "play", h * 0.32)}
          <span>${primaryTitle}</span>
        </button>
        <button class="outline-circle-btn pressable" data-act="skip" title="${skipHelp}" style="width:${h}px;height:${h}px;border-width:${Math.max(1, h * 0.028)}px;">
          ${svgIcon("skip", h * 0.4)}
        </button>
      </div>`;
  }

  function renderSetProgress(s) {
    const { streak, longEvery } = state.timer;
    const dots = [];
    for (let i = 0; i < longEvery; i++) {
      const filled = i < streak ? "filled" : "";
      dots.push(`<span class="set-dot ${filled}" style="width:${18 * s}px;height:${3 * s}px;"></span>`);
    }
    return `<div class="set-progress" title="每 ${longEvery} 个番茄后长休息" style="gap:${5 * s}px;">${dots.join("")}</div>`;
  }

  function renderInterruptionBar(s) {
    const t = state.timer;
    const chip = (kind, mark, label, count, help) => `
      <div class="interruption-chip no-drag" style="height:${30 * s}px;">
        <button class="interruption-main pressable" data-act="interrupt" data-kind="${kind}" title="${help}" style="gap:${6 * s}px;padding-left:${13 * s}px;padding-right:${(count > 0 ? 6 : 13) * s}px;font-size:${12.5 * s}px;">
          <span class="interruption-mark" style="font-size:${13 * s}px;">${mark}</span>
          <span>${label}</span>
        </button>
        ${
          count > 0
            ? `<button class="interruption-badge display-num pressable" data-act="undo-interrupt" data-kind="${kind}" data-count="${count}" title="误按了？点这个数字减 1" style="font-size:${14 * s}px;min-width:${20 * s}px;padding:${2.5 * s}px ${6 * s}px;margin-right:${5 * s}px;">${count}</button>`
            : ""
        }
      </div>`;
    return `
      <div class="interruption-bar" style="gap:${8 * s}px;">
        ${chip("internal", "-", "内部打断", t.sessionInternal, "自己想去做别的事：把念头记下来，继续专注（快捷键 -）")}
        ${chip("external", "=", "外部打断", t.sessionExternal, "别人或消息打断：告知、协商、稍后再回（快捷键 =）")}
      </div>`;
  }

  function renderTodaySummary(s) {
    const st = state.timer.stats;
    const focusLabel = st.focusSeconds > 0 ? `专注 ${formatDuration(st.focusSeconds)}` : "还没开始";
    const focusColor = st.focusSeconds > 0 ? "var(--positive)" : "var(--gray)";
    return `
      <div>
        <div class="section-label" style="font-size:${12.5 * s}px;margin-bottom:${4 * s}px;">今日成果</div>
        <div class="today-count-row" style="gap:${6 * s}px;">
          <span class="display-num" style="font-size:${40 * s}px;">${st.completed}</span>
          <span style="font-size:${14 * s}px;font-weight:600;">个番茄</span>
        </div>
        <div class="today-meta-row" style="gap:${10 * s}px;font-size:${12 * s}px;margin-top:${4 * s}px;">
          <span style="display:inline-flex;align-items:center;gap:${3 * s}px;color:${focusColor};">
            ${svgIcon("arrowUpRight", 11 * s)}
            <span>${focusLabel}</span>
          </span>
          ${st.interruptions > 0 || st.internalBreaks + st.externalBreaks > 0 ? `<span style="color:var(--gray);">打断 ${st.internalBreaks + st.externalBreaks}</span>` : ""}
          ${st.voided > 0 ? `<span style="color:var(--gray);">作废 ${st.voided}</span>` : ""}
        </div>
      </div>`;
  }

  function renderTaskMetaLine(task, s, showEstimate) {
    const bits = [];
    if (task.priority !== null && task.priority !== undefined) {
      bits.push(
        `<span class="priority-tag p${task.priority}" style="font-size:${11 * s}px;padding:${1 * s}px ${5 * s}px;">P${task.priority}</span>`
      );
    }
    if (task.ddlInfo && !task.finished) {
      const c =
        task.ddlInfo.level === 0
          ? "var(--accent-focus)"
          : task.ddlInfo.level <= 2
            ? "var(--warning)"
            : "var(--gray)";
      bits.push(`<span style="color:${c};">${esc(task.ddlInfo.text)}</span>`);
    }
    if (task.tag) {
      bits.push(`<span style="color:var(--gray);">${esc(task.tag)}</span>`);
    }
    if (showEstimate) {
      bits.push(`<span style="color:var(--gray);">预估 ${task.estimate} · 完成 ${task.done}</span>`);
    }
    if (bits.length === 0) return "";
    return `<div class="task-meta-line" style="gap:${6 * s}px;font-size:${11.5 * s}px;">${bits.join("")}</div>`;
  }

  function renderSessionBlock(s) {
    const t = state.timer;
    if (t.phase !== "focus") {
      return `
        <div class="session-block" style="gap:${10 * s}px;">
          <div class="section-label" style="font-size:${12.5 * s}px;">${t.phase === "longBreak" ? "长休息" : "休息一下"}</div>
          <div class="serif-text" style="font-size:${21 * s}px;line-height:1.35;">${esc(t.breakTip)}</div>
          <div style="font-size:${11.5 * s}px;font-weight:500;color:var(--gray);line-height:1.4;">休息时彻底离开工作，不看消息，回来会更专注。</div>
        </div>`;
    }

    const cur = t.tasks.find((x) => x.id === t.currentTaskID);
    const clamped = expandCurrentTitle ? "" : "clamped";
    let meterHTML = "";
    let metaHTML = "";
    if (cur) {
      const n = Math.min(Math.max(cur.done, cur.estimate), 12);
      const dots = [];
      for (let i = 0; i < n; i++) {
        if (i < cur.done) {
          const fill = i < cur.estimate ? "var(--accent-focus)" : "var(--warning)";
          dots.push(`<span class="tomato-dot" style="width:${8 * s}px;height:${8 * s}px;background:${fill};"></span>`);
        } else {
          dots.push(
            `<span class="tomato-dot" style="width:${8 * s}px;height:${8 * s}px;border:${Math.max(1, 8 * s * 0.14)}px solid var(--ink-40);"></span>`
          );
        }
      }
      meterHTML = `
        <div style="display:flex;align-items:center;gap:${8 * s}px;">
          <span class="tomato-meter" style="gap:${8 * s * 0.45}px;">${dots.join("")}</span>
          <span style="font-size:${11.5 * s}px;font-weight:500;color:var(--gray);">${cur.done} / ${cur.estimate} 个番茄</span>
        </div>`;
      if (cur.priority !== undefined || cur.due) {
        metaHTML = renderTaskMetaLine(cur, s, false);
      }
    }

    const titleHelp = cur ? (expandCurrentTitle ? "点击收起" : "点击展开完整任务名") : "";
    return `
      <div class="session-block" style="gap:${10 * s}px;">
        <div class="section-label" style="font-size:${12.5 * s}px;">当前任务</div>
        <div class="session-title ${cur ? clamped : "empty"}" data-act="toggle-current-title" title="${titleHelp}" style="font-size:${19 * s}px;">${esc(cur ? cur.title : "还没有选择任务")}</div>
        ${meterHTML}
        ${metaHTML}
        <div style="margin-top:${2 * s}px;">${renderInterruptionBar(s)}</div>
      </div>`;
  }

  function renderNotionSyncButton(s) {
    const n = state.notion;
    if (!n.configured) return "";
    const hasErr = Boolean(n.lastError);
    const help = hasErr
      ? `同步失败：${n.lastError}`
      : n.lastSyncHM
        ? `上次同步 ${n.lastSyncHM}，${n.lastCount} 条 · 点击立即同步`
        : "立即同步 Notion";
    const icon = hasErr ? "warn" : "sync";
    const spin = n.syncing ? "spin" : "";
    return `
      <button class="notion-sync-btn pressable no-drag ${hasErr ? "error" : ""}" data-act="notion-sync" title="${esc(help)}" style="font-size:${11 * s}px;">
        <span class="${spin}" style="display:inline-flex;">${svgIcon(icon, 11 * s)}</span>
        <span>${n.lastSyncHM ? `Notion ${n.lastSyncHM}` : "Notion"}</span>
      </button>`;
  }

  function renderTaskRows(s) {
    const t = state.timer;
    const focusMin = t.settings.focusMinutes;
    if (t.tasks.length === 0) {
      return `
        <div class="serif-text" title="末尾可写 ×2（预估番茄数）、P0–P3（优先级）、@11-25 或 @明天（DDL）" style="font-size:${14 * s}px;color:var(--gray);text-align:center;line-height:1.6;padding:${24 * s}px 0;">
          先列出今天要做的事，<br/>再预估每件要几个番茄。
        </div>`;
    }

    return t.tasks
      .map((task, idx) => {
        const isCurrent = task.id === t.currentTaskID;
        const expanded = expandedFinishedIDs.has(task.id);
        const showFullTitle = (isCurrent && !task.finished) || (task.finished && expanded);
        const statusText = task.finished
          ? ["已完成", "var(--positive)"]
          : task.done > task.estimate
            ? [`超出 ${task.done - task.estimate}`, "var(--warning)"]
            : isCurrent
              ? ["进行中", "var(--accent-focus)"]
              : ["待开始", "var(--gray)"];

        const checkInner = task.finished
          ? svgIcon("check", 13 * s)
          : `<span class="display-num" style="font-size:${16 * s}px;">${idx + 1}</span>`;

        const showMetaEst =
          (task.priority === undefined || task.priority === null) && !task.due && !task.tag;

        const actionBar =
          isCurrent && !task.finished
            ? `
            <div class="task-action-bar" style="padding-left:${46 * s}px;margin-top:${6 * s}px;">
              <div style="display:inline-flex;align-items:center;gap:${5 * s}px;" title="预估这件事要几个番茄（当前每个 ${focusMin} 分钟）">
                <span style="font-size:${11 * s}px;color:var(--gray);font-weight:500;">预估</span>
                <button class="small-circle-btn pressable" data-act="task-est" data-id="${task.id}" data-delta="-1" ${task.estimate <= 1 ? "disabled" : ""} title="预估少 1 个番茄" style="width:${22 * s}px;height:${22 * s}px;">${svgIcon("minus", 10 * s)}</button>
                <span class="display-num" style="font-size:${15 * s}px;min-width:${12 * s}px;text-align:center;">${task.estimate}</span>
                <button class="small-circle-btn pressable" data-act="task-est" data-id="${task.id}" data-delta="1" ${task.estimate >= 12 ? "disabled" : ""} title="预估多 1 个番茄" style="width:${22 * s}px;height:${22 * s}px;">${svgIcon("plus", 10 * s)}</button>
              </div>
              ${
                task.notionURL
                  ? `<button class="chip-btn pressable" data-act="open-url" data-url="${esc(task.notionURL)}" title="在浏览器里打开这条任务的 Notion 页面" style="height:${22 * s}px;padding:0 ${9 * s}px;font-size:${11 * s}px;">Notion ↗</button>`
                  : `<button class="chip-btn pressable" data-act="task-rm" data-id="${task.id}" title="删除这个任务" style="height:${22 * s}px;padding:0 ${9 * s}px;font-size:${11 * s}px;">删除</button>`
              }
            </div>`
            : "";

        const rowHelp = task.finished
          ? expanded
            ? "点击收起完整名称"
            : "点击查看完整名称"
          : isCurrent
            ? "当前任务"
            : "点击设为当前任务，可查看完整名称与调整预估";

        return `
          <div class="task-row no-drag ${isCurrent && !task.finished ? "current" : ""}" data-act="task-row" data-id="${task.id}" title="${rowHelp}" style="padding:${7 * s}px ${8 * s}px;margin-bottom:${2 * s}px;">
            <div class="task-row-main" style="gap:${12 * s}px;">
              <button class="task-check-btn pressable ${task.finished ? "finished" : ""}" data-act="task-toggle" data-id="${task.id}" title="${task.finished ? "标记为未完成" : "标记为已完成"}" style="width:${34 * s}px;height:${34 * s}px;">
                ${checkInner}
              </button>
              <div class="task-body">
                <div class="task-title-line">
                  ${task.top3 ? `<span style="color:var(--accent-focus);display:inline-flex;transform:translateY(1px);" title="Notion 置顶">${svgIcon("star", 10 * s)}</span>` : ""}
                  <span class="task-title-text ${showFullTitle ? "" : "clamped"} ${task.finished ? "finished" : ""}" style="font-size:${14 * s}px;">${esc(task.title)}</span>
                </div>
                ${renderTaskMetaLine(task, s, showMetaEst)}
              </div>
              <div class="task-right" style="gap:${2 * s}px;">
                <span class="display-num" style="font-size:${17 * s}px;color:${task.finished ? "var(--gray)" : "var(--ink)"};">${task.done}/${task.estimate}</span>
                <span style="font-size:${11 * s}px;font-weight:500;color:${statusText[1]};">${statusText[0]}</span>
              </div>
            </div>
            ${actionBar}
          </div>`;
      })
      .join("");
  }

  function renderTaskListShell(s) {
    const hasFinished = state.timer.tasks.some((t) => t.finished);
    return `
      <div class="task-list-wrap" style="gap:${8 * s}px;">
        <div class="task-list-header">
          <div class="section-label" style="font-size:${12.5 * s}px;">今日待办</div>
          <div class="task-header-actions">
            <span data-slot="notion-sync-btn">${renderNotionSyncButton(s)}</span>
            <button class="no-drag" data-act="clear-finished" style="font-size:${11.5 * s}px;font-weight:500;color:var(--gray);display:${hasFinished ? "inline-flex" : "none"};">清除已完成</button>
          </div>
        </div>
        <div class="task-scroll" data-slot="task-scroll">
          ${renderTaskRows(s)}
        </div>
        <div class="task-add-row no-drag" style="gap:${10 * s}px;padding:${6 * s}px;">
          <span class="task-add-icon" style="width:${30 * s}px;height:${30 * s}px;">${svgIcon("plus", 11 * s)}</span>
          <input class="task-add-input" data-slot="task-add-input" type="text" placeholder="添加任务，如「写周报 ×2 P1 @11-25」" value="${esc(taskDraft)}" style="font-size:${13 * s}px;" />
        </div>
      </div>`;
  }

  // MARK: Layout builders

  function getGeometry(w, h) {
    const kind = getLayoutKind(w, h);
    if (kind === "landscape") {
      const s = Math.min(Math.max(h / 720, 0.85), 1.45);
      const sideW = Math.min(Math.max(w * 0.32, 270), 440);
      const mainW = w - sideW;
      const pad = 22 * s;
      const D = Math.max(140, Math.min(mainW * 0.66, (h - 60 * s - pad * 2) / 1.3));
      return { kind, s, sideW, pad, D };
    }
    if (kind === "portrait") {
      const avail = h - 34;
      const D = Math.max(120, Math.min(w * 0.74, avail * 0.47));
      const s = Math.min(Math.max(D / 270, 0.8), 1.6);
      return { kind, s, D };
    }
    const k = Math.min(Math.max(Math.min(h / 104, w / 320), 0.8), 1.8);
    return { kind, k };
  }

  function renderFullLayout() {
    if (!state) return;
    const w = window.innerWidth;
    const h = window.innerHeight;
    const g = getGeometry(w, h);
    lastLayoutKind = g.kind;

    if (g.kind === "landscape") {
      const { s, sideW, pad, D } = g;
      appEl.innerHTML = `
        <div class="landscape-shell">
          <aside class="sidebar" style="width:${sideW}px;padding:${Math.max(18, pad * 0.8)}px ${pad}px ${pad * 0.8}px;gap:${16 * s}px;">
            <div class="drag-region" style="height:6px;flex-shrink:0;"></div>
            <div data-slot="today-summary">${renderTodaySummary(s)}</div>
            <div class="hairline"></div>
            <div data-slot="session-block">${renderSessionBlock(s)}</div>
            <div class="hairline"></div>
            ${renderTaskListShell(s)}
          </aside>
          <main class="main-pane" style="padding:${pad * 0.7}px ${pad}px ${pad}px;">
            <div class="main-header drag-region">
              <div data-slot="phase-picker">${renderPhasePicker(12.5 * s)}</div>
              <div style="flex:1;height:28px;" class="drag-region"></div>
              <div data-slot="toolbar">${renderToolbar(s)}</div>
            </div>
            <div data-slot="ring-view">${renderRingView(D)}</div>
            <div class="main-bottom" style="gap:${16 * s}px;">
              <div data-slot="controls-view">${renderControls(D)}</div>
              <div data-slot="set-progress">${renderSetProgress(s)}</div>
            </div>
          </main>
        </div>`;
      return;
    }

    if (g.kind === "portrait") {
      const { s, D } = g;
      const t = state.timer;
      const cur = t.tasks.find((x) => x.id === t.currentTaskID);
      const st = t.stats;
      const statParts = [`今日 ${st.completed} 个番茄`];
      if (st.focusSeconds > 0) statParts.push(`专注 ${formatDuration(st.focusSeconds)}`);
      const intTotal = st.internalBreaks + st.externalBreaks;
      if (intTotal > 0) statParts.push(`打断 ${intTotal}`);
      if (st.voided > 0) statParts.push(`作废 ${st.voided}`);

      appEl.innerHTML = `
        <div class="portrait-shell" style="padding:10px 12px 14px;">
          <div class="portrait-top drag-region">
            <div style="flex:1;height:28px;" class="drag-region"></div>
            <div data-slot="toolbar">${renderToolbar(Math.min(s, 1.15))}</div>
          </div>
          <div data-slot="phase-picker">${renderPhasePicker(12.5 * s)}</div>
          <button class="current-task-pill pressable no-drag" data-act="open-tasks" title="今日待办" style="gap:${12.5 * s * 0.55}px;font-size:${12.5 * s}px;padding:${12.5 * s * 0.5}px ${12.5 * s}px;">
            ${svgIcon("list", 12.5 * s * 0.85)}
            <span class="current-task-pill-title" style="color:${cur ? "var(--ink)" : "var(--gray)"};">${esc(cur ? cur.title : "添加今天的任务")}</span>
            ${cur ? `<span class="display-num" style="font-size:${12.5 * s * 1.15}px;">${cur.done}/${cur.estimate}</span>` : ""}
            <span style="color:var(--gray);display:inline-flex;">${svgIcon("chevronDown", 12.5 * s * 0.75)}</span>
          </button>
          <div data-slot="ring-view">${renderRingView(D)}</div>
          <div data-slot="controls-view">${renderControls(D)}</div>
          <div class="portrait-footer" style="gap:${10 * s}px;width:100%;">
            <div data-slot="set-progress">${renderSetProgress(s)}</div>
            <div class="stats-line" data-slot="stats-line" style="font-size:${11.5 * s}px;">${esc(statParts.join(" · "))}</div>
            <div data-slot="portrait-int">${t.phase === "focus" ? renderInterruptionBar(s * 0.92) : ""}</div>
          </div>
        </div>`;
      return;
    }

    // Mini layout
    const { k } = g;
    const t = state.timer;
    const cur = t.tasks.find((x) => x.id === t.currentTaskID);
    const label = t.phase === "focus" && cur ? `专注 · ${cur.title}` : t.phaseTitle;
    const status = t.running ? `${t.projectedEndHM} 结束` : t.hasStarted ? "已暂停" : "未开始";
    const gapPx = t.progress > 0.004 && t.progress < 0.996 ? 3 * k : 0;
    const pct = Math.max(0, Math.min(100, t.progress * 100));

    appEl.innerHTML = `
      <div class="mini-shell drag-region" style="padding:${12 * k}px ${18 * k}px ${14 * k}px;">
        <div class="mini-top" style="gap:${10 * k}px;">
          <div class="mini-info">
            <div class="mini-label" style="font-size:${11.5 * k}px;">${esc(label)}</div>
            <div class="mini-time-row" style="gap:${8 * k}px;margin-top:${1 * k}px;">
              <span class="display-num" style="font-size:${38 * k}px;">${t.timeText}</span>
              <span style="font-size:${11 * k}px;font-weight:500;color:${t.running ? "var(--accent)" : "var(--gray)"};white-space:nowrap;">${esc(status)}</span>
            </div>
          </div>
          <div class="mini-actions no-drag" style="gap:${8 * k}px;">
            <button class="mini-play-btn pressable" data-act="toggle" title="开始 / 暂停（空格）" style="width:${38 * k}px;height:${38 * k}px;">
              ${svgIcon(t.running ? "pause" : "play", 13 * k)}
            </button>
            <button class="tool-icon pressable" data-act="win-expand" title="展开" style="width:${28 * k * 0.95}px;height:${28 * k * 0.95}px;">
              ${svgIcon("expand", 12 * k)}
            </button>
          </div>
        </div>
        <div class="mini-progress-track" style="height:${2.5 * k}px;gap:${gapPx}px;">
          ${pct > 0.3 ? `<div class="mini-progress-done" style="width:${pct.toFixed(2)}%;"></div>` : ""}
          <div class="mini-progress-rest"></div>
        </div>
      </div>`;
  }

  function renderDynamicSlots() {
    if (!state) return;
    const w = window.innerWidth;
    const h = window.innerHeight;
    const g = getGeometry(w, h);
    if (g.kind !== lastLayoutKind || g.kind === "mini" || g.kind === "portrait") {
      // Check if an input inside main app is currently focused (landscape task add input)
      const activeInput = document.activeElement?.getAttribute("data-slot") === "task-add-input";
      if (!activeInput && g.kind !== lastLayoutKind) {
        renderFullLayout();
        return;
      }
      if (g.kind === "mini") {
        renderFullLayout();
        return;
      }
    }

    if (g.kind === "landscape") {
      const { s, D } = g;
      const setSlot = (name, html) => {
        const el = appEl.querySelector(`[data-slot="${name}"]`);
        if (el) el.innerHTML = html;
      };
      setSlot("today-summary", renderTodaySummary(s));
      setSlot("session-block", renderSessionBlock(s));
      setSlot("phase-picker", renderPhasePicker(12.5 * s));
      setSlot("toolbar", renderToolbar(s));
      setSlot("ring-view", renderRingView(D));
      setSlot("controls-view", renderControls(D));
      setSlot("set-progress", renderSetProgress(s));
      setSlot("notion-sync-btn", renderNotionSyncButton(s));
      const clr = appEl.querySelector('[data-act="clear-finished"]');
      if (clr) clr.style.display = state.timer.tasks.some((t) => t.finished) ? "inline-flex" : "none";
      const scrollEl = appEl.querySelector('[data-slot="task-scroll"]');
      if (scrollEl) {
        const prevTop = scrollEl.scrollTop;
        scrollEl.innerHTML = renderTaskRows(s);
        scrollEl.scrollTop = prevTop;
      }
    } else if (g.kind === "portrait") {
      const activeTag = document.activeElement?.tagName;
      if (activeTag !== "INPUT") {
        renderFullLayout();
      }
    }

    // Also update portrait task popover list if open
    if (activePopover === "tasks") {
      const popScroll = popoverLayer.querySelector('[data-slot="task-scroll"]');
      if (popScroll) {
        const prevTop = popScroll.scrollTop;
        popScroll.innerHTML = renderTaskRows(1);
        popScroll.scrollTop = prevTop;
      }
      const popSync = popoverLayer.querySelector('[data-slot="notion-sync-btn"]');
      if (popSync) popSync.innerHTML = renderNotionSyncButton(1);
      const popClr = popoverLayer.querySelector('[data-act="clear-finished"]');
      if (popClr) popClr.style.display = state.timer.tasks.some((t) => t.finished) ? "inline-flex" : "none";
    } else if (activePopover === "settings" && settingsTab === 1) {
      const statusSlot = popoverLayer.querySelector('[data-slot="notion-status-area"]');
      if (statusSlot) statusSlot.innerHTML = renderNotionStatusHTML();
    }
  }

  // MARK: Popover rendering

  function renderNotionStatusHTML() {
    const n = state.notion;
    const dbLabel = n.databaseTitle || "Notion 数据库";
    let title, color, detail;
    if (!n.configured) {
      title = "未连接";
      color = "var(--faint)";
      detail = "填写 integration 令牌和数据库链接或 ID";
    } else if (n.syncing) {
      title = "同步中…";
      color = "var(--warning)";
      detail = `正在拉取 ${dbLabel}`;
    } else if (n.lastError) {
      title = "同步失败";
      color = "var(--accent-focus)";
      detail = n.lastError;
    } else if (n.lastSyncHM) {
      title = `已连接 · ${dbLabel}`;
      color = "var(--positive)";
      detail = `上次同步 ${n.lastSyncHM} · ${n.lastCount} 条任务`;
    } else {
      title = `已连接 · ${dbLabel}`;
      color = "var(--positive)";
      detail = "等待首次同步";
    }
    return `
      <div class="status-dot-wrap">
        <div class="status-dot-row">
          <span class="status-dot" style="background:${color};"></span>
          <span>${esc(title)}</span>
        </div>
        <div class="status-dot-detail">${esc(detail)}</div>
      </div>`;
  }

  function renderPopover() {
    if (!activePopover || !state) {
      popoverLayer.classList.add("hidden");
      popoverLayer.innerHTML = "";
      return;
    }
    popoverLayer.classList.remove("hidden");

    if (activePopover === "tasks") {
      popoverLayer.innerHTML = `
        <div class="popover-card tasks-card" data-card="1">
          ${renderTaskListShell(1)}
        </div>`;
      return;
    }

    const t = state.timer;
    const st = t.settings;
    const n = state.notion;
    const api = state.api;

    const stepper = (key, val, unit, min, max) => `
      <div class="ink-stepper">
        <button class="ink-stepper-btn pressable" data-act="step" data-key="${key}" data-delta="-1" ${val <= min ? "disabled" : ""}>${svgIcon("minus", 10)}</button>
        <div class="ink-stepper-val">
          <span class="display-num ink-stepper-num">${val}</span>
          <span class="ink-stepper-unit">${unit}</span>
        </div>
        <button class="ink-stepper-btn pressable" data-act="step" data-key="${key}" data-delta="1" ${val >= max ? "disabled" : ""}>${svgIcon("plus", 10)}</button>
      </div>`;

    const sw = (key, isOn, act = "toggle-setting") => `
      <button class="ink-switch ${isOn ? "on" : ""}" data-act="${act}" data-key="${key}" aria-pressed="${isOn}">
        <span class="ink-switch-knob"></span>
      </button>`;

    const isClassic =
      st.focusMinutes === 25 &&
      st.shortBreakMinutes === 5 &&
      st.longBreakMinutes === 15 &&
      st.longBreakEvery === 4;

    let tabBody = "";
    if (settingsTab === 0) {
      tabBody = `
        <div class="setting-group">
          <div class="setting-group-label">外观</div>
          <div class="capsule-tabs" style="gap:4px;margin-left:-10px;">
            ${[
              ["light", "纸色"],
              ["dark", "深咖"],
              ["system", "跟随系统"],
            ]
              .map(
                ([v, label]) =>
                  `<button class="capsule-tab ${st.appearance === v ? "active" : ""}" data-act="set-appearance" data-val="${v}" style="font-size:12.5px;padding:5px 12px;">${label}</button>`
              )
              .join("")}
          </div>
        </div>
        <div class="setting-group">
          <div class="setting-group-label">时长</div>
          <div class="setting-row"><span class="setting-row-title">专注</span>${stepper("focusMinutes", st.focusMinutes, "分钟", 1, 120)}</div>
          <div class="setting-row"><span class="setting-row-title">短休息</span>${stepper("shortBreakMinutes", st.shortBreakMinutes, "分钟", 1, 60)}</div>
          <div class="setting-row"><span class="setting-row-title">长休息</span>${stepper("longBreakMinutes", st.longBreakMinutes, "分钟", 1, 60)}</div>
          <div class="setting-row no-divider">
            <div>
              <div class="setting-row-title">长休息间隔</div>
              <div class="setting-row-detail">完成几个番茄后长休息一次</div>
            </div>
            ${stepper("longBreakEvery", st.longBreakEvery, "个", 2, 10)}
          </div>
          ${
            !isClassic
              ? `<button data-act="restore-classic" style="display:inline-flex;align-items:center;gap:4px;font-size:12px;font-weight:500;color:var(--accent-focus);margin-top:6px;">
                  ${svgIcon("undo", 12)}
                  <span>恢复经典 25 / 5 / 15 · 每 4 个</span>
                </button>`
              : ""
          }
        </div>
        <div class="setting-group">
          <div class="setting-group-label">行为</div>
          <div class="setting-row">
            <div><div class="setting-row-title">自动开始下一段</div><div class="setting-row-detail">专注结束直接进入休息，休息结束直接开始专注</div></div>
            ${sw("autoStartNext", st.autoStartNext)}
          </div>
          <div class="setting-row">
            <div><div class="setting-row-title">结束提示音</div><div class="setting-row-detail">每段结束时响三声</div></div>
            ${sw("playSound", st.playSound)}
          </div>
          <div class="setting-row">
            <div><div class="setting-row-title">系统托盘显示</div><div class="setting-row-detail">在托盘显示运行状态并提供快捷控制菜单</div></div>
            ${sw("showInTray", st.showInTray)}
          </div>
          <div class="setting-row no-divider">
            <div><div class="setting-row-title">移到副屏自动全屏</div><div class="setting-row-detail">窗口移到外接显示器或无线副屏时自动进入全屏</div></div>
            ${sw("autoFullScreenOnSecondary", st.autoFullScreenOnSecondary)}
          </div>
        </div>
        <div class="setting-group">
          <div class="setting-group-label">数据</div>
          <div class="setting-row no-divider">
            <div><div class="setting-row-title">今日成果</div><div class="setting-row-detail">清零今日番茄数、专注时长、打断与作废</div></div>
            ${
              confirmResetToday
                ? `<div style="display:inline-flex;gap:6px;">
                    <button class="ink-btn outline pressable" data-act="cancel-reset-today">取消</button>
                    <button class="ink-btn filled pressable" data-act="confirm-reset-today">确认清零</button>
                  </div>`
                : `<button class="ink-btn outline pressable" data-act="ask-reset-today">清零</button>`
            }
          </div>
        </div>`;
    } else if (settingsTab === 1) {
      const dirty = notionTokenDraft.trim() !== "" || notionTargetDraft.trim() !== n.targetInput;
      const saveDisabled = (!notionTokenDraft.trim() && !n.hasToken) || !notionTargetDraft.trim() || n.syncing;
      const btnLabel = dirty ? "保存并同步" : "立即同步";
      tabBody = `
        <div class="setting-group">
          <div class="setting-group-label">Notion</div>
          <div data-slot="notion-status-area">${renderNotionStatusHTML()}</div>
          <div style="font-size:11px;color:var(--gray);line-height:1.45;margin-bottom:4px;">
            范围：今天计划、${n.lookaheadDays} 天内到期、已逾期、置顶的未完成任务；启动时和每 30 分钟同步。
          </div>
          <div class="ink-field">
            <div class="ink-field-label">Integration 令牌${n.hasToken ? "（已保存，留空表示保持不变）" : ""}</div>
            <input class="ink-field-input" data-slot="notion-token" type="password" placeholder="ntn_… 或 secret_…" value="${esc(notionTokenDraft)}" />
          </div>
          <div class="ink-field">
            <div class="ink-field-label">数据库链接或 ID</div>
            <input class="ink-field-input mono" data-slot="notion-target" type="text" placeholder="粘贴 Notion 数据库链接或 ID" value="${esc(notionTargetDraft)}" />
          </div>
          <div class="setting-row">
            <div><div class="setting-row-title">DDL 提前天数</div><div class="setting-row-detail">拉取未来几天内到期的任务</div></div>
            ${stepper("lookaheadDays", n.lookaheadDays, "天", 1, 30)}
          </div>
          <div class="setting-row no-divider">
            <div><div class="setting-row-title">完成时回写 Notion</div><div class="setting-row-detail">在番茄钟里勾选完成时同步更新 Notion 状态</div></div>
            ${sw("writeBack", n.writeBack, "toggle-notion-writeback")}
          </div>
          <div style="margin-top:8px;">
            <button class="ink-btn filled pressable" data-act="notion-save-sync" ${saveDisabled ? "disabled" : ""}>
              ${svgIcon("sync", 12)}
              <span>${btnLabel}</span>
            </button>
          </div>
        </div>
        <div class="hairline" style="margin-top:16px;"></div>
        <div class="setting-group">
          <div class="setting-group-label">AI 接口</div>
          <div class="status-dot-wrap">
            <div class="status-dot-row">
              <span class="status-dot" style="background:${api.running ? "var(--positive)" : "var(--accent-focus)"};"></span>
              <span>${api.running ? "已开启" : "未启动"}</span>
            </div>
            <div class="status-dot-detail">${api.running ? `只在本机 127.0.0.1:${api.port} 监听，需令牌访问` : esc(api.lastError || "")}</div>
          </div>
          <div style="display:flex;gap:6px;flex-wrap:wrap;padding:4px 0;">
            <span class="key-chip mono">pomo status</span>
            <span class="key-chip mono">pomo tasks</span>
            <span class="key-chip mono">pomo add</span>
          </div>
          <div style="font-size:11px;color:var(--gray);padding:4px 0;">AI 用命令行 pomo 即可调用，说明见 docs/API.md</div>
          <div style="margin-top:6px;">
            <button class="ink-btn outline pressable" data-act="copy-api-token">
              ${svgIcon(copiedToken ? "check" : "copy", 12)}
              <span>${copiedToken ? "已复制" : "复制接口令牌"}</span>
            </button>
          </div>
        </div>`;
    } else {
      const steps = [
        ["列出今日待办", "预估每件要几个番茄"],
        ["选一件，专注 25 分钟", "中途不切换任务"],
        ["被打断就记一笔", "按 - 记内部打断 · 按 = 记外部打断，尽量推迟处理"],
        ["休息 5 分钟", "彻底离开工作，不看消息"],
        ["每 4 个番茄长休息", "15–30 分钟，回顾这一组"],
      ];
      const modPrefix = state.platform === "darwin" ? "⌘" : "Ctrl+";
      const altPrefix = state.platform === "darwin" ? "⌥⌘" : "Ctrl+Alt+";
      const keys = [
        ["空格", "开始 / 暂停"],
        [`${modPrefix}R`, "重置"],
        [`${modPrefix}Shift+S`, "跳过"],
        ["-", "内部打断"],
        ["=", "外部打断"],
        [`${altPrefix}I`, "发送到副屏"],
        [`${altPrefix}M`, "移回主屏"],
        [`${altPrefix}P`, "迷你窗"],
      ];
      tabBody = `
        <div class="setting-group">
          <div class="setting-group-label">番茄工作法</div>
          ${steps
            .map(
              ([a, b], i) => `
              <div class="method-step">
                <span class="display-num method-step-num">${i + 1}</span>
                <div>
                  <div style="font-size:13px;font-weight:500;">${a}</div>
                  <div style="font-size:11px;color:var(--gray);margin-top:1px;">${b}</div>
                </div>
              </div>`
            )
            .join("")}
        </div>
        <div class="setting-group">
          <div class="setting-group-label">快速添加</div>
          <div style="font-family:var(--font-mono);font-size:12.5px;background:var(--panel-solid);border-radius:10px;padding:8px 12px;margin:4px 0;">写周报 ×2 P1 @11-25</div>
          <div style="display:flex;gap:12px;flex-wrap:wrap;margin-top:6px;">
            <span style="display:inline-flex;align-items:center;gap:5px;font-size:11.5px;color:var(--gray);"><span class="key-chip mono" style="color:var(--ink);">×2</span>预估番茄</span>
            <span style="display:inline-flex;align-items:center;gap:5px;font-size:11.5px;color:var(--gray);"><span class="key-chip mono" style="color:var(--ink);">P0–P3</span>优先级</span>
            <span style="display:inline-flex;align-items:center;gap:5px;font-size:11.5px;color:var(--gray);"><span class="key-chip mono" style="color:var(--ink);">@明天</span>DDL</span>
          </div>
        </div>
        <div class="setting-group">
          <div class="setting-group-label">快捷键</div>
          <div class="shortcut-grid">
            ${keys
              .map(([k, d]) => `<div class="shortcut-item"><span class="key-chip" style="color:var(--ink);">${k}</span><span>${d}</span></div>`)
              .join("")}
          </div>
        </div>`;
    }

    popoverLayer.innerHTML = `
      <div class="popover-card" data-card="1">
        <div class="settings-head">
          <div class="settings-title">设置</div>
          <button class="tool-icon pressable" data-act="close-popover" style="width:26px;height:26px;" title="关闭">${svgIcon("close", 12)}</button>
        </div>
        <div class="capsule-tabs" style="gap:4px;margin-left:-10px;">
          ${[
            [0, "计时"],
            [1, "同步与接口"],
            [2, "方法"],
          ]
            .map(
              ([id, label]) =>
                `<button class="capsule-tab ${settingsTab === id ? "active" : ""}" data-act="settings-tab" data-tab="${id}" style="font-size:12.5px;padding:5px 12px;">${label}</button>`
            )
            .join("")}
        </div>
        ${tabBody}
      </div>`;
  }

  function applyThemeAndPhase() {
    if (!state) return;
    document.body.setAttribute("data-theme", isDarkTheme() ? "dark" : "light");
    document.body.setAttribute("data-phase", state.timer.phase);
    drawPaperGrain();
  }

  // MARK: Event delegation

  document.addEventListener("click", async (e) => {
    // Hover / click inside popover backdrop closes popover
    if (e.target === popoverLayer) {
      activePopover = null;
      confirmResetToday = false;
      copiedToken = false;
      renderPopover();
      renderDynamicSlots();
      return;
    }

    const undoBadge = e.target.closest('[data-act="undo-interrupt"]');
    if (undoBadge) {
      e.stopPropagation();
      await window.pomo.undoInterruption(undoBadge.dataset.kind === "internal");
      return;
    }

    const el = e.target.closest("[data-act]");
    if (!el) return;
    const act = el.dataset.act;

    if (act === "toggle") return window.pomo.toggle();
    if (act === "reset") return window.pomo.reset();
    if (act === "skip") return window.pomo.skip();
    if (act === "phase") return window.pomo.selectPhase(el.dataset.phase);
    if (act === "interrupt") return window.pomo.logInterruption(el.dataset.kind === "internal");

    if (act === "task-toggle") {
      e.stopPropagation();
      return window.pomo.toggleFinished(el.dataset.id);
    }
    if (act === "task-est") {
      e.stopPropagation();
      return window.pomo.adjustEstimate(el.dataset.id, Number(el.dataset.delta));
    }
    if (act === "task-rm") {
      e.stopPropagation();
      return window.pomo.removeTask(el.dataset.id);
    }
    if (act === "open-url") {
      e.stopPropagation();
      return window.pomo.openExternal(el.dataset.url);
    }
    if (act === "task-row") {
      const id = el.dataset.id;
      const task = state?.timer?.tasks?.find((t) => t.id === id);
      if (!task) return;
      if (task.finished) {
        if (expandedFinishedIDs.has(id)) expandedFinishedIDs.delete(id);
        else expandedFinishedIDs.add(id);
        renderDynamicSlots();
      } else {
        await window.pomo.selectTask(id);
      }
      return;
    }
    if (act === "toggle-current-title") {
      if (state?.timer?.currentTaskID) {
        expandCurrentTitle = !expandCurrentTitle;
        renderDynamicSlots();
      }
      return;
    }
    if (act === "clear-finished") return window.pomo.clearFinished();
    if (act === "notion-sync") return window.pomo.syncNotion();

    if (act === "win-secondary") return window.pomo.sendToSecondary();
    if (act === "win-primary") return window.pomo.sendToPrimary();
    if (act === "win-mini") return window.pomo.setMini(true);
    if (act === "win-expand") return window.pomo.setMini(false);
    if (act === "win-fullscreen") return window.pomo.toggleFullScreen();
    if (act === "win-minimize") return window.pomo.minimizeWindow();
    if (act === "win-close") return window.pomo.closeWindow();
    if (act === "toggle-ontop") {
      return window.pomo.updateSettings({ alwaysOnTop: !state.timer.settings.alwaysOnTop });
    }

    if (act === "open-tasks") {
      activePopover = "tasks";
      renderPopover();
      return;
    }
    if (act === "open-settings") {
      activePopover = activePopover === "settings" ? null : "settings";
      confirmResetToday = false;
      copiedToken = false;
      notionTokenDraft = "";
      notionTargetDraft = state?.notion?.targetInput || "";
      renderPopover();
      renderDynamicSlots();
      return;
    }
    if (act === "close-popover") {
      activePopover = null;
      confirmResetToday = false;
      copiedToken = false;
      renderPopover();
      renderDynamicSlots();
      return;
    }
    if (act === "settings-tab") {
      settingsTab = Number(el.dataset.tab);
      confirmResetToday = false;
      if (settingsTab === 1) {
        notionTargetDraft = state?.notion?.targetInput || notionTargetDraft;
      }
      renderPopover();
      return;
    }
    if (act === "set-appearance") {
      await window.pomo.updateSettings({ appearance: el.dataset.val });
      renderPopover();
      return;
    }
    if (act === "step") {
      const key = el.dataset.key;
      const delta = Number(el.dataset.delta);
      if (key === "lookaheadDays") {
        await window.pomo.updateNotionConfig({ lookaheadDays: state.notion.lookaheadDays + delta });
      } else {
        await window.pomo.updateSettings({ [key]: state.timer.settings[key] + delta });
      }
      renderPopover();
      return;
    }
    if (act === "restore-classic") {
      await window.pomo.updateSettings({
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        longBreakEvery: 4,
      });
      renderPopover();
      return;
    }
    if (act === "toggle-setting") {
      const key = el.dataset.key;
      await window.pomo.updateSettings({ [key]: !state.timer.settings[key] });
      renderPopover();
      return;
    }
    if (act === "toggle-notion-writeback") {
      await window.pomo.updateNotionConfig({ writeBack: !state.notion.writeBack });
      renderPopover();
      return;
    }
    if (act === "ask-reset-today") {
      confirmResetToday = true;
      renderPopover();
      return;
    }
    if (act === "cancel-reset-today") {
      confirmResetToday = false;
      renderPopover();
      return;
    }
    if (act === "confirm-reset-today") {
      confirmResetToday = false;
      await window.pomo.resetToday();
      renderPopover();
      return;
    }
    if (act === "notion-save-sync") {
      const tokenToSave = notionTokenDraft.trim();
      const targetToSave = notionTargetDraft.trim();
      const payload = {
        token: tokenToSave || undefined,
        target: targetToSave,
      };
      // If token input left blank and already configured, keep existing token in main
      if (!tokenToSave && state.notion.hasToken) {
        delete payload.token;
        // update target + sync without wiping token
        await window.pomo.saveAndSyncNotion({ tokenKeep: true, target: targetToSave });
      } else {
        await window.pomo.saveAndSyncNotion(payload);
      }
      notionTokenDraft = "";
      notionTargetDraft = state?.notion?.targetInput || targetToSave;
      renderPopover();
      return;
    }
    if (act === "copy-api-token") {
      await window.pomo.copyApiToken();
      copiedToken = true;
      renderPopover();
    }
  });

  // Interruption badge hover text (-1)
  document.addEventListener("mouseover", (e) => {
    const badge = e.target.closest('[data-act="undo-interrupt"]');
    if (badge) badge.textContent = "−1";
  });
  document.addEventListener("mouseout", (e) => {
    const badge = e.target.closest('[data-act="undo-interrupt"]');
    if (badge) badge.textContent = badge.dataset.count;
  });

  // Inputs tracking & quick add submit
  document.addEventListener("input", (e) => {
    const slot = e.target.getAttribute("data-slot");
    if (slot === "task-add-input") {
      taskDraft = e.target.value;
    } else if (slot === "notion-token") {
      notionTokenDraft = e.target.value;
      updateNotionSaveBtnState();
    } else if (slot === "notion-target") {
      notionTargetDraft = e.target.value;
      updateNotionSaveBtnState();
    }
  });

  function updateNotionSaveBtnState() {
    const btn = popoverLayer.querySelector('[data-act="notion-save-sync"]');
    if (!btn || !state) return;
    const n = state.notion;
    const dirty = notionTokenDraft.trim() !== "" || notionTargetDraft.trim() !== n.targetInput;
    const disabled = (!notionTokenDraft.trim() && !n.hasToken) || !notionTargetDraft.trim() || n.syncing;
    btn.disabled = disabled;
    const span = btn.querySelector("span:last-child");
    if (span) span.textContent = dirty ? "保存并同步" : "立即同步";
  }

  document.addEventListener(
    "keydown",
    async (e) => {
      if (e.isComposing) return;
      const active = document.activeElement;
      const isTextInput = active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA");

      if (isTextInput) {
        if (e.key === "Enter" && active.getAttribute("data-slot") === "task-add-input") {
          e.preventDefault();
          const text = active.value.trim();
          if (text) {
            taskDraft = "";
            active.value = "";
            await window.pomo.addQuickTask(text);
          }
          return;
        }
        if (e.key === "Escape") {
          active.blur();
          if (activePopover) {
            activePopover = null;
            renderPopover();
          }
        }
        return;
      }

      if (e.key === "Escape" && activePopover) {
        activePopover = null;
        renderPopover();
        renderDynamicSlots();
        return;
      }

      const mod = state?.platform === "darwin" ? e.metaKey : e.ctrlKey;
      const hasAnyMod = e.ctrlKey || e.altKey || e.metaKey || e.shiftKey;

      if (!hasAnyMod && !e.repeat) {
        if (e.code === "Space") {
          e.preventDefault();
          e.stopPropagation();
          await window.pomo.toggle();
          return;
        }
        if (e.code === "Minus") {
          e.preventDefault();
          e.stopPropagation();
          await window.pomo.logInterruption(true);
          return;
        }
        if (e.code === "Equal") {
          e.preventDefault();
          e.stopPropagation();
          await window.pomo.logInterruption(false);
          return;
        }
      }

      if (mod && !e.altKey && !e.shiftKey && e.code === "KeyR") {
        e.preventDefault();
        await window.pomo.reset();
      } else if (mod && e.shiftKey && !e.altKey && e.code === "KeyS") {
        e.preventDefault();
        await window.pomo.skip();
      } else if (e.ctrlKey && e.altKey && e.code === "KeyI") {
        e.preventDefault();
        await window.pomo.sendToSecondary();
      } else if (e.ctrlKey && e.altKey && e.code === "KeyM") {
        e.preventDefault();
        await window.pomo.sendToPrimary();
      } else if (e.ctrlKey && e.altKey && e.code === "KeyP") {
        e.preventDefault();
        await window.pomo.setMini(!state.windowState.isMini);
      } else if (e.key === "F11") {
        e.preventDefault();
        await window.pomo.toggleFullScreen();
      }
    },
    true
  );

  window.addEventListener("resize", () => {
    drawPaperGrain();
    renderFullLayout();
  });

  // MARK: Bootstrap & IPC subscription

  function onNewState(next) {
    state = next;
    if (state.timer.currentTaskID !== lastCurrentTaskID) {
      lastCurrentTaskID = state.timer.currentTaskID;
      expandCurrentTitle = false;
    }
    applyThemeAndPhase();
    if (!lastLayoutKind) renderFullLayout();
    else renderDynamicSlots();
  }

  window.pomo.onState(onNewState);
  window.pomo.onPhaseComplete((info) => {
    flashScreen();
    if (info?.sound) playChime();
  });

  window.pomo.getInitialState().then((init) => {
    onNewState(init);
  });
})();
