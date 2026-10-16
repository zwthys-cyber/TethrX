// Temporary experiment: which streaming response shapes does a Cloudflare quick
// tunnel deliver in real time?
import { createServer } from "node:http";
import { spawn } from "node:child_process";

const variants = {
  "GET text/event-stream": { method: "GET", type: "text/event-stream" },
  "GET text/event-stream +no-transform": { method: "GET", type: "text/event-stream", extra: { "cache-control": "no-cache, no-transform" } },
  "GET application/octet-stream": { method: "GET", type: "application/octet-stream", extra: { "cache-control": "no-cache, no-transform" } },
  "GET application/x-ndjson": { method: "GET", type: "application/x-ndjson", extra: { "cache-control": "no-cache, no-transform" } },
  "GET text/plain": { method: "GET", type: "text/plain; charset=utf-8", extra: { "cache-control": "no-cache, no-transform" } },
  "POST text/event-stream": { method: "POST", type: "text/event-stream", extra: { "cache-control": "no-cache, no-transform" } },
  "POST application/octet-stream": { method: "POST", type: "application/octet-stream", extra: { "cache-control": "no-cache, no-transform" } },
};

const server = createServer((req, res) => {
  const name = decodeURIComponent(new URL(req.url, "http://x").searchParams.get("v") || "");
  const v = variants[name];
  if (!v) { res.writeHead(404); return res.end(); }
  req.resume();
  res.writeHead(200, { "content-type": v.type, "x-accel-buffering": "no", ...(v.extra || {}) });
  res.write("retry: 3000\n\n");
  let n = 0;
  const t = setInterval(() => {
    res.write(`id: ${++n}\ndata: {"n":${n}}\n\n`);
    if (n >= 8) { clearInterval(t); setTimeout(() => res.end(), 3000); }
  }, 500);
  req.on("close", () => clearInterval(t));
});
await new Promise((r) => server.listen(8080, "127.0.0.1", r));

const cf = spawn(process.env.CLOUDFLARED || "cloudflared", ["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:8080"], { stdio: ["ignore", "pipe", "pipe"] });
const base = await new Promise((resolve, reject) => {
  const to = setTimeout(() => reject(new Error("no tunnel url")), 60000);
  const scan = (d) => {
    const m = String(d).match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if (m) { clearTimeout(to); resolve(m[0]); }
  };
  cf.stdout.on("data", scan); cf.stderr.on("data", scan);
});
console.log("tunnel", base);

for (let i = 0; i < 30; i++) {
  try { const r = await fetch(base + "/?v=x", { signal: AbortSignal.timeout(5000) }); console.log("ready?", r.status); if (r.status === 404) break; } catch (e) { console.log("not ready", e.message); }
  await new Promise((r) => setTimeout(r, 2000));
}

for (const [name, v] of Object.entries(variants)) {
  console.log('probing', name);
  const start = Date.now();
  const times = [];
  const ac = new AbortController();
  const kill = setTimeout(() => ac.abort(), 25000);
  try {
    const r = await fetch(`${base}/?v=${encodeURIComponent(name)}`, { signal: ac.signal, method: v.method, body: v.method === "POST" ? "{}" : undefined, headers: { accept: "text/event-stream" } });
    const reader = r.body.getReader();
    let buf = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += Buffer.from(value).toString();
      for (const m of buf.matchAll(/data: \{"n":(\d+)\}/g)) times[Number(m[1])] ??= Date.now() - start;
    }
    console.log(`${name.padEnd(40)} status=${r.status} enc=${r.headers.get("content-encoding")} first=${times[1]}ms last=${times[8]}ms spread=${times[8] - times[1]}ms`);
  } catch (e) {
    console.log(`${name.padEnd(40)} ERROR ${e.message} times=${JSON.stringify(times)}`);
  }
  clearTimeout(kill);
}
cf.kill();
server.close();
process.exit(0);
