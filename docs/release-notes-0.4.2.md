# SelectionTranslator 0.4.2

发布日期：2026-11-27  
版本：0.4.2 / build 7  
系统要求：macOS 14.0+，arm64  
许可证：Apache License 2.0

## 本版重点：阅读控制、字段级隐私与调用边界

`0.4.2` 把 `0.4.1` 之后留在 `main` 上的第二批改造收进发布包。它不改变取词和翻译的基本交互，主要补齐三件事：

1. 让译文更贴近阅读场景：风格、术语表、长文档窗口和 PDF 上下文；
2. 让本机历史不再以明文落盘：历史敏感字段和历史搜索都已迁移到加密存储；
3. 让公开的 `selectiontranslator://` URL Scheme 不再只看限流，而是校验调用方签名。

## 详细更新内容

### 1. 翻译与阅读

- **五种译文风格**：自然、忠实、学术、技术、简洁。风格指令进入 system prompt，并纳入缓存键；切换风格不会复用旧译文。
- **术语表**：原文术语与指定译法成对保存，只对有效条目生成 `<glossary>` 块；术语表变化会使缓存失效。
- **长文档上下文**：不再盲目截掉开头，优先保留选区首次出现位置附近的窗口，按行边界收尾；找不到选区时回退到开头。
- **PDF 导入**：设置页「上下文」新增「从 PDF 导入」，用 PDFKit 提取文本；扫描件提示改用截图 OCR。
- **阅读节奏**：设置页新增风格、术语表、阅读节奏等控件。

### 2. 体验

- **选中后立即翻译**：可选跳过浮标直接翻译；默认关闭，避免默认产生模型调用。
- **按 App 排除**：可按 bundle ID 排除取词；排除后不显示浮标，快捷键会明确提示。
- **首启授权卡**：首次引导可现场请求辅助功能/屏幕录制权限并刷新状态；不授权仍可用剪贴板、输入翻译和浏览器扩展。
- **首启窗口尺寸修正**：`620 × 640`，底部授权卡不再被裁切。

### 3. 隐私与工程

- **历史字段级加密**：原文、译文、上下文、App 名与 bundle ID 使用 AES-GCM；账户、时间、语言等查询字段保留明文；密钥在 Keychain 的 `historyEncryptionKey`。
- **旧数据迁移**：旧明文行、半迁移行首次读取时原地修复；`char_count` 自动回填，统计不再依赖密文长度；历史搜索改为解密后内存过滤。
- **上下文加密**：整篇上下文以 AES-GCM 文件保存，密钥在 Keychain；旧明文 `.txt` 自动迁移并删除。
- **文件权限**：数据目录 `0700`，历史库、上下文文件和 `profiles.json` 为 `0600`。
- **URL 调用方校验**：从 Apple Event 原始地址解析发送进程，校验 bundle ID 与代码签名证书；只接受 Safari/Chrome/Edge/Firefox、Finder、快捷指令与自动化来源，未知来源拒绝。原有 20,000 字符上限和每分钟 60 次限流保留。
- **测试**：新增历史加密/半迁移、URL 签名策略、设置迁移、Prompt、长文裁剪、OCR 版面等用例；当前 44 个 XCTest 全部通过。
- **CI**：GitHub Actions 继续执行 XcodeGen、Debug 构建和单元 XCTest。

### 4. 未纳入本次验收

- `SelectionTranslatorUITests` 冒烟测试 target 和独立 scheme 已加入，但实际运行仍被 macOS UI Automation 权限弹窗阻塞；本次发布只以 44 个单元测试作为自动化验收，不声称 UI 自动化已通过。
- 发布包仍为 Apple Development 签名，未使用 Developer ID 公证。首次打开可能被 Gatekeeper 拦截，请在 Finder 里右键“打开”，或到系统设置里允许。

## 升级说明

- `0.4.1` 已包含 Sparkle 更新链路，可自动检查到 `0.4.2`；也可以手动下载 zip 覆盖安装。
- 从 `0.4.0` 升级请手动下载 `0.4.2` 覆盖安装一次。
- 首次读取由旧版本创建的加密历史/keychain 项时，系统可能要求一次钥匙串授权；允许后同一签名不再反复弹窗。

## 验证

- `./scripts/build.sh`：通过，Apple Development 签名。
- `xcodebuild test -scheme SelectionTranslator`：44 个 XCTest，0 failures。
- 历史库迁移后全部记录为 `enc:v1:`，字符统计完整。
- Finder/Safari 调起 `selectiontranslator://` 实测通过；伪造证书来源在单元测试中被拒绝。
- Sparkle appcast 与 zip 的 EdDSA 签名在发布前校验。

## 资产

- `SelectionTranslator-0.4.2.zip`：App（arm64）
- `SelectionTranslator-0.4.2-source.zip`：源码、测试、脚本、扩展和文档
- `SelectionTranslator-0.4.2-SHA256SUMS.txt`
- `appcast.xml`：Sparkle feed
- `SelectionTranslator-0.4.2.md`：本说明
