// CI contract: the package we distribute must satisfy the app's required bridge
// version. Optionally check the installed tarball rather than the source checkout.
import assert from "node:assert/strict";
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve, join } from "node:path";
import { BRIDGE_INSTALL_COMMAND } from "../src/distribution.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const packageRoot = process.argv[2] ? resolve(process.argv[2]) : join(root, "bridge");
const pkg = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"));
const app = readFileSync(join(root, "ios/GrokRemote/AppState.swift"), "utf8");
const wanted = app.match(/wantedBridgeVersion\s*=\s*"(\d+\.\d+\.\d+)"/)?.[1];
const installCommand = app.match(/bridgeInstallCommand\s*=\s*"([^"]+)"/)?.[1];
assert.equal(installCommand, BRIDGE_INSTALL_COMMAND, "App and bridge must use the same tested distribution");
assert.ok(wanted, "App must declare its minimum bridge version");
assert.equal(pkg.name, "tethrx-bridge");
assert.match(pkg.version, /^\d+\.\d+\.\d+$/);
const actualParts = pkg.version.split(".").map(Number);
const wantedParts = wanted.split(".").map(Number);
let comparison = 0;
for (let i = 0; i < 3 && comparison === 0; i++) comparison = Math.sign(actualParts[i] - wantedParts[i]);
assert.ok(comparison >= 0, `Bridge ${pkg.version} is older than the app's required ${wanted}`);
for (const file of ["src/server.mjs", "src/sessions.mjs", "src/titles.mjs", "public/index.html", "public/qrcode.js"]) {
  assert.ok(existsSync(join(packageRoot, file)), `Distributed package is missing ${file}`);
}

if (process.env.TETHRX_MANIFEST_PATH) {
  writeFileSync(process.env.TETHRX_MANIFEST_PATH, JSON.stringify({
    version: pkg.version,
    minimumRequiredByApp: wanted,
    commit: process.env.GITHUB_SHA,
  }, null, 2) + "\n");
}
console.log(`Bridge ${pkg.version} satisfies app minimum ${wanted}; package contents present`);
