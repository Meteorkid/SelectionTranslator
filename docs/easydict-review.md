# Easydict 代码评审与本项目功能对照

日期：2026-11-26  
参考源码：`/tmp/Easydict-src/Easydict-main`（Easydict main，434 个 Swift 文件，约 65,129 行 Swift，59 个测试文件）  
本项目：SelectionTranslator v0.3.1（40 个 Swift 源文件，约 5,438 行；12 个 XCTest 用例）

## 一句话结论

Easydict 是一个成熟、分层清楚、测试覆盖不错的 macOS 翻译工程，值得学习它的**服务抽象、事件监听和 OCR 细节**；但它同时也是 ObjC + Swift 混编、Pods 依赖、20+ 翻译服务、65k+ 行的重工程，不适合作为一个轻量 MVP 的直接模板。

本项目选择“参考架构，不复制代码”。Easydict 使用 GPL-3.0，直接搬代码会把项目拖进 GPL 约束；下面的对照只讨论实现思路，没有复制其源码。

## Easydict 写得好的地方

- **服务层抽象清楚**：`QueryService` 协议 + `QueryServiceFactory` + `QueryResult` / `QueryModel`，把“某个翻译服务”和“查询结果展示”解耦。新增服务时不需要改 UI。
- **事件监听细**：`EventMonitor` 和 `SelectionWorkflow` 对划词、快捷键、鼠标事件的处理比较完整，考虑了不少边缘情况。
- **OCR 做得细**：`AppleOCREngine` 不只是调一次 Vision，还处理了识别语言、结果合并和版面顺序。
- **测试不是摆设**：59 个测试文件，服务层、OCR、工具函数都有覆盖；这在同类开源 Mac App 里不常见。
- **功能广度完整**：多服务、词典、生词本、AnkiConnect、浏览器取词、菜单栏、偏好设置、自动更新等产品化能力都具备。

## Easydict 不适合照搬的地方

- **体量偏重**：65k+ 行 Swift，另有 ObjC、Pods、Masonry/ReactiveObjC；为了一个划词翻译，学习和维护成本很高。
- **服务配置复杂**：20+ 服务各自有 Key、语言、请求参数和结果模型，设置界面和查询链路会迅速膨胀。
- **上下文不是产品中心**：Easydict 更像“多词典/多翻译源聚合器”；对“结合整句/整段语境解释”的表达不是核心卖点。
- **窗口/设置层级多**：多窗口、菜单栏、浮动窗口、偏好设置互相耦合，轻量项目很容易被这套结构拖慢。
- **GPL-3.0**：如果目标是做一个可自由分发、以后可能商业化的 App，不能直接复制其源码。

## 本项目 v0.2 的重构选择

1. **保留一条主链路**：`TranslationPipeline` 统一决定走离线词库、缓存、模型、系统翻译还是不可用提示；ViewModel 不再自己判断引擎。
2. **只做 OpenAI-compatible**：DeepSeek / OpenAI / Ollama / LM Studio 共用一套协议，不为每个服务写一个 Adapter。
3. **上下文显式建模**：`CaptureResult.context` 参与请求和缓存 key；面板可展开查看上下文。
4. **本地优先**：ECDICT 离线词库 + 内存缓存 + 本地 Ollama + macOS 系统翻译；没有云端账号。
5. **轻量数据层**：SQLite 单表 `queries`，按 `account_id` 隔离；不引入 ORM、不引入云同步。
6. **可迁移设置**：`AppSettings` 自定义 Codable，旧 JSON 缺字段时补默认值；避免新增设置导致旧配置读不出来。
7. **事件与 UI 解耦**：`HotKeyManager` 只负责注册/分发，`AppState` 负责窗口编排，`TranslationViewModel` 负责翻译状态。
8. **失败必须可见且可操作**：模型失败继续系统翻译；再失败保留原文和复制按钮。

## 功能对照

说明：Easydict 的“有”按仓库结构和已知能力标注；“部分”表示有基础实现但未逐项验收；本项目“未做”表示当前 v0.2 没有实现。

| 能力 | Easydict | 本项目 v0.2 | 备注 |
| --- | --- | --- | --- |
| 划词取词 | 有 | 有 | 本项目用 Accessibility + 前后文 |
| 选区上下文 | 非核心 | 有，默认 1,600 字符；另有整篇文档上下文 | 本项目差异化重点 |
| 单词离线词典 | 部分 | 有，系统词典 + ECDICT 5.6 万条 | 几十毫秒快路径 |
| 单词按上下文二次解释 | 非核心 | 有（可选按钮） | 词库先出释义，再按需调用模型 |
| 模型翻译 | 有，多服务 | 有，OpenAI-compatible | 只保留一套协议 |
| 多引擎并排对比 | 有 | 未做 | 不是轻量 MVP 的优先项 |
| 系统翻译兜底 | 部分 | 有，macOS 15+ | 语言包缺失时保留原文并提示 |
| 剪贴板翻译 | 有 | 有，`⌥V` | 不需要辅助功能 |
| 输入翻译窗口 | 有 | 有，`⌥A` | 适合贴整段文章 |
| 截图 OCR | 有 | 有，`⌥O` | Vision 离线识别 |
| 历史记录 | 部分 | 有，SQLite | 本项目按账户隔离 |
| 生词本/收藏 | 有 | 有 | 星标即收藏 |
| 本地多账户 | 未做 | 有 | 无登录、无云端 |
| 朗读 | 有 | 有 | AVSpeechSynthesizer |
| 可配置全局快捷键 | 有 | 有，6 个动作 | 设置页可改 |
| 服务预设/连接测试 | 有 | 有 | Ollama 自动识别 |
| 浏览器专项取词 | 有 | Chrome + Safari Web Extension | 两端均已走通选区浮标 → App；Safari 需授予所有网站权限 |
| 悬浮图标/双击取词 | 有 | 有 | 鼠标划词后出现“译”，悬停/点击翻译 |
| PDF 阅读器 | 未做/部分 | 未做 | Preview 选区可走 AX；扫描件走 OCR |
| Anki / WebDAV | 有 | AnkiConnect + CSV；WebDAV 未做 | 已用 mock AnkiConnect 验证 |
| 插件系统 | 部分 | 未做 | 轻量项目暂不需要 |
| 自动更新/公证 | 有 | 轻量 JSON 检查已做；完整更新器与公证未做 | 本机只有 Apple Development，无法公证；没有 Sparkle |

## v0.3.1 变化

- 新增 `AppleDictionaryService`（`DCSCopyTextDefinition`），系统词典优先于离线词库。
- 目标语言目录扩到 52 种；实际可用性取决于系统语言包/模型。
- 新增静默 OCR、URL Scheme、Chrome Manifest V3 扩展、鼠标悬浮“译”图标。
- 新增 Safari Web Extension Xcode target：已构建、签名、注册，并在 Safari 内完成端到端验收。
- 新增整篇文档上下文：每账户独立文件，PromptBuilder 增加 `<document>` 块，缓存 key 含账户与文档。
- 新增 AnkiConnect 测试与收藏导出，历史导出增加 CSV。
- OCR 增加屏幕录制权限预检和子进程取消，避免 `screencapture -i` 挂起。
- 新增 `AppURLParser` 与 `UpdateChecker`；URL 解析支持 `+`/`%2B`，更新检查只读轻量 JSON，不自动安装。
- 新增 `SelectionTranslatorTests`：12 个 XCTest 用例全部通过，覆盖 URL、设置迁移、Prompt、缓存 key、更新比较、History/CSV。
- 交互式 OCR 已在本机获屏幕录制授权后完成一次框选验收；剪贴板图片 OCR 仍是最稳的 OCR 入口。
- 版本升到 0.3.1 / build 4；源码约 5.4k 行、40 个 Swift 文件，仍无第三方运行时依赖。

## 优势与短板

先说明：以下“优势/短板”是相对 Easydict 的产品取舍，不是代码质量评分。

### 我们的优势

- **上下文优先**：同样一段选词，模型拿到的是选区 + 前后文；单词也可以先查词库，再按需让模型结合上下文解释。
- **更轻**：约 4,000 行，单工程，编译和改动都快；没有 ObjC/Pods 负担。
- **本地优先**：离线词库、系统翻译、本地 Ollama 形成完整降级链；不配 Key 也能用。
- **账户和历史是自己的**：SQLite + JSON 本地文件，数据可控，不依赖云服务。
- **产品边界清楚**：不追 20+ 翻译接口，先把“划词 → 上下文 → 结果 → 收藏”做顺。

### 我们的短板

- **功能广度仍不如 Easydict**：没有 20+ 服务、MDict、WebDAV、插件系统、多引擎并排；浏览器已覆盖 Chrome 与 Safari，但两端都依赖外部协议提示。
- **测试覆盖仍偏少**：已有 12 个 XCTest 用例，但远少于 Easydict 的 59 个测试文件；浏览器、OCR、Anki 主要靠手工验收。
- **OCR 质量受选区影响**：屏幕录制权限已授权，`screencapture -i` 框选链路已通过；但选区边缘会截断文字，识别结果不一定完整，剪贴板图片 OCR 仍更稳。
- **发布工程未完成**：未公证、未接 Sparkle；有 `scripts/notarize.sh` 和 `scripts/package.sh`，但本机没有 Developer ID。
- **更新器只是检查**：`UpdateChecker` 能提示新版本并打开下载页，但不会下载、安装或回滚。

## 建议优先级

### 当前状态

- **P1**：系统词典、离线词库、模型、系统翻译降级链已走通；OCR 权限闸门、子进程取消和真实 `screencapture -i` 框选均已验证。
- **P2**：文档级上下文与 Anki/CSV 已实现；文档用 mock 模型验证进入 prompt，Anki 用 mock AnkiConnect 验证 deckNames/addNotes。
- **P3**：Chrome 扩展、Safari 扩展、URL Scheme、悬浮“译”图标、轻量更新检查均已实现；Developer ID 公证仍未完成，详见 `docs/v0.3.1-status.md`。

## 结论

Easydict 的代码质量在“成熟开源 Mac App”这个标准下是好的，尤其是服务抽象、事件监听、OCR 和测试；但它不是“轻量划词翻译”的最佳复制对象。我们现在的方向是对的：保留它的分层思想，砍掉多服务与重依赖，把上下文、本地降级、账户和历史做成自己的主线。

下一步不应盲目补“更多翻译网站”。当前优先项是：Developer ID 公证、正式更新器与下载页、静默 OCR/真实 Anki 的回归，以及服务抽象后再加第二个翻译服务。
