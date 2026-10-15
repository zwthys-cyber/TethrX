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

这个包仅包含 iPhone 主程序，不申请原作者的 App Group、共享钥匙串或 Apple 推送权限，也不打包手表、小组件、分享扩展和 Live Activity。配对令牌保存在主程序自己的钥匙串中。需要后台提醒时可使用 ntfy。

每次 GitHub 构建会检查实际 Bundle ID、单 App 标记、arm64 架构和扩展目录，再生成 IPA 与 SHA-256 文件。测试和编译均在 GitHub Actions 运行。
