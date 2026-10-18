// DeepSeek turns go through Claude Code's print mode, pointed at DeepSeek's
// Anthropic-compatible API. Grok's ACP process does not know these model ids, so
// a session that selected one must not be handed to `grok agent`.
//
// Claude's stream-json output is normalized into the same text / thought / end
// events the phone already renders. Tool approval cards stay on the Grok path:
// this mode lets Claude's own permission mode decide, because print mode has no
// channel back to the phone for a tap.

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const ONE_MILLION = 1_000_000;

export function deepseekPermissionMode(policy) {
  if (policy === "all") return "bypassPermissions";
  if (policy === "reads") return "acceptEdits";
  return "auto";
}

export function deepseekContextWindow(model) {
  return String(model || "").includes("[1m]") ? ONE_MILLION : 0;
}

/** Map one Claude `--output-format stream-json` object onto bridge events.
 *  Partial deltas are the live text. The later `assistant` snapshot repeats
 *  them, so it is ignored. */
export function normalizeClaudeEvent(obj) {
  if (!obj || typeof obj !== "object") return [];
  if (obj.type === "stream_event") {
    const event = obj.event || {};
    const delta = event.delta || {};
    if (event.type === "content_block_delta" && delta.type === "thinking_delta" && delta.thinking) {
      return [{ kind: "thought", text: String(delta.thinking) }];
    }
    if (event.type === "content_block_delta" && delta.type === "text_delta" && delta.text) {
      return [{ kind: "text", text: String(delta.text) }];
    }
    const block = event.content_block;
    if (event.type === "content_block_start" && block?.type === "tool_use" && block.name) {
      return [{ kind: "log", text: `tool: ${block.name}` }];
    }
    return [];
  }
  if (obj.type !== "result") return [];
  const ok = obj.subtype === "success" && obj.is_error !== true;
  return [{
    kind: "end",
    stopReason: ok ? "EndTurn" : (obj.subtype || "Error"),
    sessionId: obj.session_id || "",
    requestId: null,
    ok,
    errorText: ok ? "" : String(obj.result || obj.error || "DeepSeek turn failed"),
    usage: usageFromClaude(obj.usage),
  }];
}

export function usageFromClaude(usage) {
  if (!usage || typeof usage !== "object") return null;
  const inputTokens = number(usage.input_tokens);
  const outputTokens = number(usage.output_tokens);
  const cachedReadTokens = number(usage.cache_read_input_tokens);
  return {
    inputTokens,
    outputTokens,
    cachedReadTokens,
    reasoningTokens: 0,
    totalTokens: inputTokens + outputTokens,
    costUsdTicks: 0,
    apiDurationMs: 0,
  };
}

function number(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function writeClaudeSettings({ apiKey, baseUrl, model }) {
  const dir = join(homedir(), ".grok-remote");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const path = join(dir, "deepseek-claude.json");
  writeFileSync(path, JSON.stringify({
    env: {
      ANTHROPIC_BASE_URL: baseUrl || "https://api.deepseek.com/anthropic",
      ANTHROPIC_AUTH_TOKEN: apiKey,
      ANTHROPIC_MODEL: model,
      CLAUDE_CODE_EFFORT_LEVEL: "max",
    },
  }), { mode: 0o600 });
  return path;
}

function redactSecrets(text) {
  return String(text || "").replace(/sk-[A-Za-z0-9_-]+/g, "sk-***");
}

/**
 * Run one DeepSeek turn. Resolves with the Claude session id so the next turn
 * can `--resume` it.
 */
export function runDeepSeekTurn(opts) {
  const {
    claudeBin,
    prompt,
    cwd,
    model,
    resumeSessionId,
    apiKey,
    baseUrl,
    permissionMode,
    signal,
    onEvent,
  } = opts;

  // `--bare` ignores the computer's Claude settings, so a key saved there cannot
  // override the one the bridge was given. Auth then comes only from this file.
  const settingsPath = writeClaudeSettings({ apiKey, baseUrl, model });
  const args = [
    "--bare",
    "--settings", settingsPath,
    "--print", prompt,
    "--verbose",
    "--output-format", "stream-json",
    "--include-partial-messages",
    "--model", model,
    "--permission-mode", permissionMode || "auto",
  ];
  if (resumeSessionId) args.push("--resume", resumeSessionId);

  const env = { ...process.env };
  env.ANTHROPIC_BASE_URL = baseUrl || "https://api.deepseek.com/anthropic";
  env.ANTHROPIC_AUTH_TOKEN = apiKey;
  // An empty or stale API key in the environment takes precedence over the token
  // and makes DeepSeek answer 401. The token above is the only credential.
  delete env.ANTHROPIC_API_KEY;
  env.ANTHROPIC_MODEL = model;
  if (!env.CLAUDE_CODE_EFFORT_LEVEL) env.CLAUDE_CODE_EFFORT_LEVEL = "max";

  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawn(claudeBin || "claude", args, {
        cwd: cwd || undefined,
        signal,
        stdio: ["ignore", "pipe", "pipe"],
        env,
      });
    } catch (err) {
      reject(err);
      return;
    }

    let ended = null;
    let stderrTail = "";
    const rl = createInterface({ input: child.stdout });
    rl.on("line", (line) => {
      const trimmed = line.trim();
      if (!trimmed) return;
      let obj;
      try {
        obj = JSON.parse(trimmed);
      } catch {
        onEvent({ kind: "log", text: redactSecrets(trimmed) });
        return;
      }
      for (const event of normalizeClaudeEvent(obj)) {
        if (event.kind === "end") {
          ended = event;
          if (event.ok) {
            onEvent({
              kind: "end",
              stopReason: event.stopReason,
              sessionId: event.sessionId,
              requestId: null,
            });
          }
          continue;
        }
        onEvent(event);
      }
    });

    child.stderr.on("data", (buf) => {
      const text = redactSecrets(buf.toString()).trim();
      if (!text) return;
      stderrTail = (stderrTail + "\n" + text).slice(-4000);
      // Claude warns when it does not recognize a gateway model id. The request
      // still succeeds; the phone does not need that diagnostic in the transcript.
      if (text.includes("unrecognized_model")) return;
      onEvent({ kind: "log", text });
    });

    child.on("error", (err) => {
      reject(new Error(`failed to launch claude (${claudeBin}): ${err.message}`));
    });

    child.on("close", (code, sig) => {
      if (ended?.ok) {
        resolve({
          sessionId: ended.sessionId,
          stopReason: ended.stopReason,
          usage: ended.usage,
        });
        return;
      }
      if (signal?.aborted || sig === "SIGTERM") {
        resolve({ sessionId: ended?.sessionId || resumeSessionId || "", stopReason: "Cancelled", usage: null });
        return;
      }
      const why = ended?.errorText || stderrTail.trim();
      reject(new Error(redactSecrets(
        `DeepSeek turn failed${code != null ? ` (code ${code})` : ""}${why ? `: ${why}` : ""}`
      )));
    });
  });
}
