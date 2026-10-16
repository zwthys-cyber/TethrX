# 在 iPhone 17 Pro Max / iOS 26.6 上安装

使用全能签：先签名，再安装。下载未签名的 `TethrX-iPhone17ProMax-iOS26.6-esign.ipa`：

[iPhone 17 Pro Max / iOS 26.6 发布页](https://github.com/zwthys-cyber/TethrX/releases/tag/iphone17pm-ios26.6)

只有服务器、没有个人电脑时，安装后按 [Linux 服务器指南](linux-server.md)配对。

## 编译配置

GitHub Actions 的 **ESign IPA** 使用 Xcode 26.6 编译 arm64 真机包。App 的最低系统保持 iOS 17.0；这不表示只能在 iOS 17 运行。

默认 Bundle ID 是 `nsk-164.v-team.cn`。它必须和你自己描述文件允许的 App ID 匹配。手机型号和系统版本不能证明证书、UDID 或描述文件适用于你的设备，仓库也不包含你的证书。

手动运行工作流时可以填写 `bundle_id`，使用其他描述文件允许的标识符。不要在工作流、Issue 或提交中放入 p12、密码、token 或描述文件。GitHub 生成未签名 IPA，签名仍在你自己的全能签中完成。

## 签名与安装

1. 将自己的 p12 和匹配的 `.mobileprovision` 导入全能签，输入对应的 p12 密码。
2. 导入最新的 `TethrX-iPhone17ProMax-iOS26.6-esign.ipa`。
3. 选择匹配的证书和描述文件，确认 Bundle ID 与描述文件允许的标识符一致，然后签名。
4. 签名完成后安装。使用开发签名时，按 iOS 提示启用开发者模式。

证书、描述文件必须有效且相互匹配；开发或 Ad Hoc 描述文件需要包含这台手机的实际 UDID。不能通过更改 IPA 文件名或填写其他设备的 UDID 实现适配。参见 [Apple 的描述文件说明](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)。

发布页若还保留旧的 `*-signed.ipa`，它不是本次未签名构建的签名结果。使用最新的 `*-esign.ipa` 并自行签名。

## 单 App 模式

这个包仅包含 iPhone 主程序，不申请原作者的 App Group 或共享钥匙串，也不打包手表、小组件、分享扩展和 Live Activity。配对令牌保存在主程序自己的钥匙串中。

## 通知

App 关闭或在后台时，Grok 需要审批或完成一轮回复会发提醒。正在 App 里看着该会话时不提醒。有两种方式，任选其一，也可以同时用。

### 方式一：Apple 推送（证书带推送权限时）

全能签会把描述文件里的权限写进 App。描述文件含 `aps-environment` 时，iOS 会发放设备令牌。App 会读取描述文件，把自己的 Bundle ID 和推送环境（生产或开发沙盒）告诉桥接服务，桥接服务就按这个 Bundle ID 发到对应的 Apple 服务器。

光有证书还不够：**桥接服务还需要一个 APNs 密钥（`.p8`）**，必须在签发这张证书的**同一个 Apple 开发者团队**里创建（Certificates, Identifiers & Profiles → Keys → Apple Push Notifications service），并记下 Key ID 和 Team ID。购买的共享证书通常不提供这个密钥，这种情况请用方式二。

有密钥时，在服务器上（桥接服务 0.1.33 或更新）：

```bash
GROK_REMOTE_APNS_KEY=/root/AuthKey_XXXXXXXXXX.p8 \
GROK_REMOTE_APNS_KEY_ID=XXXXXXXXXX \
GROK_REMOTE_APNS_TEAM_ID=你的TeamID \
tethrx-bridge service install --tunnel
```

密钥路径要写绝对路径。然后在 App 的 **设置 → 通知** 打开 **推送通知**，允许通知后重新连接一次服务器。该页面会显示描述文件是否带推送、推送环境、Bundle ID 和 Team ID；iOS 拒绝发放令牌时会显示原因。审批提醒带 **批准 / 拒绝** 按钮。

### 方式二：Bark（不需要 APNs 密钥）

1. 在 App Store 安装 [Bark](https://apps.apple.com/app/bark-customed-notifications/id1403753865)，打开后复制它给出的地址，例如 `https://api.day.app/你的密钥`。
2. 在服务器上：

```bash
GROK_REMOTE_BARK=https://api.day.app/你的密钥 tethrx-bridge service install --tunnel
```

提醒由 Bark 显示，点按会打开 TethrX 里对应的会话。Bark 没有批准 / 拒绝按钮，需要进 App 处理审批。Bark 地址里的密钥等同于推送权限，不要公开。启动日志只显示服务器域名，不显示密钥。

也可以继续使用 ntfy（`GROK_REMOTE_NTFY`）；现在点按 ntfy 提醒同样会打开对应会话，中文会话标题也能正常显示。

每次 GitHub 构建会检查实际 Bundle ID、单 App 标记、arm64 架构和扩展目录，再生成 IPA 与 SHA-256 文件。测试和编译均在 GitHub Actions 运行。
