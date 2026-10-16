// Per-device APNs routing (re-signed builds) and the key-less push payloads.
// `--live` also round-trips an ntfy alert with a non-Latin title through ntfy.sh.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Apns } from "../src/apns.mjs";
import { barkPayload, ntfyHeader, redactPushUrl } from "../src/notify.mjs";

const dir = mkdtempSync(join(tmpdir(), "tethrx-push-"));
const store = new Apns({ stateDir: dir, topic: "com.tethrx.app" });
const app = "a".repeat(64), esign = "b".repeat(64), dev = "c".repeat(64);

assert.equal(store.addDevice(app), true);
assert.equal(store.addDevice(esign, { topic: "nsk-164.v-team.cn", env: "production" }), true);
assert.equal(store.addDevice(dev.toUpperCase(), { topic: "nsk-164.v-team.cn", env: "development" }), true);
assert.equal(store.addDevice("zz"), false);
assert.equal(store.addDevice(app, { topic: "not a bundle id" }), false);
assert.equal(store.addDevice(app, { env: "staging" }), false);

assert.deepEqual(store.route(app), { topic: "com.tethrx.app", host: "https://api.push.apple.com" });
assert.deepEqual(store.route(esign), { topic: "nsk-164.v-team.cn", host: "https://api.push.apple.com" });
assert.deepEqual(store.route(dev), { topic: "nsk-164.v-team.cn", host: "https://api.sandbox.push.apple.com" });

const saved = JSON.parse(readFileSync(join(dir, "devices.json"), "utf8"));
assert.deepEqual(saved.tokens, [app, esign, dev]);
assert.equal(saved.info[app], undefined);
assert.equal(statSync(join(dir, "devices.json")).mode & 0o777, 0o600);

// Re-registering after moving to a production profile drops the sandbox route.
store.addDevice(dev, { topic: "nsk-164.v-team.cn", env: "production" });
assert.equal(new Apns({ stateDir: dir }).route(dev).host, "https://api.push.apple.com");

// Files written before per-device info existed still load.
const legacyDir = mkdtempSync(join(tmpdir(), "tethrx-push-legacy-"));
const { writeFileSync } = await import("node:fs");
writeFileSync(join(legacyDir, "devices.json"), JSON.stringify({ tokens: [app] }));
const legacy = new Apns({ stateDir: legacyDir });
assert.deepEqual(legacy.tokens, [app]);
assert.equal(legacy.route(app).topic, "com.tethrx.app");

const bark = barkPayload({ title: "修复登录: approval needed", message: "rm -rf build", priority: "high",
  sessionId: "s1", open: "tethrx://session/s1" });
assert.deepEqual(bark, { title: "修复登录: approval needed", body: "rm -rf build", url: "tethrx://session/s1",
  group: "TethrX", level: "timeSensitive", id: "tethrx-s1" });
assert.equal(barkPayload({ title: "t", message: "m", priority: "default", open: "x" }).level, "active");

assert.equal(ntfyHeader("Fix login: done"), "Fix login: done");
const encoded = ntfyHeader("修复登录");
assert.match(encoded, /^=\?UTF-8\?B\?[A-Za-z0-9+/=]+\?=$/);
assert.equal(Buffer.from(encoded.slice(10, -2), "base64").toString(), "修复登录");
new Headers({ Title: encoded });

assert.equal(redactPushUrl("https://api.day.app/SECRETKEY/"), "https://api.day.app/…");

if (process.argv.includes("--live")) {
  const topic = "tethrx-ci-" + Date.now().toString(36) + Math.floor(Math.random() * 1e9).toString(36);
  const r = await fetch(`https://ntfy.sh/${topic}`, {
    method: "POST",
    headers: { Title: ntfyHeader("修复登录: approval needed"), Priority: "high", Click: "tethrx://session/s1" },
    body: "echo hi",
  });
  assert.equal(r.status, 200);
  // ntfy can answer the poll before the message is stored.
  let msg;
  for (let i = 0; i < 10 && !msg; i++) {
    await new Promise((r) => setTimeout(r, 1500));
    const text = (await (await fetch(`https://ntfy.sh/${topic}/json?poll=1`)).text()).trim();
    if (text) msg = JSON.parse(text.split("\n").at(-1));
  }
  assert.ok(msg, "ntfy never returned the message");
  assert.equal(msg.title, "修复登录: approval needed");
  assert.equal(msg.click, "tethrx://session/s1");
  console.log("ntfy live: PASS");
}

console.log("push: PASS");
