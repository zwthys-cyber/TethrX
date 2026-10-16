// Writes announcements signed by the bridge's own code, for ios/tools/rendezvoustest.swift
// to verify with the app's code: the two sides must agree byte for byte.
//
//   node bridge/test/rendezvous-fixture.mjs /tmp/rendezvous.json
import { writeFileSync } from "node:fs";
import { rendezvousTopic, rendezvousMessage, pairingLink } from "../src/tunnel.mjs";

const token = "Qm9yZWQ_tethrx-fixture-token-ab12";
const serverId = "fixture-server";
const line = (message) => JSON.stringify({ id: "x", event: "message", topic: "t", message });
const body = [
  line(rendezvousMessage(token, { url: "https://older.trycloudflare.com", serverId, ts: 1_700_000_000_000 })),
  line(rendezvousMessage(token, { url: "https://newest.trycloudflare.com", serverId, ts: 1_700_000_500_000 })),
  line(JSON.stringify({ v: 1, url: "https://forged.example", serverId, ts: 1_800_000_000_000, sig: "ab".repeat(32) })),
  line(rendezvousMessage("another-token", { url: "https://other-key.example", serverId, ts: 1_800_000_000_001 })),
  line(rendezvousMessage(token, { url: "https://other-bridge.trycloudflare.com", serverId: "other", ts: 1_800_000_000_002 })),
  line(rendezvousMessage(token, { url: "http://cleartext.example", serverId, ts: 1_800_000_000_003 })),
  JSON.stringify({ id: "y", event: "keepalive" }),
].join("\n");

writeFileSync(process.argv[2], JSON.stringify({
  token, serverId, body,
  topic: rendezvousTopic(token),
  expectUrl: "https://newest.trycloudflare.com",
  pairingLink: pairingLink("https://newest.trycloudflare.com", "tok/+=&x"),
}, null, 2));
console.log(`fixture written to ${process.argv[2]}`);
