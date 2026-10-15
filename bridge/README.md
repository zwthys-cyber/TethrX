# tethrx-bridge

The local bridge for **[TethrX](https://github.com/zwthys-cyber/TethrX)** — run **Grok Build** (xAI's terminal coding agent) from your phone.

The bridge runs on your computer and exposes your Grok Build install to the TethrX iOS app over HTTP + SSE: streamed thoughts, tool calls, and per-tool **approvals** you tap from your phone.

📱 **Get the app: [TethrX on the App Store](https://apps.apple.com/app/tethrx/id6792520305)** — free.

## Requirements

- **Node.js 20+**
- **Grok Build** installed and signed in (`grok --version` should work)
- An iPhone or iPad on **iOS 17+** with [TethrX](https://apps.apple.com/app/tethrx/id6792520305) installed

## Run

```bash
npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz
GROK_REMOTE_HOST=0.0.0.0 tethrx-bridge
```

It prints a **bridge address** and a **pairing token**. On the same computer, open **http://localhost:4180/pair** to get a scannable QR code, then in the TethrX app tap **Scan to pair**. That page is loopback-only, so the token never leaves the machine.

Prefer it always-on? Install it globally, then install the included launchd/systemd user service:

```bash
tethrx-bridge service install --host 0.0.0.0
```

Manage it with `tethrx-bridge service status|logs|restart|uninstall`. On Linux,
`loginctl enable-linger $USER` keeps the user service alive after you close SSH.

## Reaching it from your phone

- **Same Wi-Fi:** use the LAN address it prints.
- **Anywhere (cellular):** put your computer and phone on [Tailscale](https://tailscale.com) and use the `100.x` address. Never expose the bridge directly to the public internet — it can run commands on your machine.

## Config

Environment variables (all optional):

| Var | Default | Notes |
| --- | --- | --- |
| `GROK_REMOTE_HOST` | `127.0.0.1` | `0.0.0.0` to allow LAN/Tailscale |
| `GROK_REMOTE_PORT` | `4180` | Port |
| `GROK_BIN` | auto | Path to the `grok` binary |
| `GROK_REMOTE_ASK` | `1` | Per-tool approval prompts (`0` inherits your global grok config) |
| `GROK_REMOTE_TLS_CERT` / `_KEY` | — | Serve HTTPS |

State (pairing token, session registry) lives in `~/.grok-remote/` — never in this package.

## Updates

This fork distributes the tested bridge through [GitHub Releases](https://github.com/zwthys-cyber/TethrX/releases/tag/bridge-latest). Publishing source on GitHub does not update the npm package name; installing by name can select an older version. To update an installed background service:

```sh
npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz
tethrx-bridge service restart
```

For a foreground bridge, stop it with Ctrl-C and run it again with the same host settings. For a headless Linux server, follow the [phone-only server guide](https://github.com/zwthys-cyber/TethrX/blob/main/docs/linux-server.md); no desktop browser is needed.

## License

Apache-2.0
