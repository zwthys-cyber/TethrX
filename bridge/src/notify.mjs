// Payloads for the push services that need no APNs key on this computer.

/** Bark (https://bark.day.app) JSON body. Tapping opens `open` in TethrX. */
export function barkPayload({ title, message, priority, sessionId, open }) {
  return {
    title, body: message, url: open, group: "TethrX",
    level: priority === "high" ? "timeSensitive" : "active",
    // Same id replaces the previous alert, so approval reminders don't pile up.
    ...(sessionId ? { id: `tethrx-${sessionId}`.slice(0, 64) } : {}),
  };
}

/** fetch() rejects header values outside Latin-1, which silently dropped every ntfy
 *  alert for a session titled in Chinese. ntfy decodes RFC 2047 encoded words. */
export function ntfyHeader(value) {
  const s = String(value ?? "");
  return /^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${Buffer.from(s).toString("base64")}?=`;
}

/** Bark URLs carry the device key in the path; show the origin only. */
export function redactPushUrl(u) {
  try { return `${new URL(u).origin}/…`; } catch { return "set"; }
}
