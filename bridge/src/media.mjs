// Pictures Grok generates land in that grok session's images/ folder, and the
// reply refers to them as `images/1.jpg` (or a markdown link to it). The phone
// cannot read that disk. This module is the only door: it names which files a
// session may hand to a client, and it refuses anything that is not one image
// inside that session.

import { realpathSync, statSync, readdirSync } from "node:fs";
import { join, resolve as resolvePath } from "node:path";

const MEDIA_RE = "(?:images|videos)\\/[A-Za-z0-9][A-Za-z0-9._-]{0,120}\\.(?:jpe?g|png|gif|webp)";
const TOKEN = new RegExp(MEDIA_RE, "gi");
const CANONICAL = new RegExp(`^(${MEDIA_RE})$`, "i");
// Grok's ACP session ids are UUIDv7-shaped. Reject anything that could be a path.
const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f-]{16,40}$/i;

/** `images/1.jpg` in canonical form, or null when `name` is not one image file. */
export function canonicalMediaName(raw) {
  const m = CANONICAL.exec(String(raw ?? "").trim());
  if (!m) return null;
  const slash = m[1].indexOf("/");
  const folder = m[1].slice(0, slash).toLowerCase();
  const file = m[1].slice(slash + 1);
  if (file.includes("..") || folder !== "images" && folder !== "videos") return null;
  return `${folder}/${file}`;
}

export function mediaContentType(name) {
  const ext = String(name).split(".").pop().toLowerCase();
  switch (ext) {
    case "jpg":
    case "jpeg": return "image/jpeg";
    case "png": return "image/png";
    case "gif": return "image/gif";
    case "webp": return "image/webp";
    default: return "application/octet-stream";
  }
}

/**
 * Split prose into text runs and generated-image references.
 *
 * Fenced code is the caller's job: a path inside a code block is code, not a
 * picture. Wrappers Grok actually emits are consumed with the reference, so the
 * phone does not also show a dead link beside the image.
 */
export function splitMediaRefs(text) {
  const src = String(text ?? "");
  const out = [];
  let cursor = 0;
  for (const match of src.matchAll(TOKEN)) {
    let start = match.index;
    let end = start + match[0].length;
    if (start < cursor) continue;
    if (start > 0 && /[A-Za-z0-9._-]/.test(src[start - 1])) continue;
    const name = canonicalMediaName(match[0]);
    if (!name) continue;
    [start, end] = expandWrap(src, start, end, name);
    if (start < cursor) continue;
    const before = src.slice(cursor, start);
    if (before.trim()) out.push({ type: "text", text: before });
    out.push({ type: "image", name });
    cursor = end;
  }
  if (cursor === 0) return [{ type: "text", text: src }];
  const rest = src.slice(cursor);
  if (rest.trim()) out.push({ type: "text", text: rest });
  return out;
}

function expandWrap(src, start, end, name) {
  if (start > 0 && src[start - 1] === "`" && src[end] === "`") return [start - 1, end + 1];
  // [label](…images/1.jpg…) — the label itself may be the same path.
  if (src.startsWith("](", end)) {
    const close = src.indexOf(")", end + 2);
    if (close !== -1 && src.slice(end + 2, close).toLowerCase().includes(name.toLowerCase())) {
      let from = start;
      if (src[start - 1] === "[") from = start - 1;
      if (src[from - 1] === "!") from -= 1;
      return [from, close + 1];
    }
  }
  if (src.startsWith(")", end) && src.slice(Math.max(0, start - 2), start) === "](") {
    let i = start - 3;
    while (i >= 0 && src[i] !== "[" && src[i] !== "\n") i -= 1;
    if (i >= 0 && src[i] === "[") {
      if (src[i - 1] === "!") i -= 1;
      return [i, end + 1];
    }
  }
  if (src[start - 1] === "/") {
    let i = start;
    while (i > 0 && !/[\s`'"(<\[]/.test(src[i - 1])) i -= 1;
    return [i, end];
  }
  return [start, end];
}

/**
 * Absolute path of one generated image for this grok session, or null.
 * `cwd` is only a hint: the file is also accepted from whichever session group
 * actually holds `grokSessionId`, because Grok's directory name is the encoded
 * working directory and a long path uses a different spelling.
 */
export function locateSessionMedia(home, cwd, grokSessionId, name) {
  const rel = canonicalMediaName(name);
  const id = String(grokSessionId ?? "");
  if (!rel || !SESSION_ID.test(id)) return null;
  const root = join(home, ".grok", "sessions");
  const groups = [];
  const add = (value) => {
    if (!value) return;
    const enc = encodeURIComponent(value);
    if (Buffer.byteLength(enc) <= 255 && !groups.includes(enc)) groups.push(enc);
  };
  add(cwd);
  try { add(resolvePath(String(cwd))); } catch { /* a missing cwd still scans */ }
  for (const group of groups) {
    const hit = openMedia(join(root, group, id), rel);
    if (hit) return hit;
  }
  let entries;
  try { entries = readdirSync(root, { withFileTypes: true }); } catch { return null; }
  for (const entry of entries) {
    if (!entry.isDirectory() || groups.includes(entry.name)) continue;
    const hit = openMedia(join(root, entry.name, id), rel);
    if (hit) return hit;
  }
  return null;
}

function openMedia(sessionDir, rel) {
  const full = join(sessionDir, rel);
  let realDir, realFile;
  try {
    if (!statSync(full).isFile()) return null;
    realDir = realpathSync(sessionDir);
    realFile = realpathSync(full);
  } catch {
    return null;
  }
  // A symlink (the file, or images/ itself) that steps outside the session
  // resolves somewhere else. The joined path does not, so it stops matching.
  if (realFile !== join(realDir, rel)) return null;
  return realFile;
}
