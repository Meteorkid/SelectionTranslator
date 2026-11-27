# SelectionTranslator 0.4.1

发布日期：2026-11-27  
版本：0.4.1 / build 6  
系统要求：macOS 14.0+，arm64  
许可证：Apache License 2.0

## 本版重点：从“能用”到“可发布、可更新、可解释”

`0.4.1` 是一次收口版本。它把此前留在 `main` 上的取词/OCR 硬化正式收进发布包，同时补齐一个独立 Mac App 必须具备的四件事：

1. 明确的许可证与第三方组件声明；
2. 可验证的 Sparkle 自动更新链路；
3. 写清楚数据边界的隐私说明；
4. 不打断老用户、又能解释产品原则的首次启动引导。

## 详细更新内容

### 1. 许可证与合规

- 项目许可证从“未声明”改为 **Apache License 2.0**，新增标准全文 `LICENSE`（202 行）。
- 新增 `PRIVACY.md`，并随 App 打包到 `Contents/Resources/PRIVACY.md`。
- `Support/Resources/NOTICE.md` 增加项目 Apache-2.0 声明，并保留 Sparkle（MIT）、ECDICT（MIT）的第三方声明。
- `LICENSE`、`PRIVACY.md` 同时加入 App 资源和源码包，下载后可离线查看。

### 2. Sparkle 2 自动更新

- 通过 Swift Package Manager 引入 Sparkle，target 依赖 `package: Sparkle`。
- `Info.plist` 写入：
  - `SUFeedURL = https://github.com/Meteorkid/SelectionTranslator/releases/latest/download/appcast.xml`
  - `SUPublicEDKey`（EdDSA 公钥）
  - `SUEnableAutomaticChecks = true`
  - `SUScheduledCheckInterval = 86400`
  - `SUAllowsAutomaticUpdates = false`（检查自动，安装前仍由用户确认）
- 新增 `SparkleUpdater`，用 `SPUStandardUpdaterController` 管理更新；实现 `supportsGentleScheduledUpdateReminders`，避免菜单栏 App 在后台检查时弹出不合时宜的提醒。
- 设置页「数据与权限 → 更新」提供“检查更新”；菜单栏提供同名入口。
- 删除旧的轻量 JSON `UpdateChecker`、`updateFeedURL`、`checkForUpdatesOnLaunch`，不再同时维护两条更新链路。
- 新增 `scripts/appcast.sh`：从 `dist/` 的 zip 生成 appcast、逐条注入 EdDSA 签名、签名 feed 本身，并校验通过后才写回仓库。
- 更新私钥不进入仓库；默认读取 `~/Library/Application Support/SelectionTranslator/Sparkle/ed25519.key`（权限 `0600`）。

### 3. 隐私说明与首启引导

- 首启窗口使用三张卡片，标题严格为：
  - **不会误取**
  - **不会丢上下文**
  - **不会打断截图**
- 首启页底部提供完整隐私说明入口和「开始使用」；点击完成后写入 `SelectionTranslator.onboardingCompleted.v1`。
- 老用户迁移：只要已有 `SelectionTranslator.settings`，就自动标记引导完成，升级后不会被新窗口打断；设置页仍可「重新查看首次引导」。
- 设置页新增「隐私与引导」区块：查看隐私说明、重新查看首次引导。
- `PRIVACY.md` 说明：
  - 本机 SQLite、JSON、上下文文件、UserDefaults、Keychain 的用途；
  - 主动翻译、Apple 系统翻译、AnkiConnect、Sparkle 检查更新四类联网时机；
  - 剪贴板降级与截图 OCR 的边界；
  - 辅助功能、屏幕录制权限的用途；
  - Sparkle、ECDICT 第三方组件。
- 默认不接入分析 SDK、崩溃上报或云端账户。

### 4. 取词可靠性

- AX 调用增加 **0.20s 超时**，避免某个 App 的 Accessibility 卡住整个取词流程。
- Chrome / Electron 切到前台时预启用 AX 树，减少首次划词等待。
- Chromium 原生取词补上 `AXSelectedTextMarkerRange` 上下文；只有 marker range、没有普通 selected range 的 WebKit/Chromium 选区也能恢复上下文。
- 安全输入与密码字段 fail closed，不读取系统安全输入框内容。
- system-wide 焦点回退增加前台 PID 校验，避免把旧 App 的选区当成当前选区。
- 鼠标划词增加鼠标点与焦点元素 bounds 的校验（20pt 容差），点击工具栏/侧边栏时丢弃陈旧选区。
- 剪贴板降级改为：
  - 只对目标 PID 发合成 `⌘C`；
  - 等待 `changeCount` 真正变化；
  - 保存并恢复剪贴板快照；
  - 文件复制不当作选中文字；
  - 截图工具浮层期间跳过；
  - 并发触发串行化，避免互相覆盖。

### 5. OCR 版面与质量

- 同一行的识别碎片合并，避免把一行拆成多个词。
- 中英文续行按段落拼接；列表项和明显行距保留换行，段落间距保留空行。
- 低置信度时自动多 pass：灰度、对比度、锐化增强，必要时反色；按置信度、字符数、行数评分选择最佳结果。
- 保留交互式框选 OCR、静默 OCR、屏幕录制授权入口和一次性权限说明。

### 6. 工程与发布

- `scripts/build.sh` 指定 `-clonedSourcePackagesDirPath build/SourcePackages`，并改为 `codesign --force --deep` 签主 App。
- `scripts/notarize.sh` 增加 Sparkle 嵌套组件签名顺序：`Downloader.xpc`、`Installer.xpc`、`Autoupdate`、`Updater.app`、`Sparkle.framework`，再签主 App；需要 Developer ID 与 notary profile，当前未实际执行。
- `scripts/package.sh` 的源码包加入 `LICENSE`、`PRIVACY.md`、`appcast.xml`、`CHANGELOG.md`。
- 浏览器扩展 manifest 同步到 `0.4.1`。
- XCTest 仍为 **33 个，0 failures**。

## 升级与兼容性

- **从 0.4.0 升级**：0.4.0 的发布 zip 不含 Sparkle，无法自动更新；请手动下载 `SelectionTranslator-0.4.1.zip` 覆盖安装一次。
- **从 0.4.1 开始**：包内已包含 Sparkle；后续版本会通过签名 appcast 自动检查，安装前仍要用户确认。
- 设置、账户、历史、生词本和上下文文件保持兼容；老用户首次启动不会看到新引导。
- 仅提供 arm64 构建；Intel Mac 需要自行从源码构建或等待后续通用包。

## 验证

- `./scripts/build.sh`：`BUILD SUCCEEDED`
- `xcodebuild test`：`33 tests, 0 failures`
- `codesign --verify --deep --strict`：通过
- Sparkle live feed：可下载，`sign_update --verify` 通过
- EdDSA 签名：feed 与 enclosure 均通过校验
- 首启页实机验证：三张卡完整、按钮关闭窗口、`onboardingCompleted.v1` 写入
- 设置页实机验证：「更新」「隐私与引导」区块可见；「重新查看首次引导」可再次打开首启窗口

## 下载与校验

- `SelectionTranslator-0.4.1.zip`：arm64 App，Apple Development 开发签名，**未做 Developer ID 公证**。
- `SelectionTranslator-0.4.1-source.zip`：源码、脚本、浏览器扩展、设计文档和本说明。
- SHA256：

| 文件 | SHA256 |
| --- | --- |
| `SelectionTranslator-0.4.1.zip` | `c473d378af71ce6c111d83f1e1841a3c314f352be9f9bc78caa8f60269d13051` |
| `SelectionTranslator-0.4.1-source.zip` | 见 `SelectionTranslator-0.4.1-SHA256SUMS.txt` |

## 已知限制

- 没有 Developer ID 证书，无法完成公证；首次打开可能被 Gatekeeper 拦截。请在 Finder 中右键「打开」，或到系统设置里允许。
- App 包仅 arm64。
- Chrome/Safari 扩展仍需手动加载/启用一次；Safari 需要“所有网站”权限。
- OCR 识别率受选区质量、字体、背景对比度影响，不等于完美。
- Sparkle 自动检查已工作，但“检查更新”按钮的完整交互仍建议在发布后手动点一次确认。
- 本轮没有替换 v0.4.0 的旧 zip；v0.4.1 是新的 Release 资产。
