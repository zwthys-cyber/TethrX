# TethrX — Security Review

SAST pass over the bridge (`bridge/src/*.mjs`) and iOS client. Threat model: the bridge
lets an **authenticated** phone run shell commands and edit files on the user's dev
machine via Grok Build, reachable over LAN / Tailscale. The pairing token is therefore
equivalent to full RCE on the host, so protecting it is the central concern.

## Executive summary

No Critical or High findings. The auth model is sound: a 192-bit random pairing token
(`crypto.randomBytes(24)`), a length-checked `timingSafeEqual` compare, and every
sensitive route gated behind it. One Medium and one Low were **fixed**; the rest are
defense-in-depth notes for how you deploy it.

## Findings

### [Medium — FIXED] Pairing token embedded in ntfy notification URLs
`notifyPermission()` previously put `Authorization: Bearer <pairing-token>` into the
ntfy Action buttons. That token = full RCE, and it would travel to (and rest on) the
ntfy server; anyone who could read the topic could take over the host.
**Fix:** lock-screen actions now use **single-use, decision-bound tokens** (`/api/approve/:token`)
that resolve exactly one pending permission and expire in 15 min. The pairing token is
never sent to ntfy. Blast radius of a leaked link: approve/reject one already-proposed
action, once. (Still: keep the ntfy topic secret and prefer self-hosted ntfy.)

### [Low — FIXED] Static-file prefix check could match sibling dirs
`full.startsWith(PUBLIC_DIR)` matches `.../public-anything`. Not exploitable today (no
such sibling), but hardened to `full === PUBLIC_DIR || full.startsWith(PUBLIC_DIR + sep)`.

### [Low] Cleartext HTTP when bound beyond loopback
Default bind is `127.0.0.1` (safe). If you set `GROK_REMOTE_HOST=0.0.0.0` without TLS on
an untrusted LAN, the token is sniffable. **Mitigation:** use Tailscale (WireGuard-encrypted)
or enable TLS (`scripts/gen-cert.sh`) when binding beyond loopback.

### [Info] Internet tunnel (`--tunnel`)
The tunnel puts the bridge on a public `trycloudflare.com` address, so the 192-bit token is
the only barrier against the internet, and traffic is decrypted at Cloudflare's edge.
The bridge itself stays bound to loopback. Requests carrying proxy headers
(`cf-connecting-ip`, `cf-ray`, `x-forwarded-for`) are never treated as loopback, so `/pair`
(which shows the token) refuses them; CI checks this through a real tunnel. The address
announcement on ntfy uses a topic of `sha256("tethrx-rendezvous-topic\n" + token)` and an
HMAC-SHA256 keyed with the token. The app ignores unsigned or foreign announcements, so a
third party cannot redirect it, and the token never leaves the two devices. `cloudflared` is
downloaded over HTTPS from Cloudflare's GitHub releases; set `GROK_REMOTE_CLOUDFLARED` to
use a binary you installed and verified yourself. Pairing links opened from other apps
need confirmation in the app, so a web page cannot silently pair the phone with another bridge.

### [Low] `?token=` query-param auth can leak via logs/referrer
SSE accepts `?token=` because browser `EventSource` can't set headers. Query strings can
land in proxy/access logs. The iOS app uses the `Authorization` header; the query form is
only for the browser test client — keep it to trusted networks.

### [Info] Unauthenticated `/api/health` exposes the grok version + bridge name
Intended (reachability probe before pairing); minor version fingerprinting.

### [Info] Request bodies are unbounded; error strings are returned to the client
Both are post-auth (operator-only) so low risk; consider a body-size cap and generic 500s
if you ever broaden the trust boundary.

## Not vulnerabilities (checked)
- **Command injection** — `spawn(grokBin, args)` uses array args (no shell); user prompt/cwd
  drive Grok by design (authenticated operator on their own machine).
- **CSRF** — stateless Bearer-token API (no cookies); a browser can't forge the header.
- **Prototype pollution** — request bodies are read field-by-field, never merged.
- **IDOR** — single-user model; the one token owns all sessions.
- **Redirected-HOME config** — derived from the operator's own `~/.grok` config (trusted input).
