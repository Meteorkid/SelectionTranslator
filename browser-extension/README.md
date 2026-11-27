# 浏览器划词桥

浏览器扩展不直接翻译，也不保存 API Key。它只负责：

1. 在你点击“译”、使用右键菜单或按扩展快捷键时，读取选区、周边段落，以及最多 6,000 字符的当前页面文本；
2. 打开 `selectiontranslator://translate?...`；
3. 由本机 App 用上下文优先的翻译链处理；扩展自身不保存 API Key，也不直接上传内容。

## Chrome / Edge

1. 先安装并运行 `SelectionTranslator.app`。
2. 打开 `chrome://extensions`，开启「开发者模式」。
3. 点「加载已解压的扩展程序」，选择本目录下的 `chrome/`。
4. 在网页中选中文字，会出现蓝色「译」按钮；点击即可打开本机 App。
   也可以右键选择「用划词翻译翻译选中内容」，或按 `Ctrl+Shift+Y`。
5. 第一次打开自定义 URL 时，Chrome 可能询问是否允许打开 SelectionTranslator，选择允许。

## Safari

Safari 的 Web Extension 必须由 Xcode 包装并签名，不能直接加载一个普通文件夹。
仓库已包含转换后的工程：

```text
safari-project/SelectionTranslator Safari/SelectionTranslator Safari.xcodeproj
```

构建：

```bash
xcodebuild \
  -project 'safari-project/SelectionTranslator Safari/SelectionTranslator Safari.xcodeproj' \
  -scheme 'SelectionTranslator Safari' \
  -destination 'platform=macOS' \
  -derivedDataPath build/SafariDerivedData \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

打开生成的 `SelectionTranslator Safari.app`，在 Safari → 设置 → 扩展中勾选
`SelectionTranslator for Safari`，并在同一页点“在每个网站上始终允许…”（否则
content script 不会注入页面）。刷新网页后选中文字即可看到“译”浮标。首次点击会
询问是否允许打开 `selectiontranslator://`，选择允许即可。

已验收：Safari 选区浮标 → 点击 → 外部协议确认 → App 面板显示结果。

## 限制

- URL 长度有限：选区最多 8,000 字符，周边段落最多 1,800 字符，页面文本最多 6,000 字符；长文请用 App 内输入翻译窗口。
- 自定义 URL 的首次打开可能被浏览器安全提示拦截，这是浏览器行为，不是 App 错误。
- 扩展不读取剪贴板，也不上传内容。
