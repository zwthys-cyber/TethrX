# Changelog

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
