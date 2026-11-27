# 隐私说明

生效日期：2026-11-27

SelectionTranslator（显示名「划词翻译」）是一个本地优先的 macOS 菜单栏工具。它没有自有云端账户系统，也不会把历史记录、生词本或设置上传到本项目自己的服务器。

## 本机保存的数据

以下数据默认只保存在这台 Mac 上：

- `~/Library/Application Support/SelectionTranslator/history.sqlite3`：翻译历史、生词本、账户标识；敏感文本字段用 AES-GCM 加密，文件权限 `0600`。
- `~/Library/Application Support/SelectionTranslator/profiles.json`：本地账户名称与头像标识。
- `~/Library/Application Support/SelectionTranslator/document-context-<account-uuid>.enc`：你主动粘贴或从 PDF 导入的整篇文章上下文；AES-GCM 加密保存，文件权限 `0600`。
- `~/Library/Preferences/SelectionTranslator.settings`：外观、快捷键、模型地址、上下文长度等设置。
- Keychain（service `com.meteor.SelectionTranslator`）：`apiKey` 保存你填写的模型 API Key；`documentContextKey` 保存上下文加密密钥；`historyEncryptionKey` 保存历史字段加密密钥（均为 256 位，只在本机）。

卸载 App 不会自动删除上述数据。你可以手动删除 `Application Support/SelectionTranslator` 目录，并在「钥匙串访问」里删除 service `com.meteor.SelectionTranslator` 下的 `apiKey`、`documentContextKey` 与 `historyEncryptionKey`。

## 什么时候会联网

只有在以下情况才会发起网络请求：

1. **你主动触发翻译**：选中的文字、必要的上下文、目标语言和模型参数会发送到你配置的模型服务（例如 DeepSeek、OpenAI 兼容服务、Ollama/LM Studio 的本机地址）。请求由该服务商按其隐私政策处理。
2. **你使用 Apple 系统翻译/系统词典**：请求由 macOS 的 Translation / Dictionary 框架处理，是否联网取决于系统语言包与 Apple 的实现。
3. **你使用 AnkiConnect**：只连接你填写的本机或局域网 Anki 地址，用于发送生词卡片。
4. **Sparkle 检查更新**：App 会向 `https://github.com/Meteorkid/SelectionTranslator/releases/latest/download/appcast.xml` 请求版本信息；下载更新前会用 EdDSA 公钥验证签名。该请求不包含翻译内容、历史或 API Key。

默认不包含分析 SDK、崩溃上报、广告 SDK，也不做使用行为埋点。

## 剪贴板与屏幕内容

- **剪贴板翻译**只在你按下快捷键或点击菜单时读取剪贴板。
- **取词降级**在必要时会向目标 App 发送一次合成 `⌘C`，读取当前选区后恢复原剪贴板内容。该操作只在本次取词期间发生。
- **截图 OCR** 只处理你框选的区域；OCR 在设备端通过 Apple Vision 完成，不上传截图。
- **整篇文章上下文**只有在你主动开启、粘贴或从 PDF 导入内容后才会参与翻译；它不会自动抓取整个屏幕或整个网页。上下文和历史只在本机解密，发送给模型服务的只有翻译所需的选区与相关片段。

## 权限

- **辅助功能**：用于读取其他 App 的 AX 选中文字与焦点窗口；不用于记录键盘输入。
- **屏幕录制**：只用于截图 OCR；不持续录屏，不保存截图。
- **安全输入**：检测到密码框或安全输入时，取词会直接跳过，不读取内容。

## 第三方组件

- **Sparkle**（MIT）：检查与安装更新，使用 EdDSA 签名验证。
- **ECDICT**（MIT）：内置英汉词典摘录，见 `Support/Resources/NOTICE.md`。
- **Apple frameworks**：Vision、Translation、Dictionary、Speech 等，按 macOS 系统能力运行。

## 联系

隐私问题请通过 GitHub Issues 联系：

https://github.com/Meteorkid/SelectionTranslator/issues

本项目采用 Apache License 2.0；该许可证不改变本说明中的数据处理承诺。
