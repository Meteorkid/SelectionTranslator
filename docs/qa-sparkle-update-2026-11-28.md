# Sparkle 更新链路验证（本地测试包 + 生产 0.4.2 迁移）

日期：2026-11-28
环境：macOS，本地 `http://127.0.0.1:8765/appcast.xml`；生产 `https://github.com/Meteorkid/SelectionTranslator/releases/latest/download/appcast.xml`
目的：验证 Sparkle 的下载、替换、重启机制；并单独验证正式 0.4.2 的迁移边界。

> 注意：本地测试里的“0.4.2 / 7”旧包是当前 Debug 构建改版本号，包含 0.4.3 的 3 秒退出保护，不是正式 0.4.2 二进制。它只能证明更新机制本身可用，不能证明正式 0.4.2 可以自动安装。

## 步骤

1. 从 Debug 构建复制两份 App：
   - 旧包保留 `0.4.2 / 7`，把 `SUFeedURL` 改为本地 feed，`SUScheduledCheckInterval=10`。
   - 新包改为 `0.4.3 / 8`，重新 ad-hoc 签名并打成 zip。
2. 用 Sparkle `generate_appcast` + 生产私钥生成带 EdDSA 签名的本地 appcast。
3. 启动旧包，等待自动检查；Sparkle 发起 `GET /appcast.xml`，显示“A new version of 划词翻译 is available”。
4. 依次点击“Install Update”与“Install and Relaunch”。
5. 验证安装结果。

## 结果

- HTTP 日志记录 `GET /appcast.xml` 与 `GET /SelectionTranslator-0.4.3.zip`，均返回 200。
- Sparkle 完成下载，并显示“Ready to Install”。
- 点击“Install and Relaunch”后，原路径 App 被替换，`CFBundleShortVersionString` 从 `0.4.2` 变为 `0.4.3`，`CFBundleVersion` 从 `7` 变为 `8`。
- 更新后的 App 被重新拉起，进程持续运行；安装窗口关闭。
- 旧包上的启动退出保护（启动 3 秒内忽略终止、之后允许退出）没有阻塞 Sparkle 的安装终止请求。

## 边界

- 本地测试使用本地 feed + ad-hoc 测试包，不覆盖正式 Release 的 Apple Development 签名和 Gatekeeper 路径。
- 本地旧包不是正式 0.4.2 二进制；正式 0.4.2 的迁移验证见下节。
- 未验证 Developer ID 公证包在 Gatekeeper 下的首次启动或跨 Team 签名替换；正式发版前仍需用真实的 Apple Development / Developer ID 包重跑一次。

## 生产 0.4.2 → 0.4.3 验证

1. 用 `ditto -x -k dist/SelectionTranslator-0.4.2.zip /tmp/prod-update-old` 解压，`codesign --verify --deep --strict` 通过。`unzip` 解压会破坏 `Sparkle.framework` 的符号链接，随后 `codesign` 报 `a sealed resource is missing or invalid`；这是解压工具问题，不是发布包损坏。
2. （appcast 改为信息型更新之前）启动正式 0.4.2，自动检查请求 GitHub 最新 `appcast.xml`（HTTP 200），显示 0.4.3 更新说明并下载 `SelectionTranslator-0.4.3.zip`（约 4.1MB）。
3. 点击“Install and Relaunch”后，窗口停在 “Ready to Install”。`osascript -e 'tell application id "com.meteor.SelectionTranslator" to quit'` 返回 `-128`，进程不退出。
4. 根因：正式 0.4.2 的 `AppDelegate.allowQuit = false`，`applicationShouldTerminate` 始终返回 `.terminateCancel`；0.4.3 才改为启动 3 秒后允许退出。启动 5 秒后对 0.4.3 执行同一 AppleEvent，进程正常退出，修复有效。
5. 在安装等待状态强制退出旧 App 后，Sparkle 继续完成替换：`CFBundleShortVersionString` 从 `0.4.2` 变为 `0.4.3`，`CFBundleVersion` 从 `7` 变为 `8`，`codesign --verify --deep --strict` 通过。强制退出路径没有自动重启 App，手动打开后进程持续运行。
6. 处置：生产 appcast 的 0.4.3 条目加入 `<sparkle:informationalUpdate><sparkle:belowVersion>8</sparkle:belowVersion></sparkle:informationalUpdate>` 和指向 Release 页的 `<link>`。构建号 `< 8` 的旧版本只看到“Learn More”，不再触发会卡住的自动安装；0.4.3/8 不受影响，后续版本可继续正常自动更新。
