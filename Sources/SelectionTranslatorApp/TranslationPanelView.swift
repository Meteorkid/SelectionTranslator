import SwiftUI
import AppKit
import Translation

struct TranslationPanelView: View {
    @ObservedObject var model: TranslationViewModel
    var onClose: () -> Void
    var onOpenLibrary: () -> Void
    @Environment(\.stAppearance) private var appearance

    var body: some View {
        STPanelSurface {
            VStack(spacing: 0) {
                header
                separator
                content
                separator
                footer
            }
        }
        .frame(width: 480, height: 420)
        .overlay {
            if #available(macOS 15.0, *) {
                SystemTranslationBridge(model: model)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                Image(systemName: "character.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.appName.isEmpty ? "翻译" : model.appName)
                    .font(.system(size: 13, weight: .semibold))
                if !model.sourceLabel.isEmpty, model.sourceLabel != model.appName {
                    Text(model.sourceLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            if !model.engineLabel.isEmpty {
                STStatusBadge(text: model.engineLabel, tone: .accent, showsIcon: false)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceBlock

                if let error = model.errorMessage, model.translation.isEmpty {
                    noticeBlock(error, tone: .danger)
                } else if model.translation.isEmpty, model.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在翻译…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                } else {
                    Text(model.translation)
                        .font(.system(size: 16, weight: .regular))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = model.errorMessage, !model.translation.isEmpty {
                    noticeBlock(error, tone: .warning)
                }

                if model.canExplainInContext {
                    explainBlock
                }

                if !model.contextText.isEmpty {
                    disclosureBlock(
                        title: "上下文",
                        count: model.contextText.count,
                        symbol: "text.alignleft",
                        text: model.contextText
                    )
                }

                if !model.documentContextText.isEmpty {
                    disclosureBlock(
                        title: "文档上下文",
                        count: model.documentContextText.count,
                        symbol: "doc.text",
                        text: model.documentContextText
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("原文")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(model.sourceText.count) 字符")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Text(model.sourceText)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if appearance == .liquidGlass {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.11), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor.opacity(0.32))
                .frame(width: 2)
                .padding(.vertical, 9)
                .padding(.leading, 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    appearance == .liquidGlass
                        ? Color.white.opacity(0.10)
                        : Color.clear,
                    lineWidth: 0.7
                )
        }
    }

    private var explainBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("语境解释")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.explainInContext()
                } label: {
                    Text(model.contextExplanation.isEmpty ? "解释" : "重新解释")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(model.isExplaining)

                if model.isExplaining {
                    ProgressView().controlSize(.mini)
                }
            }

            if let error = model.explanationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.contextExplanation.isEmpty {
                Text(model.contextExplanation)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background {
            if appearance == .liquidGlass {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.06))
                    }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.055))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    appearance == .liquidGlass
                        ? Color.white.opacity(0.12)
                        : Color.accentColor.opacity(0.12),
                    lineWidth: 0.7
                )
        }
    }

    private func disclosureBlock(title: String, count: Int, symbol: String, text: String) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .lineLimit(12)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(count) 字符")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                copy(model.translation + explanationSuffix)
            } label: {
                Label("复制译文", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.translation.isEmpty)

            Button {
                copy(model.sourceText)
            } label: {
                Image(systemName: "doc")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .disabled(model.sourceText.isEmpty)
            .help("复制原文")

            Button {
                model.toggleFavorite()
            } label: {
                Image(systemName: model.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(model.isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .disabled(!model.canFavorite)
            .help(model.canFavorite ? "收藏到生词本" : "翻译完成后可收藏")

            if model.enableTTS {
                Menu {
                    Button("朗读原文") { model.speakSource() }
                    Button("朗读译文") { model.speakTranslation() }
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .frame(width: 16)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("朗读")
            }

            Button {
                model.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help("重新翻译")

            Button(action: onOpenLibrary) {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help("打开历史与生词本")

            Spacer()

            if model.isStreaming {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(statusText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private func noticeBlock(_ message: String, tone: STStatusTone) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: tone.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.color)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tone.color.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tone.color.opacity(0.12), lineWidth: 0.7)
        }
    }

    private var statusText: String {
        if model.isStreaming {
            return "生成中"
        }
        let parts = [model.sourceLabel, model.engineLabel].filter { !$0.isEmpty }
        return "\(parts.joined(separator: " · ")) · \(model.errorMessage == nil ? "完成" : "未完成")"
    }

    private var explanationSuffix: String {
        let explanation = model.contextExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        return explanation.isEmpty ? "" : "\n\n语境解释：\n" + explanation
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@available(macOS 15.0, *)
private struct SystemTranslationBridge: View {
    @ObservedObject var model: TranslationViewModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: model.needsSystemTranslation, initial: true) { _, needs in
                if needs {
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(
                            identifier: LanguageCatalog.systemIdentifier(for: model.systemTargetLanguage)
                        )
                    )
                } else {
                    configuration = nil
                }
            }
            .translationTask(configuration) { session in
                let text = await MainActor.run { model.sourceText }
                do {
                    let response = try await session.translate(text)
                    await MainActor.run {
                        model.applySystemTranslation(response.targetText)
                    }
                } catch {
                    let message = "系统翻译未完成（可能尚未下载语言包，可在系统设置 → 通用 → 语言与地区 → 翻译中下载）：\(error.localizedDescription)"
                    await MainActor.run {
                        model.applySystemTranslationError(message)
                    }
                }
            }
    }
}

struct ErrorPanelView: View {
    let message: String
    var actionTitle: String?
    var onAction: (() -> Void)?
    var onClose: () -> Void
    var height: CGFloat = 240

    private var tone: STStatusTone {
        if message.contains("失败") || message.contains("错误") || message.contains("无法") {
            return .danger
        }
        if message.contains("发现新版本") {
            return .accent
        }
        return .warning
    }

    var body: some View {
        STPanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(tone.color.opacity(0.12))
                        Image(systemName: tone.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tone.color)
                    }
                    .frame(width: 30, height: 30)

                    Text("提示")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.045), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)

                Text(message)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                Spacer(minLength: 16)

                if let actionTitle, let onAction {
                    HStack {
                        Spacer()
                        Button(actionTitle, action: onAction)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 480, height: height)
    }
}

struct PermissionPanelView: View {
    var onOpenSettings: () -> Void
    var onUseClipboard: () -> Void
    var onClose: () -> Void

    var body: some View {
        STPanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                        Image(systemName: "lock.shield")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 30, height: 30)

                    Text("还差一步：辅助功能权限")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.045), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)

                VStack(alignment: .leading, spacing: 7) {
                    Text("macOS 需要你手动允许一次，才能读取其他应用里的选中文字。授权后 ⌥D 就能直接划词翻译。")
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("暂时不想授权？选中文字 → ⌘C → ⌥V；或者直接按 ⌥O 截图 OCR。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Button("打开系统设置") {
                        onOpenSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("试试剪贴板模式") {
                        onUseClipboard()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("关闭", action: onClose)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 480, height: 250)
    }
}
