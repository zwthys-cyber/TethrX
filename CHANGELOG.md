# Changelog

## 1.1.7 (57) — 2026-10-15

### Added

- A Linux server pairing path: SSH setup from the phone, Grok device-code sign-in, Tailscale on the server and iPhone, then address/token pairing. No server browser or QR code is required. Includes Simplified Chinese instructions.
- A direct-connect shortcut for an existing bridge and a [Linux server deployment guide](docs/linux-server.md).

### Fixed

- The standalone ESign build now uses the selected Bundle ID and omits the original app's shared keychain, App Group and APNs entitlements. Runtime features match the single-app package.
- Shared keychain access resolves the signing prefix from build settings instead of hardcoding the original author's team.
- Updating a pairing token preserves its previous value when a keychain update fails.
- GitHub Actions checks the ESign preparation, embedded targets, Bundle ID and arm64 binary before packaging. Validation and compilation run on GitHub.

## 1.1.6 (56) — 2026-10-15

### Changed

- The pairing step that shows `http://localhost:4180/pair` now says to type that address on the computer. Opening it on the phone cannot work.
- The bridge start command listens on the network (`GROK_REMOTE_HOST=0.0.0.0`) so the pairing page can show a QR code the phone is able to reach.

## Sideload

- GitHub Actions workflow **ESign IPA** builds `TethrX-iPhone17ProMax-iOS26.6-esign.ipa` for iPhone 17 Pro Max / iOS 26.6. 全能签 signs that unsigned IPA, then installs it. Bundle id `nsk-164.v-team.cn`, UDID `00008150-0015748602A3C01C`. Steps are in [docs/iphone17pm-ios26.6.md](docs/iphone17pm-ios26.6.md). The Watch app, widget, and share extension are left out. TrollStore packages stay on the iOS 17 release.

## 1.1.5 (55) — 2026-09-25

### Fixed

- Opening a chat shows the latest message immediately. 1.1.4 still animated the trip down from the top.

## 1.1.4 (54) — 2026-09-25

### Fixed

- Opening a chat scrolls to the latest message. The previous build only moved a short way down, because the list had not laid out the rest of the conversation yet.

## 1.1.3 (53) — 2026-09-25

### Changed

- Conversation text is slightly smaller.
- Opening a chat lands on the latest message instead of the start of the page.

## 1.1.2 (52) — 2026-09-25

### Added

- Show pictures Grok generates in the conversation. A reply that names `images/1.jpg` loads that file from the session and draws it inline.

### Bridge

- Updated `tethrx-bridge` to 0.1.29. The app asks for this bridge or newer, because an older one cannot serve those pictures.
- `GET /api/sessions/:id/media` serves one generated image from that Grok session and nothing else on disk.

## 1.1.1 (50) — 2026-09-24

### Added

- Select the Grok model used by new sessions.
- Show daily usage broken down by model, including tokens, turns, and cost.
- Use Grok-generated conversation titles while keeping the workspace visible.
- Generate Simplified Chinese titles for Chinese conversations without copying the user's prompt.

### Fixed

- Prevent intermittent blank/grey settings pages.
- Restore the interactive left-edge back gesture inside Settings.
- Preserve event timestamps so completed reasoning shows its real duration after reopening a session.
- Show legacy reasoning without a fabricated `0s` duration when historical timing is unavailable.

### Bridge

- Updated `tethrx-bridge` to 0.1.28.
- Persist per-model usage and timestamps for replay.
- Added dynamic model discovery and model-aware session creation.

### Build

- Build with macOS 26 and Xcode 26.6.
- Moved GitHub Actions to Node.js 24-based action versions and pinned Linux CI to Ubuntu 24.04.
