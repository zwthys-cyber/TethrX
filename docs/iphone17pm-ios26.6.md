# 在 iPhone 17 Pro Max / iOS 26.6 上安装

巨魔（TrollStore）不能在 iOS 26 上安装。这台手机用全能签：先签名，再安装。全能签没有直接安装。

下载：[iPhone 17 Pro Max / iOS 26.6 发布页](https://github.com/zwthys-cyber/TethrX/releases/tag/iphone17pm-ios26.6)

用未签名的 `TethrX-iPhone17ProMax-iOS26.6-esign.ipa`。GitHub Actions 用 Xcode 26.6 编译。`TethrX-iPhone17ProMax-iOS26.6-signed.ipa` 只是同一份包的签名结果，全能签仍会再签一次，不必用它。

证书只属于下面这一台设备：

| 项目 | 值 |
|---|---|
| 机型 | iPhone 17 Pro Max（UDID 前缀 `00008150`，A19 / A19 Pro） |
| UDID | `00008150-0015748602A3C01C` |
| 系统 | iOS 26.6。包的最低系统仍是 iOS 17.0 |
| Bundle ID | `nsk-164.v-team.cn` |
| 团队 | `YQTF39XU3L` |
| 证书 | iPhone Distribution，到 2027-10-06 |
| 描述文件 | 到 2027-10-15。这是开发描述文件 |
| p12 密码 | 证书包里的 `密码.txt` |

在全能签里按这个顺序做：

1. 导入 p12 和同包里的 `.mobileprovision`。密码用 `密码.txt` 里的那一个。
2. 导入 `TethrX-iPhone17ProMax-iOS26.6-esign.ipa`。
3. 签名。Bundle ID 填 `nsk-164.v-team.cn`。证书和描述文件选刚才导入的那一对。
4. 签名完成后再安装。

装好后打开「设置 → 隐私与安全性 → 开发者模式」，按提示重启并确认。开发描述文件需要这一步，App 才能打开。

这个包只有 iPhone 主程序。手表、主屏幕小组件和分享扩展没有打进去，因为这份描述文件只有一个 App ID。配对在 App 自己的钥匙串里完成。iOS 17 的巨魔包仍在[最新正式发布](https://github.com/zwthys-cyber/TethrX/releases/latest)，不能装到 iOS 26。
