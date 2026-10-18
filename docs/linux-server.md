# 只用 iPhone 连接 Linux 服务器

没有个人电脑也能使用 TethrX。Grok Build 和桥接服务运行在 Linux 服务器，iPhone 是控制端。桥接服务用 `--tunnel` 启动后，会自动获得一个公网 `https://….trycloudflare.com` 地址：**手机只要能上网（Wi-Fi 或蜂窝网络）就能连接，不需要 Tailscale 或其他 VPN，不需要公网 IP，也不需要开放端口。**

App 选择「连接电脑或服务器 → Linux 服务器」。桥接服务已经运行时，选择「我的桥接服务已在运行」，直接粘贴配对链接。

## 准备服务器

用 iPhone 的 SSH 应用或云服务商网页终端登录服务器。以下命令均在服务器执行，Grok Build 和桥接服务使用同一个 Linux 账户。

需要 Node.js 20 或更新版本，请按 [Node.js 官方说明](https://nodejs.org/en/download)安装 Linux 版本。

按照 [Grok Build 官方说明](https://docs.x.ai/build/overview)安装：

```sh
curl -fsSL https://x.ai/cli/install.sh | bash
```

无浏览器服务器使用[设备码登录](https://docs.x.ai/build/cli/reference)：

```sh
grok login --device-auth
```

把终端显示的授权网址复制到 iPhone 的 Safari，输入设备码完成登录。无需在服务器弹出浏览器。

## 使用 DeepSeek

模型列表里会多出 `deepseek-flash[1m]` 和 `deepseek-flash`。选中之后，这一路会话走 Claude Code 和 DeepSeek 的 API，不再走 Grok。手机上能看到回复和思考过程；工具是否执行由 Claude 自己的权限模式决定，不会弹出 Grok 那种逐条批准卡片。

在启动桥接的同一个账户里设置 Key（用你自己的，不要写进仓库）：

```sh
export DEEPSEEK_API_KEY='你的 DeepSeek API Key'
```

也可以写进 `~/.grok-remote/config.json` 的 `deepseekApiKey` 字段。服务器上需要已安装 Claude Code（`claude` 命令可用）。

## 启动桥接并配对（无需 VPN）

安装本仓库在 GitHub 检查通过后发布的桥接包，然后以互联网隧道方式启动：

```sh
npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz
tethrx-bridge --tunnel
```

首次启动会从 Cloudflare 的 GitHub 发布页自动下载 `cloudflared` 到 `~/.grok-remote/bin/`（已安装 `cloudflared` 时直接使用）。不需要 Cloudflare 账户。几秒后终端会显示：

```
  ── internet address (no VPN needed) ──  https://xxxx-xxxx.trycloudflare.com
  Pairing link: copy it, then open it on your iPhone or paste it into TethrX:

     tethrx://pair?addr=https%3A%2F%2Fxxxx-xxxx.trycloudflare.com&token=…
```

复制整条 `tethrx://pair…` 链接，然后任选一种方式：

- 在 iPhone 上打开这条链接（例如粘贴到 Safari 地址栏），App 会询问是否配对，点「配对」。
- 或在 App 的「连接你的服务器」页面点「粘贴」，也可以把链接粘贴到「桥接地址」输入框。

之后无论在 Wi-Fi 还是蜂窝网络下，App 都能直接连接。配对页面 `localhost:4180/pair` 和令牌不会通过隧道暴露；经隧道的每个请求仍然必须带配对令牌。

链接或终端内容滚走了，可以在同一个账户下重新显示：

```sh
tethrx-bridge pair
```

链接中包含配对令牌，只在自己的 SSH 终端查看，不要放进 GitHub、聊天截图或公开日志。

## 地址变化时自动跟随

免费的快速隧道每次重启（服务器重启、网络中断、桥接重启）都会换一个新地址。桥接服务会把新地址发布到 ntfy.sh 上的一个“会合”主题：主题名和每条消息的签名都由配对令牌派生，令牌本身不会发送出去。App 连不上旧地址时，会查询这个主题，只接受用本机令牌签名的地址，确认是同一台服务器后自动切换，无需重新配对。

不想使用 ntfy.sh，可以用 `GROK_REMOTE_RENDEZVOUS=off` 关闭（地址变化后需要重新粘贴配对链接），或用 `GROK_REMOTE_RENDEZVOUS=https://你的-ntfy-服务器` 指向自建的 ntfy。

## 固定地址（可选）

有自己的域名并托管在 Cloudflare 时，可以创建一个命名隧道（Cloudflare Zero Trust → Networks → Tunnels），把公共主机名指向 `http://127.0.0.1:4180`，然后：

```sh
GROK_REMOTE_TUNNEL_TOKEN="隧道令牌" GROK_REMOTE_TUNNEL_URL="https://tethrx.example.com" tethrx-bridge
```

地址永久不变。隧道令牌同样属于机密，不要公开。

## SSH 断开后继续运行

先结束前台桥接进程（Ctrl-C），再以相同的非 root Linux 账户安装后台服务：

```sh
tethrx-bridge service install --tunnel
sudo loginctl enable-linger "$USER"
tethrx-bridge pair
```

Linux 服务需要可用的 `systemd --user`。不支持 systemd 的容器应由容器平台或管理员配置进程管理（启动命令为 `tethrx-bridge --tunnel`）。`tethrx-bridge service status` 会显示当前的互联网地址。

## 仍可使用 Tailscale 或局域网

不想经过 Cloudflare 时，原来的方式依然可用：服务器和 iPhone 加入同一 Tailscale 网络，用 `GROK_REMOTE_HOST="$(tailscale ip -4)" tethrx-bridge` 启动，在 App 中填写 `http://100.x.y.z:4180` 和配对令牌。

## 以后安装和更新

GitHub 源码更新不会自动发布到 npm。按包名运行 `npx tethrx-bridge` 或 `npm i -g tethrx-bridge` 仍可能获得旧版，因此本仓库统一使用上面的 GitHub 下载地址。该地址指向通过 GitHub CI 的桥接安装包；工作流会检查包的版本不低于 App 要求，安装、启动打包后的程序，并通过真实的 Cloudflare 隧道从公网验证连接、令牌校验和实时事件流。

需要更新已安装的后台桥接时，在同一个 Linux 账户下执行：

```sh
npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz
tethrx-bridge service restart
```

前台运行的桥接需先 Ctrl-C 停止，再用 `tethrx-bridge --tunnel` 启动。更新不会删除 `~/.grok-remote/` 中的配对、会话和证书。不要再用 npm 包名覆盖安装，否则可能降回旧版。

## 应用关闭时的提醒

单 App 全能签包不包含小组件、分享扩展、手表和 Live Activity，也不启用 Apple 推送权限。需要后台提醒时，可按照 README 的 ntfy 说明配置桥接服务，并在 iPhone 的 ntfy 应用订阅对应主题。开启隧道后，ntfy 提醒中的「批准 / 拒绝」按钮会自动使用隧道地址。
