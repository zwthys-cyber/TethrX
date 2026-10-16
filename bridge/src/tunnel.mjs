// Reach the bridge from anywhere with only an internet connection: no VPN on the
// phone, no port forwarding, no public IP.
//
// The bridge starts Cloudflare's `cloudflared` and keeps it running. cloudflared
// dials OUT to Cloudflare and receives a public https://….trycloudflare.com address
// that proxies to this bridge on loopback. Every request through it still needs
// the pairing token, exactly as on the LAN.
//
// Quick-tunnel addresses change whenever cloudflared restarts, so the bridge also
// publishes its current address to a "rendezvous" ntfy topic. The topic name and
// an HMAC over the message are both derived from the pairing token: the phone can
// find the new address, and nobody without the token can point it somewhere else.

import { spawn, spawnSync } from "node:child_process";
import { createHash, createHmac } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, renameSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";

const QUICK_URL_RE = /https:\/\/(?!api\.)[a-z0-9-]+\.trycloudflare\.com/;
const RELEASES = "https://github.com/cloudflare/cloudflared/releases/latest/download/";
const RENDEZVOUS_REPUBLISH_MS = 4 * 3600_000;   // ntfy.sh keeps messages for 12 hours
const PUBLIC_CHECK_MS = 5 * 60_000;

/** "quick" (no account), "named" (your own Cloudflare tunnel token), or "off". */
export function tunnelMode({ tunnel, tunnelToken }) {
  if (tunnelToken) return "named";
  const v = String(tunnel || "").trim().toLowerCase();
  return ["1", "on", "true", "yes", "quick", "cloudflare"].includes(v) ? "quick" : "off";
}

// --- rendezvous ----------------------------------------------------------------

/** ntfy topic for this bridge. Hashing keeps the token itself off the wire. */
export function rendezvousTopic(token) {
  return "tethrx-" + createHash("sha256").update("tethrx-rendezvous-topic\n" + token).digest("hex").slice(0, 40);
}

export function rendezvousSignature(token, { url, serverId, ts }) {
  return createHmac("sha256", token)
    .update(`tethrx-rendezvous-v1\n${url}\n${serverId}\n${ts}`)
    .digest("hex");
}

export function rendezvousMessage(token, { url, serverId, ts = Date.now() }) {
  return JSON.stringify({ v: 1, url, serverId, ts, sig: rendezvousSignature(token, { url, serverId, ts }) });
}

/** The newest correctly signed address in an ntfy `/json?poll=1` response body. */
export function latestRendezvous(token, body, serverId) {
  let best = null;
  for (const line of String(body).split("\n")) {
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg?.event !== "message" || typeof msg.message !== "string") continue;
    let rec;
    try { rec = JSON.parse(msg.message); } catch { continue; }
    if (rec?.v !== 1 || typeof rec.url !== "string" || !/^https:\/\//i.test(rec.url) || !Number.isInteger(rec.ts)) continue;
    if (serverId && rec.serverId !== serverId) continue;
    if (rec.sig !== rendezvousSignature(token, rec)) continue;
    if (!best || rec.ts > best.ts) best = rec;
  }
  return best;
}

async function publishRendezvous(base, token, serverId, url) {
  const topic = rendezvousTopic(token);
  const r = await fetch(`${base.replace(/\/+$/, "")}/${topic}`, {
    method: "POST",
    headers: { Title: "TethrX bridge address", Tags: "link", Priority: "min" },
    body: rendezvousMessage(token, { url, serverId }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!r.ok) throw new Error(`rendezvous publish failed (${r.status})`);
}

// --- cloudflared binary ------------------------------------------------------

function works(bin) {
  const r = spawnSync(bin, ["--version"], { encoding: "utf8", timeout: 15_000 });
  return !r.error && r.status === 0;
}

function assetName() {
  const arch = { x64: "amd64", arm64: "arm64", arm: "arm", ia32: "386" }[process.arch];
  if (!arch) return null;
  if (process.platform === "linux") return `cloudflared-linux-${arch}`;
  if (process.platform === "darwin" && (arch === "amd64" || arch === "arm64")) return `cloudflared-darwin-${arch}.tgz`;
  return null;
}

/** An explicit path, one on PATH, or a copy downloaded once into ~/.grok-remote/bin. */
async function resolveCloudflared(stateDir, explicit) {
  if (explicit) {
    if (works(explicit)) return explicit;
    throw new Error(`GROK_REMOTE_CLOUDFLARED=${explicit} does not run`);
  }
  const local = join(stateDir, "bin", "cloudflared");
  if (existsSync(local) && works(local)) return local;
  if (works("cloudflared")) return "cloudflared";

  const asset = assetName();
  if (!asset) {
    throw new Error(`no cloudflared download for ${process.platform}/${process.arch}; install cloudflared and set GROK_REMOTE_CLOUDFLARED`);
  }
  console.log(`[tunnel] downloading cloudflared (${asset}) from Cloudflare's GitHub releases…`);
  const dir = join(stateDir, "bin");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const r = await fetch(RELEASES + asset, { signal: AbortSignal.timeout(180_000) });
  if (!r.ok) throw new Error(`cloudflared download failed (${r.status})`);
  const bytes = Buffer.from(await r.arrayBuffer());
  const tmp = join(dir, `.download-${process.pid}`);
  if (asset.endsWith(".tgz")) {
    writeFileSync(tmp + ".tgz", bytes, { mode: 0o600 });
    mkdirSync(tmp, { recursive: true });
    const x = spawnSync("tar", ["-xzf", tmp + ".tgz", "-C", tmp], { encoding: "utf8" });
    rmSync(tmp + ".tgz", { force: true });
    if (x.status !== 0) throw new Error(`could not unpack cloudflared: ${x.stderr || x.error}`);
    renameSync(join(tmp, "cloudflared"), local);
    rmSync(tmp, { recursive: true, force: true });
  } else {
    writeFileSync(tmp, bytes, { mode: 0o700 });
    renameSync(tmp, local);
  }
  chmodSync(local, 0o755);
  if (!works(local)) throw new Error("the downloaded cloudflared does not run on this machine");
  return local;
}

// --- the tunnel itself ---------------------------------------------------------

/** Where cloudflared should send traffic: loopback unless the bridge is bound elsewhere. */
export function tunnelOrigin(host, port) {
  const h = String(host || "");
  if (!h || ["0.0.0.0", "::", "127.0.0.1", "localhost", "::1"].includes(h)) return `http://127.0.0.1:${port}`;
  return h.includes(":") ? `http://[${h}]:${port}` : `http://${h}:${port}`;
}

const STATE_FILE = "tunnel.json";

/** The address the running bridge last reported, for `tethrx-bridge pair`. */
export function readTunnelState(stateDir) {
  try { return JSON.parse(readFileSync(join(stateDir, STATE_FILE), "utf8")); } catch { return null; }
}

function writeTunnelState(stateDir, state) {
  const path = join(stateDir, STATE_FILE);
  try {
    if (!state) { rmSync(path, { force: true }); return; }
    const tmp = path + ".tmp";
    writeFileSync(tmp, JSON.stringify(state, null, 2), { mode: 0o600 });
    renameSync(tmp, path);
  } catch { /* status only; never fatal */ }
}

/**
 * Start and supervise the tunnel. Returns a handle whose `url` is the current
 * public address (null while (re)connecting). `onChange(url)` fires on every change.
 */
export function startTunnel({ config, port, onChange = () => {} }) {
  const mode = tunnelMode(config);
  const handle = {
    mode,
    url: null,
    error: null,
    rendezvous: config.rendezvous && config.rendezvous !== "off" ? config.rendezvous.replace(/\/+$/, "") : null,
    stop,
  };
  if (mode === "off") return handle;

  const origin = tunnelOrigin(config.host, port);
  let child = null;
  let stopping = false;
  let backoff = 5_000;
  let publicFailures = 0;
  let republishTimer = null;
  let checkTimer = null;

  function setUrl(url) {
    if (handle.url === url) return;
    handle.url = url;
    writeTunnelState(config.stateDir, url ? { url, mode, pid: process.pid, at: new Date().toISOString() } : null);
    onChange(url);
    if (url) announce(url);
  }

  async function announce(url) {
    clearTimeout(republishTimer);
    if (handle.rendezvous) {
      try {
        await publishRendezvous(handle.rendezvous, config.token, config.serverId, url);
      } catch (err) {
        console.warn(`[tunnel] could not publish the new address to ${handle.rendezvous}: ${err.message}`);
      }
      republishTimer = setTimeout(() => { if (handle.url === url) announce(url); }, RENDEZVOUS_REPUBLISH_MS);
      republishTimer.unref?.();
    }
  }

  // A quick tunnel can silently stop routing while cloudflared keeps running.
  // Check it the way the phone would, and get a fresh one if it stays dead.
  async function checkPublic() {
    const url = handle.url;
    if (!url || stopping) return;
    let ok = false;
    try {
      const r = await fetch(`${url}/api/health`, { signal: AbortSignal.timeout(15_000) });
      ok = r.ok && (await r.json()).serverId === config.serverId;
    } catch { ok = false; }
    publicFailures = ok ? 0 : publicFailures + 1;
    if (publicFailures >= 3 && child) {
      console.warn("[tunnel] the public address stopped answering; starting a new tunnel");
      publicFailures = 0;
      child.kill("SIGTERM");
    }
  }

  async function launch() {
    if (stopping) return;
    let bin;
    try {
      bin = await resolveCloudflared(config.stateDir, config.cloudflaredBin);
    } catch (err) {
      handle.error = err.message;
      console.error(`[tunnel] ${err.message}`);
      setTimeout(launch, 60_000).unref?.();
      return;
    }
    const env = { ...process.env };
    let args;
    if (mode === "named") {
      env.TUNNEL_TOKEN = config.tunnelToken;   // env, not argv: argv is visible to every local user
      args = ["tunnel", "--no-autoupdate", "run"];
    } else {
      args = ["tunnel", "--no-autoupdate", "--url", origin];
    }
    const started = Date.now();
    child = spawn(bin, args, { env, stdio: ["ignore", "pipe", "pipe"] });
    const scan = (chunk) => {
      const text = String(chunk);
      if (mode === "quick") {
        const m = text.match(QUICK_URL_RE);
        if (m) { handle.error = null; setUrl(m[0]); }
      } else if (/Registered tunnel connection/i.test(text) && config.tunnelUrl) {
        handle.error = null;
        setUrl(config.tunnelUrl.replace(/\/+$/, ""));
      }
      if (/\bERR\b/.test(text)) {
        const line = text.split("\n").find((l) => /\bERR\b/.test(l));
        if (line) handle.error = line.replace(/^\S+\s+ERR\s+/, "").trim().slice(0, 200);
      }
    };
    child.stdout.on("data", scan);
    child.stderr.on("data", scan);
    child.on("error", (err) => { handle.error = err.message; });
    child.on("exit", (code) => {
      child = null;
      setUrl(null);
      if (stopping) return;
      // A tunnel that ran for a while gets restarted promptly; one that keeps dying
      // on startup backs off so it doesn't hammer Cloudflare.
      backoff = Date.now() - started > 120_000 ? 5_000 : Math.min(backoff * 2, 300_000);
      console.warn(`[tunnel] cloudflared exited (${code ?? "signal"}); retrying in ${Math.round(backoff / 1000)}s`);
      setTimeout(launch, backoff).unref?.();
    });
  }

  function stop() {
    stopping = true;
    clearTimeout(republishTimer);
    clearInterval(checkTimer);
    try { child?.kill("SIGTERM"); } catch { /* already gone */ }
    writeTunnelState(config.stateDir, null);
  }

  checkTimer = setInterval(checkPublic, PUBLIC_CHECK_MS);
  checkTimer.unref?.();
  launch();
  return handle;
}

/** `tethrx://pair` link for an address + token; the app opens it straight into pairing. */
export function pairingLink(url, token) {
  return `tethrx://pair?addr=${encodeURIComponent(url)}&token=${encodeURIComponent(token)}`;
}
