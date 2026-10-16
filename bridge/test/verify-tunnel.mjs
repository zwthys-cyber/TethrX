// Internet access without a VPN (src/tunnel.mjs).
//
//   node bridge/test/verify-tunnel.mjs                 unit checks only
//   node bridge/test/verify-tunnel.mjs --e2e [server]  also start a real bridge with
//                                                      --tunnel and drive it through
//                                                      Cloudflare, as the phone would
//
// `server` defaults to this checkout's src/server.mjs; CI passes the installed
// package's bin so the distributed tarball is what gets tested.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  tunnelMode, tunnelOrigin, rendezvousTopic, rendezvousMessage, latestRendezvous, pairingLink,
} from "../src/tunnel.mjs";

let failures = 0;
function check(name, fn) {
  try { fn(); console.log(`ok   ${name}`); }
  catch (err) { failures++; console.log(`FAIL ${name}\n     ${err.message}`); }
}

// --- unit --------------------------------------------------------------------

check("tunnel mode is opt-in", () => {
  assert.equal(tunnelMode({}), "off");
  assert.equal(tunnelMode({ tunnel: "0" }), "off");
  assert.equal(tunnelMode({ tunnel: "off" }), "off");
  assert.equal(tunnelMode({ tunnel: "1" }), "quick");
  assert.equal(tunnelMode({ tunnel: "cloudflare" }), "quick");
  assert.equal(tunnelMode({ tunnel: "", tunnelToken: "abc" }), "named");
});

check("cloudflared targets loopback unless the bridge is bound to one address", () => {
  assert.equal(tunnelOrigin("127.0.0.1", 4180), "http://127.0.0.1:4180");
  assert.equal(tunnelOrigin("0.0.0.0", 4180), "http://127.0.0.1:4180");
  assert.equal(tunnelOrigin("::", 4180), "http://127.0.0.1:4180");
  assert.equal(tunnelOrigin("100.64.0.7", 4180), "http://100.64.0.7:4180");
  assert.equal(tunnelOrigin("fd7a::1", 4180), "http://[fd7a::1]:4180");
});

const token = "k3Jx9_bridge-token-for-tests-0123456789";
const serverId = "srv-abc123";
const ntfyLine = (message) => JSON.stringify({ id: Math.random().toString(36).slice(2), event: "message", topic: "t", message });

check("the rendezvous topic never contains the token", () => {
  const topic = rendezvousTopic(token);
  assert.match(topic, /^tethrx-[0-9a-f]{40}$/);
  assert.ok(!topic.includes(token));
  assert.notEqual(topic, rendezvousTopic(token + "x"));
});

check("the newest signed address wins; forged, foreign and plain-http ones are ignored", () => {
  const older = rendezvousMessage(token, { url: "https://old-one.trycloudflare.com", serverId, ts: 1000 });
  const newer = rendezvousMessage(token, { url: "https://new-one.trycloudflare.com", serverId, ts: 2000 });
  const forged = JSON.stringify({ v: 1, url: "https://evil.example", serverId, ts: 9999, sig: "00".repeat(32) });
  const otherKey = rendezvousMessage("someone-else", { url: "https://evil2.example", serverId, ts: 9998 });
  const otherBridge = rendezvousMessage(token, { url: "https://other-bridge.trycloudflare.com", serverId: "other", ts: 9997 });
  const plain = rendezvousMessage(token, { url: "http://cleartext.example", serverId, ts: 9996 });
  const body = [older, forged, newer, otherKey, otherBridge, plain, "not json", JSON.stringify({ event: "open" })]
    .map((m) => (m.startsWith("{\"event\"") ? m : ntfyLine(m))).join("\n");
  const best = latestRendezvous(token, body, serverId);
  assert.equal(best?.url, "https://new-one.trycloudflare.com");
  assert.equal(latestRendezvous("wrong-token", body, serverId), null);
});

check("pairing links carry the full https address and the token", () => {
  const link = pairingLink("https://a-b-c.trycloudflare.com", "tok/+=");
  assert.equal(link, "tethrx://pair?addr=https%3A%2F%2Fa-b-c.trycloudflare.com&token=tok%2F%2B%3D");
  const u = new URL(link);
  assert.equal(u.searchParams.get("addr"), "https://a-b-c.trycloudflare.com");
  assert.equal(u.searchParams.get("token"), "tok/+=");
});

// --- end to end ----------------------------------------------------------------

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function poll(what, timeoutMs, fn) {
  const until = Date.now() + timeoutMs;
  let last;
  while (Date.now() < until) {
    try { const v = await fn(); if (v) return v; } catch (err) { last = err; }
    await sleep(1500);
  }
  throw new Error(`timed out waiting for ${what}${last ? ` (${last.message})` : ""}`);
}

async function e2e(serverPath) {
  const home = mkdtempSync(join(tmpdir(), "tethrx-tunnel-"));
  const port = 4280;
  const env = {
    ...process.env, HOME: home,
    GROK_REMOTE_PORT: String(port), GROK_REMOTE_TLS_PORT: String(port + 1),
    GROK_REMOTE_GROK_AUTO_UPDATE: "0", GROK_BIN: "/nonexistent/grok",
  };
  const isScript = serverPath.endsWith(".mjs");
  const cmd = isScript ? process.execPath : serverPath;
  const args = isScript ? [serverPath, "--tunnel"] : ["--tunnel"];
  const bridge = spawn(cmd, args, { env, stdio: ["ignore", "pipe", "pipe"] });
  let output = "";
  bridge.stdout.on("data", (d) => { output += d; });
  bridge.stderr.on("data", (d) => { output += d; });
  const local = `http://127.0.0.1:${port}`;

  try {
    const health = await poll("the tunnel address", 180_000, async () => {
      const h = await (await fetch(`${local}/api/health`)).json();
      return h.tunnel?.url ? h : null;
    });
    const url = health.tunnel.url;
    const bridgeToken = JSON.parse(readFileSync(join(home, ".grok-remote", "config.json"), "utf8")).token;
    console.log(`     tunnel: ${url}`);
    assert.match(url, /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/);
    assert.equal(health.tunnel.rendezvous, "https://ntfy.sh");
    assert.equal(health.streamPost, true);

    const pub = await poll("the public address to answer", 120_000, async () => {
      const r = await fetch(`${url}/api/health`, { signal: AbortSignal.timeout(10_000) });
      return r.ok ? r.json() : null;
    });
    assert.equal(pub.serverId, health.serverId, "the public address reaches THIS bridge");
    console.log("ok   the bridge answers on its public internet address");

    const auth = { Authorization: `Bearer ${bridgeToken}` };
    assert.equal((await fetch(`${url}/api/sessions`)).status, 401);
    assert.equal((await fetch(`${url}/api/sessions`, { headers: auth })).status, 200);
    console.log("ok   the pairing token is still required over the internet");

    const pair = await fetch(`${url}/pair`, { headers: { "sec-fetch-site": "none" } });
    assert.equal(pair.status, 403, "the pairing page must not open through the tunnel");
    assert.ok(!(await pair.text()).includes(bridgeToken));
    console.log("ok   the pairing page (and token) stays off the internet");

    const session = await (await fetch(`${url}/api/sessions`, {
      method: "POST", headers: { ...auth, "content-type": "application/json" },
      body: JSON.stringify({ cwd: home, title: "tunnel" }),
    })).json();
    assert.ok(session.id);

    // The phone's stream: it must deliver events WHILE the connection stays open.
    const ac = new AbortController();
    const started = Date.now();
    const stream = await fetch(`${url}/api/sessions/${session.id}/stream`, {
      method: "POST", headers: { ...auth, accept: "text/event-stream" }, signal: ac.signal,
    });
    assert.equal(stream.status, 200);
    const reader = stream.body.getReader();
    let buf = "";
    let sawRetryAt = 0;
    let sawEventAt = 0;
    let queuedAt = 0;
    const readLoop = (async () => {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += Buffer.from(value).toString();
        if (!sawRetryAt && buf.includes("retry:")) sawRetryAt = Date.now();
        if (queuedAt && !sawEventAt && /data: \{[^\n]*"kind":"(queue|turn_start|error)"/.test(buf)) sawEventAt = Date.now();
      }
    })().catch(() => {});
    await poll("the stream to open", 15_000, async () => sawRetryAt);
    queuedAt = Date.now();
    const q = await fetch(`${url}/api/sessions/${session.id}/queue`, {
      method: "POST", headers: { ...auth, "content-type": "application/json" }, body: JSON.stringify({ text: "over the internet" }),
    });
    assert.equal(q.status, 200);
    await poll("a live event through the tunnel", 20_000, async () => sawEventAt);
    console.log(`ok   POST stream is live through the tunnel (opened in ${sawRetryAt - started}ms, event after ${sawEventAt - queuedAt}ms)`);
    ac.abort();
    await readLoop;

    const found = await poll("the signed address on the rendezvous topic", 60_000, async () => {
      const r = await fetch(`https://ntfy.sh/${rendezvousTopic(bridgeToken)}/json?poll=1&since=12h`, { signal: AbortSignal.timeout(10_000) });
      const rec = latestRendezvous(bridgeToken, await r.text(), health.serverId);
      return rec?.url === url ? rec : null;
    });
    assert.equal(found.url, url);
    console.log("ok   the address is announced, signed, for the phone to follow");

    const pairCmd = spawnSync(cmd, isScript ? [serverPath, "pair"] : ["pair"], { env, encoding: "utf8" });
    assert.ok(pairCmd.stdout.includes(pairingLink(url, bridgeToken)), "`tethrx-bridge pair` prints the link");
    console.log("ok   `tethrx-bridge pair` prints the pairing link");

    assert.ok(!readFileSync(join(home, ".grok-remote", "tunnel.json"), "utf8").includes(bridgeToken),
      "tunnel.json must not hold the token");

    const logs = await (await fetch(`${local}/api/logs`, { headers: auth })).text();
    assert.ok(!logs.includes(bridgeToken), "the pairing link must be redacted from /api/logs");
    console.log("ok   the pairing link is redacted from the shareable logs");
  } catch (err) {
    failures++;
    console.log(`FAIL end to end\n     ${err.message}\n----- bridge output -----\n${output.slice(-4000)}`);
  } finally {
    bridge.kill("SIGTERM");
    await new Promise((r) => bridge.once("exit", r));
  }
  if (existsSync(join(home, ".grok-remote", "tunnel.json"))) {
    failures++;
    console.log("FAIL tunnel.json is removed on shutdown");
  } else {
    console.log("ok   tunnel.json is removed on shutdown");
  }
}

const i = process.argv.indexOf("--e2e");
if (i !== -1) {
  const serverPath = process.argv[i + 1] || fileURLToPath(new URL("../src/server.mjs", import.meta.url));
  await e2e(serverPath);
}

if (failures) {
  console.log(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nall tunnel checks passed");
