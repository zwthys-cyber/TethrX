# Changelog

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
