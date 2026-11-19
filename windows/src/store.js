const fs = require("fs");
const os = require("os");
const path = require("path");

function getDataDir(overrideDir = null) {
  let dir = overrideDir || process.env.POMODORO_DATA_DIR;
  if (dir) {
    if (dir.startsWith("~/") || dir === "~") {
      dir = path.join(os.homedir(), dir.slice(1));
    }
    dir = path.resolve(dir);
  } else if (process.platform === "win32") {
    const base = process.env.APPDATA || os.homedir();
    dir = path.join(base, "Pomodoro");
  } else if (process.platform === "darwin") {
    dir = path.join(os.homedir(), "Library", "Application Support", "Pomodoro");
  } else {
    const base = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
    dir = path.join(base, "Pomodoro");
  }
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function readJSON(filePath, fallback) {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function writeJSON(filePath, value, mode = null) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${filePath}.tmp.${process.pid}.${Math.random().toString(16).slice(2)}`;
  const content = JSON.stringify(value, null, 2);
  fs.writeFileSync(tmp, content, { encoding: "utf8", mode: mode ?? 0o644 });
  fs.renameSync(tmp, filePath);
  if (mode !== null && process.platform !== "win32") {
    try {
      fs.chmodSync(filePath, mode);
    } catch {
      // ignore chmod failures on restricted filesystems
    }
  }
}

module.exports = {
  getDataDir,
  readJSON,
  writeJSON,
};
