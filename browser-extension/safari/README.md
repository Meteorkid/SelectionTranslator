# Safari 扩展

`content.js` / `content.css` 与 Chrome 版共享交互，`background.js` 负责打开
`selectiontranslator://`。Safari 必须由 Xcode 的 Safari Web Extension target 包装。

本仓库已生成工程：`../safari-project/SelectionTranslator Safari/SelectionTranslator Safari.xcodeproj`。

构建与启用：

1. 用 `xcodebuild` 构建 `SelectionTranslator Safari` scheme；开发签名请把自己的 Team ID 填到 `DEVELOPMENT_TEAM`。
2. 打开生成 App，让 Safari 发现扩展。
3. Safari → 设置 → 扩展：勾选 `SelectionTranslator for Safari`，再点“在每个网站上始终允许…”并确认。
4. 刷新页面；选中文字出现“译”浮标。首次点击会弹 `selectiontranslator://` 外部协议确认。

已验收通过；若复选框无法勾选，优先检查扩展是否已由 `pluginkit` 注册、是否授予了所有网站权限。
