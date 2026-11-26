# 发布与公证

## 本地可做

```bash
./scripts/build.sh
./scripts/package.sh
```

`package.sh` 会生成：

- `dist/SelectionTranslator-<version>.zip`：可直接打开的 App
- `dist/SelectionTranslator-<version>-source.zip`：源码、脚本、浏览器扩展和文档

## 公证的前置条件

公证不是“再点一次构建”，而是需要 Apple Developer Program 的 **Developer ID Application** 证书和 notarytool 凭据。当前开发机只有：

```text
Apple Development（本机开发签名）
```

这只能用于本机开发签名，不能替代 Developer ID，也无法完成 notarize。因此本仓库提供了流程脚本，但不伪造“已公证”的结果。

## 有 Developer ID 后的步骤

1. 在 Apple Developer 后台创建 Developer ID Application 证书并安装到钥匙串。
2. 保存 notarytool 凭据：

```bash
xcrun notarytool store-credentials "selectiontranslator-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

3. 用 Developer ID 重新签名并公证：

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="selectiontranslator-notary" \
./scripts/notarize.sh
```

4. 验证：

```bash
spctl -a -vv build/DerivedData/Build/Products/Debug/SelectionTranslator.app
```

## 自动更新

当前版本不引入 Sparkle 或第三方更新框架，避免为了“自动更新”把轻量 App 重新做重。发布渠道明确后，可以二选一：

- 托管 appcast + Sparkle：适合正式分发；
- 仓库 Release 页 + 手动检查：适合个人使用。

在没有稳定下载域名和签名身份前，不把未验证的更新地址写进产品。
