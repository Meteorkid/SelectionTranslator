import SwiftUI
import AppKit
import Translation

struct InputTranslationView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var accountStore: LocalAccountStore
    @StateObject private var model = TranslationViewModel()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    var onOpenLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("把一段文字交给模型，结合文档上下文翻译")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 10)

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 12) {
                inputArea
                actionBar
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.35)

            resultArea

            Divider().opacity(0.35)
            footer
        }
        .frame(width: 640, height: 560)
        .background(STWindowBackdrop(appearance: store.settings.appearance))
        .stAppearance(store.settings.appearance)
        .overlay {
            if #available(macOS 15.0, *) {
                InputSystemTranslationBridge(model: model)
            }
        }
        .onChange(of: accountStore.activeID) { _, _ in
            model.reset()
        }
    }

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $inputText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .padding(8)
                .stEditorSurface(focused: inputFocused)
                .focused($inputFocused)
                .frame(height: 138)

            if inputText.isEmpty {
                Text("粘贴或输入要翻译的文字…")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("目标语言")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $store.settings.targetLanguage) {
                    ForEach(LanguageCatalog.targets) { language in
                        Text(language.displayName).tag(language.displayName)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Text("\(inputText.count) / 8000")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Spacer()

            Button("从剪贴板填入") {
                if let text = NSPasteboard.general.string(forType: .string) {
                    inputText = String(text.prefix(8_000))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                translate()
            } label: {
                Label("翻译", systemImage: "arrow.right")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("⌘↩")
        }
    }

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("译文")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !model.engineLabel.isEmpty {
                    STStatusBadge(text: model.engineLabel, tone: .neutral, showsIcon: false)
                }
                if model.isStreaming {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.translation.isEmpty, let error = model.errorMessage {
                        noticeBlock(error, tone: .danger)
                    } else if model.translation.isEmpty, model.isStreaming {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在翻译…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else if model.translation.isEmpty {
                        HStack(spacing: 9) {
                            Image(systemName: "character.bubble")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Text("翻译结果会显示在这里")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text(model.translation)
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error = model.errorMessage, !model.translation.isEmpty {
                        noticeBlock(error, tone: .warning)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                copy(model.translation)
            } label: {
                Label("复制译文", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.translation.isEmpty)

            Button {
                model.toggleFavorite()
            } label: {
                Image(systemName: model.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(model.isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .disabled(!model.canFavorite)
            .help("收藏到生词本")

            if store.settings.enableTTS {
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
            .help("历史与生词本")

            Spacer()

            if model.isStreaming {
                ProgressView().controlSize(.mini)
            }

            Text(model.translation.isEmpty ? "待翻译" : "完成")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
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
    }

    private func translate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let document = store.settings.useDocumentContext
            ? String(
                DocumentContextRepository.read(accountID: accountStore.activeID)
                    .prefix(max(0, store.settings.documentContextMaxChars))
            )
            : ""
        model.start(
            text: String(text.prefix(8_000)),
            context: "",
            appName: "输入翻译",
            source: .input,
            settings: store.settings,
            apiKey: KeychainStore.read(key: "apiKey") ?? "",
            accountID: accountStore.activeID,
            documentContext: document
        )
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@available(macOS 15.0, *)
private struct InputSystemTranslationBridge: View {
    @ObservedObject var model: TranslationViewModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: model.needsSystemTranslation, initial: true) { _, needs in
                configuration = needs
                    ? TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(
                            identifier: LanguageCatalog.systemIdentifier(for: model.systemTargetLanguage)
                        )
                    )
                    : nil
            }
            .translationTask(configuration) { session in
                let token = await MainActor.run { model.systemToken }
                let text = await MainActor.run { model.sourceText }
                do {
                    let response = try await session.translate(text)
                    await MainActor.run {
                        model.applySystemTranslation(response.targetText, token: token)
                    }
                } catch {
                    await MainActor.run {
                        model.applySystemTranslationError("系统翻译未完成（可能尚未下载语言包，可在系统设置 → 通用 → 语言与地区 → 翻译中下载）：\(error.localizedDescription)", token: token)
                    }
                }
            }
    }
}

@MainActor
final class InputTranslationWindowController {
    private var window: NSWindow?

    func show(store: SettingsStore, accountStore: LocalAccountStore, onOpenLibrary: @escaping () -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = InputTranslationView(
            store: store,
            accountStore: accountStore,
            onOpenLibrary: onOpenLibrary
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "输入翻译"
        window.minSize = NSSize(width: 620, height: 540)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
