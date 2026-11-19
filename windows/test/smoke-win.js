const assert = require("node:assert/strict");
const fs = require("fs");
const net = require("net");
const os = require("os");
const path = require("path");
const { spawn, execFileSync } = require("child_process");

function getFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close((err) => (err ? reject(err) : resolve(port)));
    });
  });
}

function getPythonCmd() {
  for (const cmd of process.platform === "win32" ? ["python", "python3"] : ["python3", "python"]) {
    try {
      const out = execFileSync(cmd, ["--version"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
      if (out.includes("Python 3")) return cmd;
    } catch {
      // ignore
    }
  }
  return null;
}

function killTree(child) {
  if (!child || child.killed) return;
  try {
    if (process.platform === "win32") {
      execFileSync("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore" });
    } else {
      child.kill("SIGTERM");
    }
  } catch {
    // ignore if already exited
  }
}

async function waitForHealth(port, timeoutMs = 25000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/v1/health`);
      if (r.status === 200) return await r.json();
    } catch {
      // retry
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error(`Timed out waiting for /v1/health on 127.0.0.1:${port}`);
}

async function main() {
  const customExe = process.argv[2] ? path.resolve(process.argv[2]) : null;
  const appRoot = path.resolve(__dirname, "..");
  const exe = customExe || require("electron");
  const args = customExe ? [] : [appRoot];

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pomo-smoke-"));
  const port = await getFreePort();
  const env = {
    ...process.env,
    POMODORO_DATA_DIR: tmpDir,
    POMODORO_PORT: String(port),
    POMODORO_ALLOW_MULTI: "1",
  };

  let logs = "";
  const child = spawn(exe, args, { env, stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.on("data", (d) => (logs += d.toString()));
  child.stderr.on("data", (d) => (logs += d.toString()));

  try {
    const health = await waitForHealth(port);
    assert.deepEqual(health, { ok: true, app: "Pomodoro" });

    // Unauthenticated status must be rejected
    const unauth = await fetch(`http://127.0.0.1:${port}/v1/status`);
    assert.equal(unauth.status, 401);

    // Authenticated status check
    const apiCfg = JSON.parse(fs.readFileSync(path.join(tmpDir, "api.json"), "utf8"));
    const statusResp = await fetch(`http://127.0.0.1:${port}/v1/status`, {
      headers: { Authorization: `Bearer ${apiCfg.token}` },
    });
    assert.equal(statusResp.status, 200);
    const statusJson = await statusResp.json();
    assert.equal(statusJson.phase, "focus");
    assert.equal(statusJson.remaining, "25:00");

    // Verify tools/pomo against live app
    const py = getPythonCmd();
    if (py) {
      const pomoScript = path.resolve(appRoot, "..", "tools", "pomo");
      const out = execFileSync(py, [pomoScript, "status"], { env, encoding: "utf8" });
      assert.match(out, /剩余 25:00/);
    }

    console.log(`✅ Smoke test passed on 127.0.0.1:${port} (${customExe ? path.basename(customExe) : "electron"})`);
  } catch (err) {
    console.error("Smoke test failed! Child logs:\n" + logs);
    throw err;
  } finally {
    killTree(child);
    await new Promise((r) => setTimeout(r, 300));
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
