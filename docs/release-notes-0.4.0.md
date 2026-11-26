## 本版重点：液态玻璃主题

v0.4.0 新增可切换的 **液态玻璃** 外观。原生主题仍是默认，旧设置会自动回退，不影响原有使用。

- 设置页品牌头右侧提供「原生 / 液态玻璃」切换，立即生效并持久化。
- 覆盖设置 5 个 tab、翻译浮窗、输入翻译、历史/生词本、错误与权限提示面板。
- macOS 26 浮窗使用系统 `glassEffect`；macOS 14/15 使用半透明材质 + 高光描边 fallback。
- 原生主题布局、材质和功能保持不变。

## 其他

- 浏览器扩展 manifest 同步到 0.4.0。
- 新增外观迁移回退与 round-trip 测试；XCTest 共 13 个，全部通过。
- 更新 README、UI/液态玻璃设计记录和设置页截图。

## 下载说明

- `SelectionTranslator-0.4.0.zip` 是 **arm64** App，使用 **Apple Development** 开发签名，**未做 Developer ID 公证**。首次打开可能被 Gatekeeper 拦截，请在 Finder 中右键「打开」，或到系统设置里允许。
- `SelectionTranslator-0.4.0-source.zip` 包含源码、脚本、浏览器扩展和文档。
- 更新检查仍是轻量 JSON 检查，不会自动下载或安装。

## 验证

- `./scripts/build.sh`：BUILD SUCCEEDED
- `xcodebuild test ...`：Executed 13 tests, with 0 failures
- 截图与设计记录见仓库 `docs/liquid-glass.md`、`docs/v0.4.0-status.md`

**已知限制**：没有 Developer ID，无法完成公证；App 包仅 arm64；Safari/Chrome 扩展仍需手动加载/启用。
