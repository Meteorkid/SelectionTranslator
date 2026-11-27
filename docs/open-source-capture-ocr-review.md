# 开源取词与 OCR 方案对照：0.4.0 之后的取词硬化

日期：2026-11-27  
状态：已应用到 `main`；不改变已发布的 `v0.4.0` Release，也不复制任何 GPL 源码。

## 结论

这次没有再找“更像 Bob 的多服务聚合器”，而是把范围收窄到划词翻译最关键、也最容易翻车的两条链路：**跨 App 取词**和**OCR 版面重建**。

对照后选择的参考对象是 **Cida**（原生 Swift、Apache-2.0），补充参考 **Easydict**（事件时序）、**Pot Desktop**（插件/OCR 广度）和 **Blurt**（屏幕文字，MIT）。最终没有引入第三方运行时依赖，只吸收了四条实现原则：

1. 浏览器/Electron 的 AX 树是懒加载的，必须在取词前预启用。
2. 所有 AX 调用必须有短超时；密码输入必须 fail closed。
3. 剪贴板降级不能“清空再 sleep”，要用目标 PID、`changeCount` 和快照恢复。
4. OCR 不能把每个 Vision observation 当一行；要按行框归并，再按段间距重建。

## 参考项目

| 项目 | 语言/许可 | 值得参考 | 不直接采用 |
| --- | --- | --- | --- |
| [Cida](https://github.com/Xuanwo/cida) | Swift / Apache-2.0 | AX 树启用、短消息超时、安全输入保护、文本标记取全文、剪贴板快照、OCR 版面重建 | 它是“翻译/润色任意处文字”的产品，选区替换模型与本项目不同 |
| [Easydict](https://github.com/tisfeng/Easydict) | Swift / GPL-3.0 | 事件监听、划词 debounce、服务层抽象 | 65k+ 行、多服务和 GPL，不适合照搬 |
| [Pot Desktop](https://github.com/pot-app/pot-desktop) | JS/Rust / GPL-3.0 | 多服务插件、跨平台 OCR | Tauri/插件体系与原生单 App 的取舍不同 |
| [Blurt](https://github.com/AGIHunt/blurt) | Swift/Rust / MIT | 屏幕文字、OCR 测试样例 | 产品中心是语音输入/记录，不是划词翻译 |
| [VocabPocket](https://github.com/alanzeng423/VocabPocket) | Swift / MIT | OCR 原图、增强、反色多 pass 和结果评分 | 功能面更宽，翻译服务/生词本不是本次目标 |
| [MoePeek](https://github.com/cosZone/MoePeek) | Swift / AGPL-3.0 | AX → AppleScript → 剪贴板三级兜底、鼠标点击点校验、截图浮层保护、剪贴板访问门 | AGPL，只参考行为，不复制源码 |
| [invisible-translator](https://github.com/on1ymyse1f/invisible-translator) | Swift / MIT | `AXSelectedTextMarkerRange` 读取 WebKit/Chromium 选区，选区文本反查范围 | 产品侧重点在屏幕字幕与本地翻译 |

Cida 的关键源码位置：

- `Sources/Cida/TranslationLayerAccessibility.swift`：`AXManualAccessibility` / `AXEnhancedUserInterface`
- `Sources/Cida/SelectedText.swift`：AX 选区读取、`AXTextMarker`、剪贴板复制兜底
- `Sources/Cida/SelectionReplacement.swift`：0.03s AX 超时、`IsSecureEventInputEnabled`、安全文本子角色、PID 定向事件
- `Sources/Cida/TextRecognition.swift`：`automaticallyDetectsLanguage`、同行碎片合并、段落间距

这些实现只作为行为和 API 选择的参考；本项目按自己的 `AX`、`SelectionCaptureService`、`ClipboardFallback` 结构重写。

## 应用的改动

### 1. 浏览器/Electron AX 树预启用

`AX.prepareAccessibility(for:)` 在 App 激活和取词前调用：

- 对 Electron 设置 `AXManualAccessibility`；
- 对 Chromium 浏览器，在 manual 失败时设置 `AXEnhancedUserInterface`；
- `MouseSelectionMonitor` 监听 `didActivateApplicationNotification`，提前给前台 App 建树。

Chrome 的 AX 树需要约两秒才会出现；如果只在用户按下快捷键时才设置，第一次取词仍可能读不到。预启用把这段时间移到 App 切到前台时。

### 2. AX 超时和安全输入

- 所有 `AXUIElementCopyAttributeValue` 前设置 `0.20s` messaging timeout。
- `AXIsProcessTrusted`、`IsSecureEventInputEnabled` 和 `kAXSecureTextFieldSubrole` 三重失败保护。
- system-wide 焦点回退会校验 `AXUIElementGetPid` 是否等于前台 App PID，拒绝来自非激活面板或其他进程的焦点。
- Chromium 根节点暂时没有 `AXFocusedUIElement` 时，做一次 120ms / 18 层的 bounded 搜索，只接受显式 focused 的文本字段。
- 取词前阻止 Terminal、iTerm、Keychain、Passwords、1Password、Bitwarden 等敏感 App。

### 3. 剪贴板降级重写

`ClipboardFallback` 从“清空剪贴板 → 固定 sleep 0.12s → 读 → 恢复”改成：

- `⌘C` 只发给 frontmost App 的 PID（`postToPid`），避免焦点切换后打到别的 App；
- 先保存完整 pasteboard 快照，等待 `changeCount` 真正变化且 types 非空；
- 文件复制不当作选中文字；
- 恢复快照并标记 `org.nspasteboard.TransientType`，避免剪贴板管理器把恢复动作再记一条；
- 超时后如果目标 App 迟到的复制只让 `changeCount` 增加 1，再恢复快照；如果用户已经复制了别的内容，不覆盖。
- 截图工具的全屏取词浮层出现时跳过合成 ⌘C，避免把 `⌘C` 当成截屏工具的“复制截图”快捷键而取消截图。
- 剪贴板快照/复制/恢复用锁串行化；迟到的恢复也拿同一把锁，避免两次快速触发互相覆盖。

### 4. 浏览器上下文：AX text marker 回退

Chrome 的 `AXValue` 是空的，`AXStringForRange` 也不支持；但 `AXTextMarkerRangeForUIElement` 加上 `AXAttributedStringForTextMarkerRange` 能拿到整页文本。

`AX.fullText(of:)` 现在先读常规 `AXValue`，为空时走 text marker，再用 `AXSelectedTextRange` 定位并截取上下文。实测本地 Chrome 页面：

- `Source: accessibility`
- 选中 214 chars
- 上下文 339 chars（包含标题和前后两段）

这修复了此前 Chrome 里只有选中文字、没有上下文的退化；浏览器扩展路径本来就会传 `context/document`，现在原生 `⌥D` 路径也一致。

### 4.1 只有 marker 的选区

有些 WebKit/Chromium 应用不返回 `AXSelectedText`，只暴露 `AXSelectedTextMarkerRange`。`AX.selectedText` 现在增加第二个分支：

- 先读 `kAXSelectedTextAttribute`；
- 为空时读 `AXSelectedTextMarkerRange`，再用 `AXStringForTextMarkerRange` / `AXAttributedStringForTextMarkerRange` 取选中文字；
- 如果连 `AXSelectedTextRange` 也没有，就把选中文字在全文 marker 文本里反查 UTF-16 range，再截取上下文。

反查使用第一次出现的位置，适合普通段落；同一页面出现多次完全相同句子时，上下文可能落在第一处，边界见文末。

### 5. OCR 版面重建

`OCRTextLayout` 取代原来的“每个 observation 一行”：

- `automaticallyDetectsLanguage = true`，减少中英混排时英文被中文识别器写成全角标点；
- 同一视觉行的碎片按 x 坐标合并；
- 行间距按中位行高判断，普通换行用单换行，段落间距用空行；
- Vision 的 bottom-left bounding box 转成 top-left 坐标后再排序。
- 相邻视觉行默认按段落拼接：只有明显行距、列表项、或上一行末尾仍有空间时保留换行；中文续行不加空格，英文续行加空格，连字符续行去掉连字符。

这个“拼接而非逐行输出”的策略参考 Cida 的 `RecognizedTextLayout`，但保留本项目原有的段落空行规则。

## 第二轮：OCR 多 pass

第一轮解决的是“取词能不能拿到”，第二轮解决的是“截图文字识别失败时能不能救回来”。

参考 `VocabPocket` 的 OCR 思路，但不直接复制其源码：

- 原图先跑一次 `.accurate` 识别；只有结果为空、字符太少或平均置信度低于 0.52 才进入增强 pass。
- 增强 pass 做灰度、对比度、亮度、锐化；小图放大到 2x，中等图 1.5x，大图不放大，避免 4K 截图先被无谓放大。
- 增强 pass 仍不可靠时，再跑一次反色 pass，覆盖深色背景/浅色文字。
- 每个 pass 用 `OCRQuality` 打分：平均置信度 + 字符数 + 行数，避免“只识别到一个高置信度单词”被当成最佳结果；最终仍交给 `OCRTextLayout` 重建行和段落。
- 原图可靠时只跑一次，不为正常截图增加延迟。

这一轮也核对了 `MoePeek` 的三级取词和 `invisible-translator` 的 `AXSelectedTextMarkerRange` 读取；两者证明第一轮的 text-marker 方向正确。`MoePeek` 的截图浮层保护和剪贴板访问门进一步用于剪贴板兜底：浮层期间直接跳过合成 ⌘C，剪贴板操作串行化；因其 AGPL-3.0，本次只参考行为、独立实现，没有复制源码。

## 验证

- `./scripts/build.sh`：**BUILD SUCCEEDED**
- `xcodebuild test ...`：**Executed 33 tests, with 0 failures**
- Chrome 本地页面：`selection-probe` 读到 92 字符选区 + 339 字符上下文（已重新编译当前代码）
- 剪贴板 probe：目标 Chrome 选区复制成功（214 字符），剪贴板快照 `restored: true`
- OCR probe：对 0.4.0 设置页、深色背景白字、灰底灰字合成图均能识别；设置页输出 220 字符，同行碎片合并、段落拼接/空行符合预期
- 鼠标点击点校验：`SelectionHitTest` 4 个单元测试覆盖元素内、20pt 容差边缘、远端拒绝和 Cocoa→AX 坐标翻转
- 截图浮层检测：3 个单元测试覆盖全屏、半屏拒绝和跨显示器；正常桌面 probe 返回 `capturing=false`
- marker 范围反查：3 个单元测试覆盖命中、未命中、空输入；Chrome 当前代码 probe 仍能带出完整上下文
- OCR 段落拼接：3 个新增测试覆盖英文续行、列表项换行、中文无空格续行
- 实机 Chrome 拖选：译图标正常出现，说明点校验没有误杀合法选区

## 已知边界

- Chromium 树预启用需要 App 先收到激活事件；如果刚切到浏览器就立刻按快捷键，第一次仍可能读不到，第二次通常可用。
- 部分 Electron App 只暴露 `AXManualAccessibility`，不暴露文本标记；这类 App 仍可能只能拿到 `AXSelectedText`。
- 剪贴板降级的 `⌘C` 仍使用 ANSI C 键码；Dvorak 等非 QWERTY 布局下需要后续补键盘布局映射。
- 安全输入、密码字段和敏感 App 选择直接失败，不尝试绕过。
- OCR 版面算法是轻量近似，不处理表格、竖排和多栏复杂版面；需要时再引入更强的版面模型。

## 下一步候选

1. 给 Chromium 加“选区变化监听”，而不是每次取词才查 AX。
2. 补键盘布局感知的 `⌘C` / `⌘V` 键码，参考 Cida 的 `TextEditingCommand` 思路。
3. 把 OCR 版面算法扩展到多栏、表格和竖排。
4. 再考虑第二个翻译服务；在此之前不引入插件系统。
5. 鼠标点校验目前只覆盖鼠标路径；键盘快捷键仍按用户显式操作读取选区，不做位置过滤。
6. marker 反查遇到重复文本时只能取第一处；后续可尝试用选区坐标或 caret 位置消歧。
