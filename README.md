# SelectionTranslator · 划词翻译

一个 macOS 原生、轻量的阅读辅助 App。重点不是接更多翻译网站，而是把**选区所在的句子、段落和整篇文章**一起交给翻译引擎，让单词和句子在原文语境里解释，再用一个不抢焦点的浮窗展示结果。

当前版本：**v0.4.2**（build 7）｜macOS 14+｜arm64｜Apache-2.0｜[下载最新版](https://github.com/Meteorkid/SelectionTranslator/releases/latest)｜[更新说明](docs/release-notes-0.4.2.md)

## 0.4.2 更新摘要

这一版把阅读控制、隐私存储和外部调用边界补齐，同时保留 `0.4.1` 的许可证、自动更新和首启引导。

- **阅读控制**：五种译文风格、术语表、长文档选区窗口裁剪、从 PDF 导入上下文。
- **体验**：选中后可直接翻译，按 App bundle ID 排除取词，首启页可现场申请辅助功能/屏幕录制权限。
- **隐私**：整篇上下文与历史敏感字段均为 AES-GCM；历史数据库和上下文文件 `0600`，数据目录 `0700`；旧明文行自动迁移。
- **URL 调用方校验**：解析 Apple Event 原始 sender，校验 bundle ID 与代码签名证书；浏览器、Finder、快捷指令等允许来源之外拒绝。
- **验证**：`./scripts/build.sh` 通过；发布时 44 个 XCTest 全过；Sparkle feed 与 zip 签名均校验。UI 冒烟测试仍需要本机 UI Automation 授权。

## 界面

UI 使用一套集中定义的 macOS 视觉系统：品牌头、分组标题、状态徽章、统计块、材质浮窗，以及无边框圆角翻译面板。设置页可在 **原生（默认）** 和 **液态玻璃** 两套外观之间切换；液态玻璃用环境渐变、系统玻璃胶囊和半透明表面覆盖设置、浮窗、输入翻译、历史/生词本和提示面板。设计记录与截图见 [`docs/ui-redesign.md`](docs/ui-redesign.md) 和 [`docs/liquid-glass.md`](docs/liquid-glass.md)。

## 下载与安装

GitHub Releases：<https://github.com/Meteorkid/SelectionTranslator/releases/latest>

- `SelectionTranslator-0.4.2.zip`：可直接打开的 App，**arm64 / Apache-2.0 / Apple Development 开发签名**，尚未用 Developer ID 公证。首次打开可能被 Gatekeeper 拦截，请在 Finder 里右键“打开”，或到系统设置里允许。
- `SelectionTranslator-0.4.2-source.zip`：源码、脚本、浏览器扩展、设计文档和更新说明。
- 也可以从源码构建；步骤见下方「构建与测试」。

> 从 `0.4.0` 升级：请手动下载 `0.4.2` 覆盖安装一次；`0.4.1` 及之后的版本已包含 Sparkle，可通过自动更新检查到本版。

## 已实现

- 菜单栏 App，不占 Dock；默认快捷键可改
- 划词翻译：Accessibility 读取选区，自动带入前后文（默认 1,600 字符）
- 鼠标划词：选区结束后在鼠标附近出现“译”图标；点击或悬停 550ms 翻译，4.5 秒自动消失；鼠标松开点远离焦点元素时丢弃陈旧选区
- 剪贴板翻译：`⌥V`，不依赖辅助功能
- 输入翻译窗口：`⌥A`，可手动贴一段文章
- 截图 OCR：`⌥O`；静默 OCR：`⌥⇧S`（只把识别文字复制到剪贴板）
- OCR 版面重建：同一行的识别碎片合并；中英文续行按段落拼接，列表项/明显行距保留换行，段落间距保留空行
- OCR 低置信度重试：原图不可靠时自动做灰度/对比度/锐化增强，必要时反色；按置信度、字符数和行数选择最佳 pass
- 整篇文章上下文：设置「上下文」里可保存或从 PDF 导入当前文章，按账户隔离；AES-GCM 加密保存，划词、剪贴板、输入、浏览器入口都会带上它
- 单词快路径：macOS 系统词典 → 内置 ECDICT 5.6 万词库 → 缓存，几十毫秒，不经过模型
- 模型翻译：OpenAI-compatible 流式接口，DeepSeek / OpenAI / Ollama / LM Studio 共用一套协议
- 降级链：系统词典 → 离线词库 → 内存缓存 → 本地/在线模型 → macOS 系统翻译 → 显示原文并允许复制
- 本地账户：多账户切换、重命名、头像、删除入口；无登录、无云端
- 历史与生词本：SQLite 本地库，按账户隔离；敏感字段 AES-GCM 加密；搜索、收藏、删除、JSONL/CSV 导出
- Anki：AnkiConnect 测试、把收藏发送到牌组；也支持 CSV 手动导入
- 朗读：AVSpeechSynthesizer
- 浏览器入口：Chrome Manifest V3 扩展，选区旁出现“译”按钮，带选区 + 段落 + 整页上下文；也支持右键菜单与 `Ctrl+Shift+Y`
- 跨 App 取词硬化：Chrome/Electron 切前台时预启用 AX 树；Chromium 通过 AX text marker 补全文和上下文；只有 `AXSelectedTextMarkerRange` 的 WebKit/Chromium 选区也能取词；AX 调用有 0.20s 超时；system-wide 焦点回退校验前台 PID
- 剪贴板降级安全化：目标 PID 定向复制、等待 `changeCount`、保留/恢复剪贴板快照，文件复制不会被当成选中文字；截图工具浮层期间跳过；并发触发串行化
- Safari Web Extension：已生成并签名 `browser-extension/safari-project`，在 Safari 里启用并授予“所有网站”权限后，选区浮标 → 外部协议 → App 面板的端到端链路已走通
- Sparkle 自动更新：`appcast.xml` + EdDSA 签名，设置页与菜单都可手动检查；Sparkle 负责下载、验证与安装确认
- 自动化回归：`SelectionTranslatorTests` 共 53 个 XCTest 用例，覆盖 URL 解析、设置迁移（含外观回退）、Prompt、缓存 key、首启标记、History/CSV、OCR 版面/段落拼接/多 pass 评分、鼠标点校验、截图浮层检测、marker 范围反查
- URL Scheme：`selectiontranslator://translate?...`、`clipboard`、`input`、`ocr`、`silent-ocr`、`library`、`settings`；外部调用校验 Apple Event 来源 bundle ID 与代码签名证书并限流
- 52 种目标语言目录，系统翻译与模型可用性因语言而异
- 设置页：账户 / 翻译 / 上下文 / 快捷键 / 数据与权限，五个 Tab

## 快捷键

| 动作 | 默认 |
| --- | --- |
| 划词翻译 | `⌥D` |
| 翻译剪贴板 | `⌥V` |
| 输入翻译 | `⌥A` |
| 截图 OCR | `⌥O` |
| 静默 OCR | `⌥⇧S` |
| 历史与生词本 | `⌥L` |
| 打开设置 | `⌥,` |

快捷键至少需要一个修饰键；冲突组合会跳过并写系统日志。

## 降级链

没有 API Key、也没有本地模型时，App 仍然可用：

1. **单词**：系统词典 / 内置离线词库，几十毫秒。
2. **整句/整段**：macOS 自带 Translation 框架，不需要 Key；首次使用可能要求下载语言包。
3. **系统翻译也不可用**：面板保留原文，复制原文按钮可用。

截图 OCR 和静默 OCR 需要 macOS「屏幕录制」权限。未授权时 App 会显示一次说明并提供“打开系统设置”，不会替你反复弹系统窗。

## 更新机制

App 使用 Sparkle 2 做自动更新，feed 是 GitHub Release 的 `appcast.xml`：

```text
https://github.com/Meteorkid/SelectionTranslator/releases/latest/download/appcast.xml
```

- 设置 → 数据与权限 → 更新：点“检查更新”；菜单栏也有同名入口。
- Sparkle 负责下载、EdDSA 签名验证、解压与替换；`SUPublicEDKey` 已写入 Info.plist。
- 自动检查每天最多一次；`SUAllowsAutomaticUpdates=false`，下载/安装前仍需你确认。
- 当前 feed 以 `v0.4.2` 为基线；`0.4.1` 的 zip 已包含 Sparkle，后续版本可自动检查。

更新信息不包含翻译内容、历史或 API Key。

## 文档上下文与 Anki

- 设置 → 上下文：粘贴文章或从 PDF 导入，按账户保存；内容用 AES-GCM 加密，翻译时最多发送 6,000 字符，可在 1,000–12,000 之间调整。
- 设置 → 上下文 → Anki：安装 Anki 与 AnkiConnect 插件（代码 `2055492159`），填地址 `http://127.0.0.1:8765`，测试连接后可发送收藏。
- 历史与生词本 → 导出：JSONL 或 CSV；CSV 可直接给表格软件或 Anki 导入。

## 数据位置

```text
~/Library/Application Support/SelectionTranslator/
├── profiles.json                         # 本地账户（0600）
├── history.sqlite3                       # 历史 + 生词本（敏感字段 AES-GCM，0600）
└── document-context-<account-uuid>.enc   # 当前账户的整篇上下文（AES-GCM）
```

API Key、上下文密钥与历史密钥存在 Keychain（service `com.meteor.SelectionTranslator`，account 分别为 `apiKey`、`documentContextKey` 与 `historyEncryptionKey`）。没有云端同步，也没有账号密码。

## 构建与测试

环境：macOS 14+、Xcode 16+、XcodeGen。

```bash
brew install xcodegen
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/SelectionTranslator.app
```

`build.sh` 会重新生成工程、构建并优先使用本机 `Apple Development` 证书签名；没有证书时退回 ad-hoc。Sparkle 通过 Swift Package Manager 引入，首次构建会解析 `https://github.com/sparkle-project/Sparkle`。

测试：

```bash
xcodebuild test \
  -project SelectionTranslator.xcodeproj \
  -scheme SelectionTranslator \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData
```

当前 53 个 XCTest 用例全部通过；最后一次结果：`** TEST SUCCEEDED **`。UI 冒烟测试单独放在 `SelectionTranslatorUITests` scheme，需要先在系统里允许 XCTest 的 UI Automation 权限：

```bash
xcodebuild test \
  -project SelectionTranslator.xcodeproj \
  -scheme SelectionTranslatorUITests \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData
```

## 浏览器扩展

### Chrome / Edge

1. 打开 `chrome://extensions`，开启“开发者模式”。
2. “加载已解压的扩展程序”，选择 `browser-extension/chrome`。
3. 在网页里选中文字：选区旁会出现蓝色“译”按钮；也可以右键“用划词翻译翻译选中内容”，或按 `Ctrl+Shift+Y`。
4. Chrome 首次会询问是否允许打开 `selectiontranslator://`，允许即可把内容交给本机 App。

扩展发送 `text`、`context`、`document`、`app`、`title`、`source` 参数；App 会按当前账户的文档上下文与降级链处理。扩展清单版本与主 App 同步为 `0.4.2`。

### Safari

仓库已包含由 `xcrun safari-web-extension-converter` 生成的 Xcode 工程：

```text
browser-extension/safari-project/SelectionTranslator Safari/SelectionTranslator Safari.xcodeproj
```

构建并签名（把 `YOUR_TEAM_ID` 换成自己的 Apple Developer Team ID）：

```bash
xcodebuild \
  -project 'browser-extension/safari-project/SelectionTranslator Safari/SelectionTranslator Safari.xcodeproj' \
  -scheme 'SelectionTranslator Safari' \
  -destination 'platform=macOS' \
  -derivedDataPath build/SafariDerivedData \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

第一次启用：

1. 打开生成的 `SelectionTranslator Safari.app`，让它启动一次。
2. 打开 Safari → 设置 → 扩展，勾选 `SelectionTranslator for Safari`。
3. 在同一页点“在每个网站上始终允许…”并在系统确认框里允许；否则 content script 不会注入网页。
4. 刷新网页，选中文字后会出现“译”浮标；点击后会弹一次 `selectiontranslator://` 的外部协议确认，选择“允许”。

已完成的验收：Safari 页选区浮标出现 → 点击浮标 → 系统协议确认 → App 面板显示中英结果，且上下文与整页文档字段有值。

如果只需要在当前 Mac 上使用，App 的 `⌥D` 划词快捷键不依赖浏览器扩展，也可以工作。

## 隐私与许可

- 隐私说明：[`PRIVACY.md`](PRIVACY.md)；App 内“设置 → 隐私与引导”和首启页都有入口。
- 许可证：Apache License 2.0，全文见 [`LICENSE`](LICENSE)。
- 第三方组件：Sparkle（MIT）、ECDICT（MIT），详见 `Support/Resources/NOTICE.md`。
- 默认不接入分析 SDK、崩溃上报或云端账户；只有主动翻译、打开 AnkiConnect、检查更新时才会联网。

## 已知边界

- 52 种语言只是目录；实际能否翻译取决于系统语言包或模型能力。
- 系统词典使用 macOS `DCSCopyTextDefinition`，不同系统版本的词条质量不同。
- 浏览器扩展通过外部 URL Scheme 拉起 App，首次需要用户在浏览器里允许；没有内置本地 HTTP server。
- Chrome 扩展已在干净测试 profile 完成“安装 → 浮标 → 点击 → 拉起 App”的端到端验收；Safari 已在 `safari-project` 构建、签名并完成“启用 → 浮标 → 拉起 App”的端到端验收。日常浏览器仍需手动加载/启用一次。
- 截图 OCR / 静默 OCR 需要屏幕录制权限；本机已授权并完成一次交互式框选 OCR，但 OCR 对选区质量敏感，识别率不等于完美。未授权时 App 只提示一次，不反复弹系统窗。
- 当前只有 `Apple Development` 证书，无法完成 Developer ID 公证；`scripts/notarize.sh` 已准备好嵌套 Sparkle 组件的签名流程，但不会伪造“已公证”结果。
- 不接 MDict、20+ 翻译服务、WebDAV、插件系统、多引擎并排；这些属于大型产品取舍，不是轻量 MVP 的优先项。

更细的版本记录见 [`CHANGELOG.md`](CHANGELOG.md)、[`docs/release-notes-0.4.2.md`](docs/release-notes-0.4.2.md)、[`docs/v0.4.0-status.md`](docs/v0.4.0-status.md) 和 [`docs/easydict-review.md`](docs/easydict-review.md)。
