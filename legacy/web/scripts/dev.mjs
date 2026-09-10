// Dev launcher: start the backend (:8787) and the Vite client (:5173) together.
//
// Replaces `concurrently`, which on this setup deadlocked the backend's startup:
// it piped the server's stdout through itself, and while Vite flooded its own
// startup logs the server's pipe buffer filled during the (heavy) Agent-SDK
// import — blocking the backend in a write() *before* it reached app.listen, so
// it never bound :8787 and the client only ever saw ECONNREFUSED.
//
// `stdio: 'inherit'` hands each child the real terminal directly, so there is no
// intermediary pipe to stall. Output is interleaved (no per-line prefixes); the
// reliability is worth more than the colored labels here.
import { spawn } from "node:child_process";

const isWin = process.platform === "win32";
const children = [];
let shuttingDown = false;

function shutdown(code = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  for (const c of children) {
    if (!c.pid || c.killed) continue;
    // Kill the whole child tree (npm -> tsx/vite -> worker), else they orphan
    // and keep holding the ports.
    if (isWin) spawn("taskkill", ["/pid", String(c.pid), "/T", "/F"], { stdio: "ignore" });
    else c.kill("SIGTERM");
  }
  process.exit(code);
}

function run(script) {
  const child = spawn("npm", ["run", script], { stdio: "inherit", shell: true });
  child.on("exit", (code) => shutdown(code ?? 0));
  children.push(child);
}

process.on("SIGINT", () => shutdown(0));
process.on("SIGTERM", () => shutdown(0));

run("dev:server");
run("dev:client");
