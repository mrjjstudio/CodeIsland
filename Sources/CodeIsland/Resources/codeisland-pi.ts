// codeisland-pi extension — forwards pi agent events to CodeIsland
// version: v2
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { connect } from "net";
import { getuid } from "process";

const SOCKET = `/tmp/codeisland-${getuid()}.sock`;

function sendToSocket(json: Record<string, unknown>) {
  return new Promise<boolean>((resolve) => {
    try {
      const sock = connect({ path: SOCKET }, () => {
        sock.write(JSON.stringify(json));
        sock.end();
        resolve(true);
      });
      sock.on("error", () => resolve(false));
      sock.setTimeout(3000, () => { sock.destroy(); resolve(false); });
    } catch { resolve(false); }
  });
}

// For blocking requests, delegate to the bridge binary.
// Node.js net module's half-close (sock.end()) causes NWConnection
// to close immediately on macOS, losing the response.
const BRIDGE_PATH = require("path").join(require("os").homedir(), ".codeisland", "codeisland-bridge");

function sendAndWaitResponse(json: Record<string, unknown>, timeoutMs = 300000) {
  return new Promise<Record<string, unknown> | null>((resolve) => {
    try {
      const child = require("child_process").execFile(BRIDGE_PATH, [], {
        timeout: timeoutMs, maxBuffer: 1024 * 1024,
      }, (error: Error | null, stdout: string) => {
        if (error) { resolve(null); return; }
        try { resolve(JSON.parse(stdout)); } catch { resolve(null); }
      });
      child.stdin.write(JSON.stringify(json));
      child.stdin.end();
    } catch { resolve(null); }
  });
}

// Terminal environment collection
const ENV_KEYS = [
  "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
  "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID", "__CFBundleIdentifier",
];

let detectedTty: string | null = null;
try {
  const { execSync } = require("child_process");
  let walkPid = process.pid;
  for (let i = 0; i < 8; i++) {
    const info = execSync(`ps -o tty=,ppid= -p ${walkPid}`, { timeout: 1000 }).toString().trim();
    const parts = info.split(/\s+/);
    const tty = parts[0], ppid = parseInt(parts[1]);
    if (tty && tty !== "??" && tty !== "?") { detectedTty = `/dev/${tty}`; break; }
    if (!ppid || ppid <= 1) break;
    walkPid = ppid;
  }
} catch {}

function collectEnv() {
  const env: Record<string, string> = {};
  for (const k of ENV_KEYS) { if (process.env[k]) env[k] = process.env[k]; }
  return env;
}

const pid = process.pid;

// Stable session ID — set once on session_start, reused for all events
let currentSessionId = `s-${pid}`;
let lastAssistantText = "";
let lastUserText = "";

function base(extra: Record<string, unknown>) {
  return {
    session_id: `pi-${currentSessionId}`,
    _source: "pi",
    _ppid: pid,
    _env: collectEnv(),
    _tty: detectedTty,
    ...extra,
  };
}

// Capitalize tool name for consistency with other integrations
function capitalizeTool(name: string): string {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

export default function(pi: ExtensionAPI) {
  // ── Session lifecycle ──
  pi.on("session_start", async (event, ctx) => {
    lastAssistantText = "";
    lastUserText = "";
    // Generate a stable ID based on PID + timestamp of session start
    currentSessionId = `s-${pid}-${Date.now()}`;
    await sendToSocket(base({
      hook_event_name: "SessionStart",
      cwd: ctx.cwd,
    }));
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    await sendToSocket(base({
      hook_event_name: "SessionEnd",
      cwd: ctx.cwd,
    }));
  });

  // ── Agent lifecycle ──
  pi.on("before_agent_start", async (_event, ctx) => {
    await sendToSocket(base({
      hook_event_name: "UserPromptSubmit",
      cwd: ctx.cwd,
    }));
  });

  pi.on("agent_end", async (_event, ctx) => {
    await sendToSocket(base({
      hook_event_name: "Stop",
      cwd: ctx.cwd,
      last_assistant_message: lastAssistantText || undefined,
    }));
  });

  // ── Tool execution ──
  pi.on("tool_call", async (event, ctx) => {
    const toolName = capitalizeTool(event.toolName);
    await sendToSocket(base({
      hook_event_name: "PreToolUse",
      cwd: ctx.cwd,
      tool_name: toolName,
      tool_input: event.input || {},
    }));
  });

  pi.on("tool_result", async (event, ctx) => {
    const toolName = capitalizeTool(event.toolName);
    await sendToSocket(base({
      hook_event_name: event.isError ? "PostToolUseFailure" : "PostToolUse",
      cwd: ctx.cwd,
      tool_name: toolName,
    }));
  });

  // ── Streaming messages — capture last assistant text ──
  pi.on("message_update", (event, _ctx) => {
    try {
      const evt = event as { assistantMessageEvent?: { type: string; text?: string } };
      if (evt.assistantMessageEvent?.type === "text_delta" && evt.assistantMessageEvent.text) {
        lastAssistantText += evt.assistantMessageEvent.text;
        // Keep bounded
        if (lastAssistantText.length > 2000) {
          lastAssistantText = lastAssistantText.slice(-1000);
        }
      }
    } catch {}
  });
}
