# 只用 iPhone 连接 Linux 服务器

没有个人电脑也能使用 TethrX。Grok Build 和桥接服务运行在 Linux 服务器，iPhone 是控制端。手机和服务器加入同一 Tailscale 网络后，可以通过 Wi-Fi 或蜂窝网络连接。

App 选择「连接电脑或服务器 → Linux 服务器」。桥接服务已经运行时，选择「我的桥接服务已在运行」，直接填写地址和令牌。

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

## Tailscale 与配对

按照 [Tailscale 的 Linux 安装说明](https://tailscale.com/docs/install/linux)：

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
```

用 iPhone 打开终端显示的授权网址，将服务器加入你的网络。在 iPhone 安装 Tailscale，登录同一网络并打开 VPN 连接。记下服务器的 `100.x.y.z` 地址。

先安装本仓库在 GitHub 检查通过后发布的桥接包，再让它只监听服务器的 Tailscale 地址：

```sh
npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz
GROK_REMOTE_HOST="$(tailscale ip -4)" tethrx-bridge
```

首次配对时保持 SSH 会话打开。终端会显示配对令牌，在 App 填写：

| 输入项 | 内容 |
| --- | --- |
| 桥接地址 | `http://100.x.y.z:4180`，替换为服务器实际 Tailscale 地址 |
| 配对令牌 | 服务器终端显示的 token |

点击「连接」。不需要扫码、服务器桌面或 `localhost:4180/pair` 页面。手机的 `localhost` 指向手机本身，不能用它连接服务器。配对页面仍只允许桥接服务本机访问。

已有后台桥接服务但没有保存令牌时，可在运行它的服务器账户下读取配置：

```sh
node -p 'JSON.parse(require("fs").readFileSync(require("os").homedir()+"/.grok-remote/config.json","utf8")).token'
```

令牌只在自己的 SSH 终端读取并粘贴到 App，不要放进 GitHub 或公开日志。

## SSH 断开后继续运行

先结束前台桥接进程（Ctrl-C），再以相同的非 root Linux 账户安装后台服务：

```sh
tethrx-bridge service install --host "$(tailscale ip -4)"
sudo loginctl enable-linger "$USER"
```

Linux 服务需要可用的 `systemd --user`。不支持 systemd 的容器应由容器平台或管理员配置进程管理。服务保存安装时的 Tailscale 地址；服务器重新加入网络导致地址改变时，需要更新服务配置。

在 iPhone 开启 Tailscale 并保持服务器在线，即可通过蜂窝网络连接。无需将 4180 端口映射到公网。自定义 Tailscale 访问规则或服务器防火墙时，需要允许手机经 Tailscale 访问该端口。

## 以后安装和更新

GitHub 源码更新不会自动发布到 npm。按包名运行 `npx tethrx-bridge` 或 `npm i -g tethrx-bridge` 仍可能获得旧版，因此本仓库统一使用上面的 GitHub 下载地址。该地址指向通过 GitHub CI 的桥接安装包；工作流会检查包的版本不低于 App 要求，并安装、启动打包后的程序。

需要更新已安装的后台桥接时，在同一个 Linux 账户下执行：

```sh
npm i -g --prefer-online https://github.com/zwthys-cyber/TethrX/releases/download/bridge-latest/tethrx-bridge.tgz
tethrx-bridge service restart
```

前台运行的桥接需先 Ctrl-C 停止，再使用原来的 `GROK_REMOTE_HOST` 地址启动。更新不会删除 `~/.grok-remote/` 中的配对、会话和证书。不要再用 npm 包名覆盖安装，否则可能降回旧版。

## 应用关闭时的提醒

单 App 全能签包不包含小组件、分享扩展、手表和 Live Activity，也不启用 Apple 推送权限。需要后台提醒时，可按照 README 的 ntfy 说明配置桥接服务，并在 iPhone 的 ntfy 应用订阅对应主题。
