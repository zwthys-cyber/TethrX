# 在 iPhone 17 Pro Max / iOS 26.6 上安装

巨魔（TrollStore）不能在 iOS 26 上安装。这台手机用已签名的 IPA。

下载：[iPhone 17 Pro Max / iOS 26.6 发布页](https://github.com/zwthys-cyber/TethrX/releases/tag/iphone17pm-ios26.6)

| 文件 | 用途 |
|---|---|
| `TethrX-iPhone17ProMax-iOS26.6-signed.ipa` | 安装这个。已经用本机证书签好 |
| `TethrX-iPhone17ProMax-iOS26.6-esign.ipa` | 未签名。只有要重新签名时才用。GitHub Actions 用 Xcode 26.6 编译 |

已签名包只属于下面这一台设备：

| 项目 | 值 |
|---|---|
| 机型 | iPhone 17 Pro Max（UDID 前缀 `00008150`，A19 / A19 Pro） |
| UDID | `00008150-0015748602A3C01C` |
| 系统 | iOS 26.6。包的最低系统仍是 iOS 17.0 |
| Bundle ID | `nsk-164.v-team.cn` |
| 团队 | `YQTF39XU3L` |
| 证书 | iPhone Distribution，到 2027-10-06 |
| 描述文件 | 到 2027-10-15。这是开发描述文件 |

用全能签打开已签名的 IPA，直接安装。如果全能签要求重新签名，使用同一份 p12 和同一份描述文件，Bundle ID 保持 `nsk-164.v-team.cn`。

装好后打开「设置 → 隐私与安全性 → 开发者模式」，按提示重启并确认。开发描述文件需要这一步，App 才能打开。

这个包只有 iPhone 主程序。手表、主屏幕小组件和分享扩展没有打进去，因为这份描述文件只有一个 App ID。配对在 App 自己的钥匙串里完成。iOS 17 的巨魔包仍在[最新正式发布](https://github.com/zwthys-cyber/TethrX/releases/latest)，不能装到 iOS 26。
