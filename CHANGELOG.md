# Changelog

## Unreleased — 0.4.0 之后

- 浏览器/Electron AX 树预启用，Chrome 原生取词补上 AX text marker 上下文。
- AX 调用增加 0.20s 超时；Chromium 聚焦元素 bounded fallback；安全输入和密码字段 fail closed；system-wide 焦点回退校验前台 PID。
- 剪贴板降级改为目标 PID + `changeCount` + 快照恢复，文件复制不当作选中文字。
- 鼠标划词增加焦点元素 bounds + 20pt 容差校验，点击工具栏/侧边栏时不会把旧选区当成新选区。
- OCR 增加语言自动检测、同行碎片合并和段落间距重建；新增 4 个 OCR 版面测试，XCTest 共 17 个。
- OCR 增加低置信度多 pass：灰度/对比度/锐化增强、深色反色兜底、按置信度/字符数/行数评分；新增 3 个质量与增强测试，XCTest 共 20 个。
- 鼠标划词增加点击点校验，新增 4 个单元测试；XCTest 共 24 个。
- 剪贴板兜底增加截图浮层检测和串行化锁，避免截屏浮层吞掉 ⌘C、并发触发互相覆盖；新增 3 个浮层几何测试，XCTest 共 27 个。
- 取词增加 `AXSelectedTextMarkerRange` 兜底；无 `AXSelectedTextRange` 时用选中文本反查全文范围恢复上下文；新增 3 个反查测试，XCTest 共 30 个。
- 细节见 `docs/open-source-capture-ocr-review.md`；未改变 v0.4.0 Release。

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
