# SelectionTranslator 0.4.3

发布日期：2026-11-28  
版本：0.4.3 / build 8  
系统要求：macOS 14.0+，arm64  
许可证：Apache License 2.0

## 本版重点：0.4.2 之后的可靠性、隐私与阅读加固

`0.4.3` 不改变划词、剪贴板和输入翻译的基本交互，集中收进 `0.4.2` 发布后留在 `main` 上的 79 个修复与验证提交。重点是把“已经能用”推到“边界上也可信”：

1. 退出、OCR 子进程、损坏数据库和损坏设置不再留下半完成状态；
2. 外部 URL、私网 HTTP、Keychain 与账户切换的边界继续收紧；
3. 双栏 OCR、长文上下文、词典查询和导出路径补上真实场景下的可靠性。

## 详细更新内容

### 1. 启动、退出与后台任务

- 修正 Carbon 快捷键修饰位：Control 使用 `controlKey`，不再把 `alphaLock` 当成 Control。
- 设置页提前显示快捷键冲突/缺少修饰键提示，避免注册失败后才发现。
- AppKit 在 SwiftUI `MenuBarExtra` 初始化期间可能请求退出；启动后 3 秒内忽略该请求，之后允许菜单、系统注销和 Sparkle 安装正常终止。XCTest 宿主仍阻止退出。
- `applicationWillTerminate` 取消活动 OCR 截图；退出后不再残留 `screencapture` 交互浮层或临时截图。
- OCR 截图进程改为锁内原子启动，取消不会落在 install/run 之间；临时目录改为 `0700` 私有目录。

### 2. 历史数据库与导出

- SQLite 损坏时，先把原库及 `-wal`/`-shm` 备份为 `history.corrupt-yyyyMMdd-HHmmss-<uuid>.sqlite3`（`0600`），再重建空库；设置页和历史页都会显示备份路径。
- 修复恢复后继续使用旧 SQLite handle 导致的 `SQLITE_MISUSE` / `no such table: queries`。
- 历史记录查询的 limit 改为可选；导出不再被 300 条截断，使用 SQLite `LIMIT -1` 读取完整历史。
- JSONL/CSV 导出改为逐条流式解密、写入临时文件后原子替换；固定 `0600`，失败保留旧文件。
- JSONL 保存面板使用真正的 `.jsonl` 类型，避免被追加 `.json` 后缀。
- 损坏的 `profiles.json` / 设置文件先备份为带时间戳的 `.invalid-*` 文件，再恢复默认，避免直接丢弃原始字节。

### 3. 隐私与账户隔离

- 外部 `selectiontranslator://` 调用方 requirement 按 bundle ID 固定：Apple App 使用 `anchor apple and identifier`，Chrome/Edge/Firefox 使用团队 OU + identifier；Finder 实机调起验证通过。
- 私网 HTTP 只接受真正的私有 IPv4 字面量，`127.0.0.1.example.com`、`10.example.com` 这类域名不再被误判为内网，防止 API Key 被明文发往公网。
- 账户切换前同步写入旧账户文档上下文；旧账户的历史收藏/删除迟到回调不再覆盖新账户列表。
- 账户切换隐藏旧翻译面板和划词图标，避免旧记录被新账户收藏。
- 文档上下文不可解密时禁用编辑、PDF 导入、剪贴板填入和保存，避免静默覆盖原文件；清空操作增加确认和永久删除警告。
- 剪贴板/OCR 敏感 App 黑名单、OCR 临时文件私有化、外部页面上下文隐私披露继续生效。
- API Key 改为按需读取：词典和缓存命中不再预读 Keychain，只有真正走模型或点击“语境解释”时才读取。

### 4. 阅读与翻译体验

- OCR 版面支持文章式双栏：识别全宽标题/页脚/分节标题后，按左栏、右栏阅读顺序输出；单栏和表格仍走原布局。
- 未解锁 PDF 导入返回明确 `.locked` 错误；取词前台 PID 等于自身时拒绝，避免翻译 App 自己的窗口。
- 选区上下文有 8,000 字符上界，`ContextExtractor` fallback 和 `AppState.translate` 双重裁剪。
- 术语表限制 64 条并拒绝重复原文；Prompt 的上下文/文档/选区 delimiter 中和，降低注入风险。
- 系统词典/离线词库查询移出主线程；离线词库启动后台预加载并加锁，冷启动首次查词不再同步解析整份 TSV。
- 系统翻译重试重建 `TranslationSession.Configuration`，避免复用旧请求；系统翻译降级结果不写入模型缓存。
- Anki Front/Back 转义 HTML，换行转 `<br>`；Anki 导出分批，避免大历史一次压入内存。
- 菜单栏快捷键文案和辅助功能/屏幕录制权限状态实时刷新。

## 验证

- `xcodebuild test`：**59 tests, 0 failures**，`TEST SUCCEEDED`。
- `xcodebuild analyze`：`ANALYZE SUCCEEDED`。
- Finder 调起 `selectiontranslator://` 实机验证：签名校验通过，翻译面板正常显示。
- 本地 0.4.2 → 0.4.3 测试包完整验证 Sparkle：自动检查、EdDSA 校验、下载、替换 App、重启动；启动退出保护没有阻塞安装终止请求。记录见 `docs/qa-sparkle-update-2026-11-28.md`。（该测试旧包是当前 Debug 构建改版本号，不是正式 0.4.2 二进制。）
- 生产正式 0.4.2：feed 能显示 0.4.3 并下载，但旧版 `allowQuit=false` 会拒绝 Sparkle 的终止请求，安装停在 “Ready to Install”；强制退出旧 App 后替换完成，版本 0.4.3/8，`codesign --verify --deep --strict` 通过。因此本版对旧版本改为信息型更新，避免用户卡在自动安装。

## 未纳入本次验收

- `SelectionTranslatorUITests` 仍被 macOS UI Automation 权限弹窗阻塞，本次发布不声称 UI 自动化已通过。
- 发布包仍为 Apple Development 签名，未使用 Developer ID 公证。首次打开可能被 Gatekeeper 拦截，请在 Finder 里右键“打开”，或到系统设置里允许。
- OCR 双栏只覆盖文章式垂直 gutter + 全宽标题/页脚/分节标题；复杂表格、三栏、跨栏图注尚未验证。

## 升级说明

### 从 0.4.2 及更早版本升级

- `0.4.2` 及更早版本的退出保护会拒绝 Sparkle 的自动安装终止请求。本版对构建号低于 `8` 的旧版本只展示“Learn More”，不再触发可能停在“Ready to Install”的自动安装；请从本 Release 页面下载 `SelectionTranslator-0.4.3.zip`，退出旧 App 后覆盖安装。
- 如果你已经在旧版点了“Install and Relaunch”并停在“Ready to Install”：在活动监视器里强制退出 `SelectionTranslator`，Sparkle 会继续完成替换；或直接手动下载覆盖。
- `0.4.0` 也必须手动下载 `0.4.3` 覆盖安装一次。

### 后续自动更新

- `0.4.3` 已修正退出保护：启动 3 秒后允许 Sparkle、菜单和系统注销正常终止。后续版本可以从 `0.4.3` 继续走自动更新。
- 首次读取由旧版本创建的加密历史/keychain 项时，系统可能要求一次钥匙串授权；允许后同一签名不再反复弹窗。

## 资产

- `SelectionTranslator-0.4.3.zip`：App（arm64）
- `SelectionTranslator-0.4.3-source.zip`：源码、测试、脚本、扩展和文档
- `SelectionTranslator-0.4.3-SHA256SUMS.txt`
- `appcast.xml`：Sparkle feed
- `SelectionTranslator-0.4.3.md`：本说明
