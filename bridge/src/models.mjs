import { spawn } from "node:child_process";

/** Parse the stable, human-readable output of `grok models` without baking model
 * ids into the bridge. Grok may print an authentication warning on stderr while
 * still returning the locally-known roster, so callers deliberately parse both. */
export function parseGrokModels(text) {
  const source = String(text || "");
  const defaultModel = source.match(/^Default model:\s*(\S+)/mi)?.[1] || "";
  const models = [];
  const seen = new Set();
  for (const line of source.split(/\r?\n/)) {
    const id = line.match(/^\s*[*-]\s+(\S+?)(?:\s+\(default\))?\s*$/)?.[1];
    if (id && !seen.has(id)) { seen.add(id); models.push(id); }
  }
  if (defaultModel && !seen.has(defaultModel)) models.unshift(defaultModel);
  return { models, defaultModel };
}

/** Models served by DeepSeek's Anthropic-compatible API, not by `grok models`. */
export const DEEPSEEK_MODELS = ["deepseek-v4-pro[1m]", "deepseek-v4-pro", "deepseek-flash[1m]", "deepseek-flash"];

export function isDeepSeekModel(id) {
  return /^deepseek-[A-Za-z0-9._[\]-]+$/.test(String(id || "").trim());
}

/** Append the DeepSeek roster without dropping or reordering what Grok reported. */
export function mergeModelRoster(info, { includeDeepSeek = true } = {}) {
  const models = Array.isArray(info?.models) ? [...info.models] : [];
  const seen = new Set(models);
  if (includeDeepSeek) {
    for (const id of DEEPSEEK_MODELS) {
      if (!seen.has(id)) {
        seen.add(id);
        models.push(id);
      }
    }
  }
  return { models, defaultModel: info?.defaultModel || "" };
}

export function listGrokModels(grokBin, timeout = 20_000) {
  return new Promise((resolve) => {
    let out = "", err = "", settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      resolve(parseGrokModels(`${out}\n${err}`));
    };
    let child;
    try {
      child = spawn(grokBin, ["models"], { stdio: ["ignore", "pipe", "pipe"], timeout });
    } catch {
      return finish();
    }
    child.stdout.on("data", (b) => (out += b));
    child.stderr.on("data", (b) => (err += b));
    child.on("error", finish);
    child.on("close", finish);
  });
}
