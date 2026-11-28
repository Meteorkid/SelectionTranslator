# Changelog

## 未发布 — 持续加固

0.4.2 发布后的可靠性、隐私与账户隔离修复，尚未发布新版本：

- 允许正常退出 App（菜单、系统注销、Sparkle 安装），仅在 XCTest 宿主中阻止测试期间的退出事件。
- 账户切换时先保存旧账户的文档上下文，避免防抖写入被取消而丢字；历史页的收藏/删除回调不再用旧账户数据覆盖新账户。
- OCR 截图进程的启动与取消改为原子操作，取消不再可能遗留交互截图浮层；清空文档上下文增加确认，且锁定账户时明确警告原文件会被永久删除。
- 浏览器扩展的页面选区会映射回 Chrome/Edge/Safari 的 bundle ID，按 App 排除终于对扩展入口生效。
- 系统翻译降级结果不再写入模型缓存；语境解释写入历史失败会在面板可见；菜单栏快捷键文案与权限状态实时刷新。
- 术语表限制为 64 条并拒绝重复原文；新增浏览器 bundle 映射测试，当前 53 个 XCTest 全部通过。
- 修正私网判定：`127.0.0.1.example.com`、`10.example.com` 这类域名不再被误当成回环/内网 IP；只有真正的私有 IPv4 字面量才允许 HTTP，防止 API Key 被明文发往公网。

## 0.4.2 — 2026-11-27

阅读控制、隐私存储与 URL 调用边界；版本 `0.4.2 / build 7`。

### 翻译与阅读

- 新增译文风格：自然、忠实、学术、技术、简洁；风格指令进入 system prompt，并纳入缓存键。
- 新增术语表：原文术语与指定译法成对保存，只对有效条目生成 `<glossary>` 块；术语表变化会使缓存失效。
- 长文档上下文不再盲目截头：优先保留选区首次出现位置附近的窗口，按行边界收尾；找不到选区时回退到开头。
- 设置页新增「翻译风格」「术语表」「选中后立即翻译」「按 App 排除」，上下文页新增「从 PDF 导入」（PDFKit 提取，扫描件提示改用 OCR）。

### 体验

- 鼠标划词可选跳过浮标、直接翻译；默认关闭，避免默认产生模型调用。
- 可按 App 的 bundle ID 排除取词；排除后不显示浮标，快捷键会明确提示。
- 首次引导新增辅助功能/屏幕录制授权卡，可现场请求屏幕录制并刷新状态；不授权仍可用剪贴板、输入翻译和浏览器扩展。

### 工程与隐私

- 文档上下文改为 AES-GCM 加密文件，密钥在 Keychain；首次读取旧明文 `.txt` 自动迁移并删除旧文件；写入后 0600。
- 历史 SQLite 改为字段级 AES-GCM：原文、译文、上下文、App 名与 bundle ID 加密，账户、时间、语言等查询字段保持明文；旧明文行与半迁移行首次读取时原地修复；`char_count` 自动回填；文件权限 0600；历史搜索改为解密后内存过滤。
- `Application Support/SelectionTranslator` 目录收紧为 0700，`profiles.json` 写入后设为 0600；避免账户名等旁路数据被同机其他用户读取。
- URL Scheme 外部调用增加 20,000 字符上限与每分钟 60 次限流；通过 Apple Event 原始地址解析调用方 bundle ID，并校验其代码签名证书；只接受 Safari/Chrome/Edge/Firefox、Finder、快捷指令与自动化调用，无法验证来源时拒绝。
- 新增 `AdvancedFeatureTests`（设置迁移、提示词、长文裁剪、URL 限流、加密迁移）与 `HistoryStoreTests` 加密/迁移用例；测试密钥可注入，避免 Keychain 弹窗拖慢 CI。
- 新增 `SelectionTranslatorUITests` 冒烟测试 target 与独立 scheme（首启授权卡、设置页翻译/上下文控件）；默认 XCTest 仍只跑单元测试，UI 测试需系统 UI Automation 权限。
- 新增 GitHub Actions `CI`：XcodeGen 生成、Debug 构建、单元 XCTest。

### 发布

- 版本提升到 `0.4.2 / build 7`；Chrome、Safari 扩展 manifest 同步为 `0.4.2`。
- 44 个 XCTest 全部通过；新增半迁移、URL 签名策略测试。
- `SelectionTranslatorUITests` 独立 scheme 已加入，但运行仍依赖本机 UI Automation 授权，未计入本次发布验收。

## 0.4.1 — 2026-11-27

这一版把 `0.4.0` 之后的取词/OCR 硬化收进正式包，并补齐许可证、Sparkle 自动更新、隐私说明和首启引导。

### 许可证与发布

- 许可证改为 Apache License 2.0，新增 `LICENSE`；`NOTICE` 补项目与 Sparkle/ECDICT 第三方声明。
- `LICENSE`、`PRIVACY.md`、`NOTICE.md` 随 App 打包到 `Contents/Resources`，源码包同步包含。
- 版本提升到 `0.4.1 / build 6`；浏览器扩展 manifest 同步到 `0.4.1`。
- `scripts/build.sh` 指定 SPM checkout 路径并使用 deep codesign；`scripts/notarize.sh` 增加 Sparkle 嵌套组件重签顺序。

### Sparkle 自动更新

- 更新检查从轻量 JSON 切换为 Sparkle 2：SPM 引入 `Sparkle`，target 依赖 `package: Sparkle`。
- `Info.plist` 写入 `SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks=true`、`SUScheduledCheckInterval=86400`、`SUAllowsAutomaticUpdates=false`。
- 新增 `SparkleUpdater`：`SPUStandardUpdaterController` 管理更新，支持 gentle scheduled reminders；设置页和菜单栏都可手动检查。
- 删除旧 `UpdateChecker`、`updateFeedURL`、`checkForUpdatesOnLaunch` 与其测试；不再保留 JSON fallback。
- 新增已签名的 `appcast.xml` 与 `scripts/appcast.sh`：生成条目、逐条注入 EdDSA 签名、签名 feed 并校验。
- 私钥只保存在本机 `~/Library/Application Support/SelectionTranslator/Sparkle/ed25519.key`（0600），不进入仓库。

### 隐私与首次启动

- 新增 `PRIVACY.md`：本机 SQLite/JSON/上下文文件、UserDefaults、Keychain 的用途；主动翻译、系统翻译、AnkiConnect、Sparkle 检查四类联网时机；剪贴板/截图/权限边界。
- 首启页新增三张卡：**不会误取、不会丢上下文、不会打断截图**；底部有隐私说明和「开始使用」。
- 新增 `OnboardingState`，以 `SelectionTranslator.onboardingCompleted.v1` 记录；已有设置的老用户自动跳过，不打断升级；设置页可「重新查看首次引导」。
- 设置页「数据与权限」新增「更新」「隐私与引导」区块。

### 取词可靠性

- Chrome/Electron 切前台时预启用 AX 树；Chromium 原生取词补上 AX text marker 上下文。
- AX 调用增加 0.20s 超时；Chromium 聚焦元素 bounded fallback；安全输入与密码字段 fail closed。
- system-wide 焦点回退校验前台 PID；鼠标划词增加焦点元素 bounds + 20pt 容差校验。
- 剪贴板降级改为目标 PID + `changeCount` + 快照恢复；文件复制不当作选中文字；截图工具浮层期间跳过；并发触发串行化。
- 取词增加 `AXSelectedTextMarkerRange` 兜底；无普通 selected range 时用选中文本反查全文范围恢复上下文。

### OCR 与上下文

- OCR 增加语言自动检测、同行碎片合并和段落间距重建。
- OCR 低置信度多 pass：灰度/对比度/锐化增强、深色反色兜底、按置信度/字符数/行数评分。
- OCR 段落拼接：英文/中文续行合并，列表项和明显行距保留换行，段落间距保留空行。
- 整篇文章上下文按账户保存，划词、剪贴板、输入和浏览器入口都会带上。

### 测试与文档

- XCTest 共 **33 个，0 failures**；覆盖 URL 解析、设置迁移、Prompt、缓存 key、首启标记、History/CSV、OCR 版面/段落/多 pass、鼠标点校验、截图浮层检测、marker 范围反查。
- 新增 `docs/release-notes-0.4.1.md`，README 重写版本、下载、更新、隐私与已知边界。
- 细节见 `docs/open-source-capture-ocr-review.md`。

## 0.4.0 — 2026-11-26

- 新增可切换的「液态玻璃」主题；原生主题仍是默认，旧设置自动回退原生。
- 覆盖设置五个 tab、翻译浮窗、输入翻译、历史/生词本、错误与权限提示。
- macOS 26 浮窗使用系统 `glassEffect`；旧系统使用半透明材质和高光描边的 fallback。
- 新增外观持久化、迁移回退和 round-trip 测试；XCTest 共 13 个。
- 浏览器扩展版本同步到 0.4.0。
- 更新 UI 设计记录、液态玻璃设计记录、README 和设置页截图。

## 0.3.1 — 2026-11-26

- Chrome/Safari 浏览器扩展、URL Scheme、悬浮取词、轻量更新检查。
- 屏幕录制授权入口、交互式 OCR、CSV/History 回归、Safari Web Extension。
- 完成 macOS 原生视觉重做与 12 个 XCTest。

## 0.3.0

- 上下文优先翻译链、离线词典、历史与生词本、多账户、Anki 导出和本地模型接入。
