# Sparkle 更新链路验证（本地 0.4.2 → 0.4.3 测试包）

日期：2026-11-28
环境：macOS，本地 `http://127.0.0.1:8765/appcast.xml`
目的：验证 0.4.2 发布后新增的退出保护没有阻塞 Sparkle 的下载、替换与重启动。

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

- 这是本地测试 feed + ad-hoc 测试包，不是正式 Release；生产 `appcast.xml` 仍指向 0.4.2。
- 未验证 Developer ID 公证包在 Gatekeeper 下的首次启动或跨 Team 签名替换；正式发版前仍需用真实的 Apple Development / Developer ID 包重跑一次。
