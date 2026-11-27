import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

private struct OllamaTags: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

private struct RunningAppOption: Identifiable {
    let id: String
    let name: String
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case account
    case translation
    case context
    case shortcuts
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "账户"
        case .translation: return "翻译"
        case .context: return "上下文"
        case .shortcuts: return "快捷键"
        case .data: return "数据与权限"
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .translation: return "character.bubble"
        case .context: return "doc.text"
        case .shortcuts: return "command"
        case .data: return "externaldrive"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var accountStore: LocalAccountStore
    var onOpenLibrary: () -> Void
    var onRunOCR: () -> Void
    var onOpenInput: () -> Void
    var onCheckForUpdates: () -> Void
    var onOpenPrivacy: () -> Void
    var onShowOnboarding: () -> Void

    @State private var apiKey: String = KeychainStore.read(key: "apiKey") ?? ""
    @State private var showKey = false
    @State private var selectedTab: SettingsTab = {
        if let raw = ProcessInfo.processInfo.environment["ST_SETTINGS_TAB"],
           let tab = SettingsTab(rawValue: raw) {
            return tab
        }
        return .account
    }()
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var screenRecordingTrusted = Permissions.hasScreenRecordingPermission()
    @State private var ollamaModels: [String] = []
    @State private var profileStats = HistoryStats()
    @State private var health: ProviderHealthResult?
    @State private var isTesting = false
    @State private var showingNewAccount = false
    @State private var newAccountName = ""
    @State private var showingRenameAccount = false
    @State private var renameText = ""
    @State private var showingDeleteAccount = false
    @State private var documentContext = ""
    @State private var documentContextLoaded = true
    @State private var documentContextError: String?
    @State private var newGlossaryTerm = ""
    @State private var newGlossaryTranslation = ""
    @State private var pdfImportMessage: String?
    @State private var isImportingPDF = false
    @State private var ankiHealth: String?
    @State private var ankiExportMessage: String?
    @State private var isTestingAnki = false
    @State private var isExportingAnki = false
    @State private var documentSaveTask: Task<Void, Never>?
    @State private var apiKeySaveTask: Task<Void, Never>?
    @FocusState private var contextFocused: Bool
    @Environment(\.stAppearance) private var stAppearance

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider().opacity(0.45)

            settingsTabBar

            Group {
                switch selectedTab {
                case .account:
                    accountTab
                case .translation:
                    translationTab
                case .context:
                    contextTab
                case .shortcuts:
                    shortcutsTab
                case .data:
                    dataTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: STTheme.settingsWidth, height: STTheme.settingsHeight)
        .background(STWindowBackdrop(appearance: store.settings.appearance))
        .stAppearance(store.settings.appearance)
        .animation(.easeInOut(duration: 0.22), value: store.settings.appearance)
        .onChange(of: apiKey) { _, newValue in
            // Avoid deleting and re-adding the Keychain item on every
            // keystroke while the user is typing a key.
            apiKeySaveTask?.cancel()
            apiKeySaveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                KeychainStore.save(newValue, key: "apiKey")
            }
        }
        .onDisappear {
            apiKeySaveTask?.cancel()
            KeychainStore.save(apiKey, key: "apiKey")
            documentSaveTask?.cancel()
            if documentContextLoaded {
                DocumentContextRepository.write(documentContext, accountID: accountStore.activeID)
            }
        }
        .onAppear {
            accessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
            screenRecordingTrusted = Permissions.hasScreenRecordingPermission()
            refreshOllama()
            refreshProfileStats()
            loadDocumentContext()
        }
        .onChange(of: accountStore.activeID) { _, _ in
            documentSaveTask?.cancel()
            refreshProfileStats()
            loadDocumentContext()
            ankiHealth = nil
        }
        .onChange(of: documentContext) { _, newValue in
            // Never auto-save a failed load back to disk: a Keychain denial
            // must not look like an empty document and delete the encrypted
            // context during the initial render.
            guard documentContextLoaded else { return }
            // Encrypting and writing the whole article on every keystroke
            // causes visible input lag. Coalesce edits into one write.
            documentSaveTask?.cancel()
            let accountID = accountStore.activeID
            documentSaveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                DocumentContextRepository.write(newValue, accountID: accountID)
            }
        }
        .alert("删除当前本地账户？", isPresented: $showingDeleteAccount) {
            Button("删除", role: .destructive) {
                accountStore.deleteProfile(accountStore.activeID)
                documentContext = DocumentContextRepository.read(accountID: accountStore.activeID)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除这个账户的切换入口；历史数据库里该账户的记录仍会保留。")
        }
        .alert("重命名账户", isPresented: $showingRenameAccount) {
            TextField("账户名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                accountStore.renameActive(renameText)
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            VStack(alignment: .leading, spacing: 14) {
                Text("新建本地账户")
                    .font(.system(size: 17, weight: .semibold))
                Text("账户与历史只在本机保存，不上传云端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("账户名称", text: $newAccountName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("取消") { showingNewAccount = false }
                    Button("创建") {
                        accountStore.createProfile(named: newAccountName)
                        showingNewAccount = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 340, height: 190)
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                selectedTab == tab
                                    ? (stAppearance == .liquidGlass
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.primary.opacity(0.10))
                                    : Color.clear
                            )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .stGlassCapsule()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            STBrandMark(size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("划词翻译")
                    .font(.system(size: 14, weight: .semibold))
                Text("把上下文交给翻译，而不是只翻一个词")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Picker("外观", selection: $store.settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 146)
                .help("切换界面主题")

                Text(versionText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.055), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 11)
        .background(STHeaderSurface())
    }

    private var versionText: String {
        AppVersion.display
    }

    // MARK: - Account

    private var accountTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                        Image(systemName: accountStore.activeProfile.avatarSymbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(accountStore.activeProfile.name)
                                .font(.system(size: 16, weight: .semibold))

                            Button {
                                renameText = accountStore.activeProfile.name
                                showingRenameAccount = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 18, height: 18)
                                    .background(Color.primary.opacity(0.045), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("重命名账户")
                        }

                        Text("本地账户 · 创建于 \(accountStore.activeProfile.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        newAccountName = ""
                        showingNewAccount = true
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)

                LabeledContent("切换账户") {
                    Picker("", selection: Binding(
                        get: { accountStore.activeID },
                        set: { accountStore.switchTo($0) }
                    )) {
                        ForEach(accountStore.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                HStack {
                    Text("删除只影响这个本地账户入口，不会删除历史记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("删除当前账户", role: .destructive) {
                        showingDeleteAccount = true
                    }
                    .buttonStyle(.borderless)
                    .disabled(accountStore.profiles.count <= 1)
                }
            } header: {
                STSectionHeader(title: "账户", systemImage: "person.crop.circle")
            }

            Section {
                HStack(spacing: 9) {
                    ForEach(LocalAccountStore.avatarSymbols, id: \.self) { symbol in
                        Button {
                            accountStore.setAvatar(symbol)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(
                                        accountStore.activeProfile.avatarSymbol == symbol
                                            ? Color.accentColor.opacity(0.14)
                                            : Color.primary.opacity(0.045)
                                    )
                                Image(systemName: symbol)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(
                                        accountStore.activeProfile.avatarSymbol == symbol
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                            }
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        accountStore.activeProfile.avatarSymbol == symbol
                                            ? Color.accentColor.opacity(0.55)
                                            : Color.primary.opacity(0.07),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .help("切换头像")
                    }
                }
                .padding(.vertical, 2)
            } header: {
                STSectionHeader(title: "头像", systemImage: "person.crop.circle.badge.checkmark")
            }

            Section {
                HStack(spacing: 8) {
                    STStatTile(value: "\(profileStats.total)", label: "翻译记录")
                    STStatTile(value: "\(profileStats.favorites)", label: "生词本")
                    STStatTile(value: "\(profileStats.characters)", label: "累计原文")
                }

                Text("数据来自本机 SQLite，按账户隔离，不会上传云端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                STSectionHeader(title: "本机数据", systemImage: "internaldrive")
            }
        }
        .stFormSurface()
        .task(id: accountStore.activeID) {
            refreshProfileStats()
        }
    }

    // MARK: - Translation

    private var translationTab: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ProviderPreset.all) { preset in
                        providerCard(preset)
                    }
                }
            } header: {
                STSectionHeader(title: "常用服务", systemImage: "square.stack.3d.up")
            }

            Section {
                fieldRow("API 地址") {
                    TextField("https://api.example.com/v1", text: $store.settings.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }

                fieldRow("模型") {
                    TextField("model-name", text: $store.settings.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }

                fieldRow("API Key") {
                    HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("本地模型可留空", text: $apiKey)
                            } else {
                                SecureField("本地模型可留空", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .frame(width: 18)
                        }
                        .buttonStyle(.borderless)
                        .help(showKey ? "隐藏 API Key" : "显示 API Key")
                    }
                    .frame(width: 300)
                }

                HStack(spacing: 10) {
                    Button(isTesting ? "测试中…" : "测试连接") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting)

                    if let health {
                        STStatusBadge(
                            text: health.ok ? "连接正常" : "连接失败",
                            tone: health.ok ? .success : .danger
                        )
                    }

                    Spacer()
                }

                if let health {
                    Text(health.message)
                        .font(.caption)
                        .foregroundStyle(health.ok ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("地址填到 /v1 即可；本地模型可留空 API Key，Key 存在系统钥匙串。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                STSectionHeader(title: "模型服务", systemImage: "network")
            }

            Section {
                HStack {
                    if ollamaModels.isEmpty {
                        STStatusBadge(text: "未检测到 Ollama", tone: .neutral)
                        Text("先确认本地服务正在运行")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        STStatusBadge(text: "发现 \(ollamaModels.count) 个模型", tone: .success)
                        Text(ollamaModels.prefix(3).joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack {
                    Button("使用本地 Ollama") {
                        let preferred = ollamaModels.first { $0.localizedCaseInsensitiveContains("qwen") }
                            ?? ollamaModels.first
                            ?? "qwen2.5:3b"
                        store.settings.apiBaseURL = "http://127.0.0.1:11434/v1"
                        store.settings.model = preferred
                        store.settings.providerName = "Ollama"
                    }
                    .buttonStyle(.bordered)

                    Button("重新检测") { refreshOllama() }
                        .buttonStyle(.bordered)
                }
            } header: {
                STSectionHeader(title: "本地 Ollama", systemImage: "desktopcomputer")
            }

            Section {
                Text("引擎顺序：单词查内置词库 → 缓存 → 本地/在线模型 → macOS 系统翻译 → 原文复制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("目标语言", selection: $store.settings.targetLanguage) {
                    ForEach(LanguageCatalog.targets) { language in
                        Text(language.displayName).tag(language.displayName)
                    }
                }

                Stepper(
                    "上下文长度：\(store.settings.contextLength) 字符",
                    value: $store.settings.contextLength,
                    in: 0...3000,
                    step: 200
                )

                Toggle("AX 取不到时用剪贴板降级", isOn: $store.settings.useClipboardFallback)
                Toggle("显示朗读按钮", isOn: $store.settings.enableTTS)
                Toggle("允许截图 OCR", isOn: $store.settings.enableOCR)
                Toggle("使用 macOS 系统词典（推荐）", isOn: $store.settings.useAppleDictionary)
                Toggle("鼠标划词后显示查询图标", isOn: $store.settings.enableMouseSelection)
                Toggle("鼠标悬停图标自动翻译", isOn: $store.settings.mouseHoverTranslate)
                    .disabled(!store.settings.enableMouseSelection)

                Text("鼠标划词和悬停翻译需要辅助功能权限；关闭时仍然可以用快捷键划词。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("温度") {
                    HStack(spacing: 8) {
                        Slider(value: $store.settings.temperature, in: 0...1, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f", store.settings.temperature))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            } header: {
                STSectionHeader(title: "翻译行为", systemImage: "slider.horizontal.3")
            }

            Section {
                Picker("译文风格", selection: $store.settings.translationStyle) {
                    ForEach(TranslationStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }

                Toggle("选中后立即翻译（跳过浮标）", isOn: $store.settings.autoTranslateOnSelection)
                    .disabled(!store.settings.enableMouseSelection)

                Text("立即翻译会在每次划词后直接调用翻译链，适合高频阅读；不确定时保持关闭，先用浮标确认选区。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                STSectionHeader(title: "阅读节奏", systemImage: "hare")
            }

            Section {
                Text("术语表会在提示词里要求模型优先采用指定译法；适合人名、产品名、论文术语。留空不生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($store.settings.glossary) { $entry in
                    HStack(spacing: 8) {
                        TextField("原文术语", text: $entry.term)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        TextField("指定译法", text: $entry.translation)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            store.settings.glossary.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 18)
                        }
                        .buttonStyle(.borderless)
                        .help("删除这条术语")
                    }
                }

                HStack(spacing: 8) {
                    TextField("原文术语", text: $newGlossaryTerm)
                        .textFieldStyle(.roundedBorder)
                    TextField("指定译法", text: $newGlossaryTranslation)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        let entry = GlossaryEntry(term: newGlossaryTerm, translation: newGlossaryTranslation)
                        guard entry.isValid else { return }
                        store.settings.glossary.append(entry)
                        newGlossaryTerm = ""
                        newGlossaryTranslation = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(!GlossaryEntry(term: newGlossaryTerm, translation: newGlossaryTranslation).isValid)
                }
            } header: {
                STSectionHeader(title: "术语表", systemImage: "character.book.closed")
            }
        }
        .stFormSurface()
    }

    private func providerCard(_ preset: ProviderPreset) -> some View {
        let isSelected = store.settings.providerName == preset.name

        return Button {
            apply(preset)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: providerIcon(for: preset))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.045))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(preset.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background {
                if stAppearance == .liquidGlass {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.10),
                                        Color.clear,
                                        isSelected
                                            ? Color.accentColor.opacity(0.08)
                                            : Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        stAppearance == .liquidGlass
                            ? (isSelected ? Color.accentColor.opacity(0.38) : Color.white.opacity(0.12))
                            : (isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06)),
                        lineWidth: isSelected ? 1 : 0.8
                    )
            }
            .shadow(
                color: stAppearance == .liquidGlass ? Color.black.opacity(0.10) : .clear,
                radius: stAppearance == .liquidGlass ? 7 : 0,
                y: stAppearance == .liquidGlass ? 3 : 0
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func providerIcon(for preset: ProviderPreset) -> String {
        switch preset.id {
        case "deepseek": return "sparkles"
        case "openai": return "wand.and.stars"
        case "ollama": return "desktopcomputer"
        case "lmstudio": return "square.stack.3d.up"
        default: return "network"
        }
    }

    // MARK: - Document context & Anki

    private var contextTab: some View {
        Form {
            Section {
                Text("把正在读的文章、论文或文档贴到这里。划词、剪贴板、输入翻译都会把这段内容作为背景交给模型；只会发送前 \(store.settings.documentContextMaxChars) 字符。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $documentContext)
                    .font(.system(size: 13))
                    .stEditorSurface(focused: contextFocused)
                    .focused($contextFocused)
                    .frame(height: 160)
                    .overlay(alignment: .topLeading) {
                        if documentContext.isEmpty {
                            Text("粘贴正在读的文章、论文或文档…")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 8) {
                    Text("\(documentContext.count) / \(DocumentContextRepository.maxStoredCharacters) 字符")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(isImportingPDF ? "导入中…" : "从 PDF 导入") {
                        importPDF()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isImportingPDF)

                    Button("从剪贴板填入") {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            documentContext = String(text.prefix(DocumentContextRepository.maxStoredCharacters))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("清空") {
                        documentContextLoaded = true
                        documentContextError = nil
                        documentContext = ""
                        DocumentContextRepository.clear(accountID: accountStore.activeID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("保存") {
                        DocumentContextRepository.write(documentContext, accountID: accountStore.activeID)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!documentContextLoaded)
                }

                if let documentContextError {
                    Text(documentContextError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("翻译时使用这篇文档作为上下文", isOn: $store.settings.useDocumentContext)

                Stepper(
                    "最多发送：\(store.settings.documentContextMaxChars) 字符",
                    value: $store.settings.documentContextMaxChars,
                    in: 1000...12000,
                    step: 1000
                )

                Text("文档上下文只保存在本机，按账户隔离；上下文文件使用 AES-GCM 加密，只有主动翻译时才会把与选区相关的一段发送给你配置的服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let pdfImportMessage {
                    Text(pdfImportMessage)
                        .font(.caption)
                        .foregroundStyle(pdfImportMessage.hasPrefix("已导入") ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                STSectionHeader(title: "整篇文章上下文", systemImage: "doc.text")
            }

            Section {
                Text("安装 Anki 与 AnkiConnect 插件（代码 2055492159），保持 Anki 运行，就能把收藏的单词/句子直接加到牌组。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                fieldRow("AnkiConnect 地址") {
                    TextField("http://127.0.0.1:8765", text: $store.settings.ankiURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                fieldRow("牌组与笔记类型") {
                    HStack(spacing: 8) {
                        TextField("Default", text: $store.settings.ankiDeck)
                            .textFieldStyle(.roundedBorder)
                        TextField("Basic", text: $store.settings.ankiModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(width: 280)
                }

                fieldRow("标签") {
                    TextField("SelectionTranslator", text: $store.settings.ankiTags)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                HStack(spacing: 8) {
                    Button(isTestingAnki ? "测试中…" : "测试 AnkiConnect") {
                        testAnki()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingAnki)

                    Button(isExportingAnki ? "发送中…" : "发送收藏到 Anki") {
                        sendFavoritesToAnki()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExportingAnki)

                    if let ankiHealth {
                        STStatusBadge(
                            text: ankiHealth.hasPrefix("已连接") ? "已连接" : "未连接",
                            tone: ankiHealth.hasPrefix("已连接") ? .success : .danger
                        )
                    }
                }

                if let ankiHealth {
                    Text(ankiHealth)
                        .font(.caption)
                        .foregroundStyle(ankiHealth.hasPrefix("已连接") ? Color.secondary : Color.red)
                }

                if let ankiExportMessage {
                    Text(ankiExportMessage)
                        .font(.caption)
                        .foregroundStyle(ankiExportMessage.hasPrefix("已发送") ? Color.secondary : Color.red)
                }
            } header: {
                STSectionHeader(title: "Anki 生词本", systemImage: "rectangle.stack")
            }
        }
        .stFormSurface()
    }

    // MARK: - Shortcuts

    private var shortcutsTab: some View {
        Form {
            Section {
                HotKeyRow(title: "划词翻译", binding: $store.settings.hotkeys.selection)
                HotKeyRow(title: "剪贴板翻译", binding: $store.settings.hotkeys.clipboard)
                HotKeyRow(title: "输入翻译", binding: $store.settings.hotkeys.input)
                HotKeyRow(title: "截图 OCR", binding: $store.settings.hotkeys.ocr)
                HotKeyRow(title: "静默 OCR", binding: $store.settings.hotkeys.silentOCR)
                HotKeyRow(title: "历史与生词本", binding: $store.settings.hotkeys.library)
                HotKeyRow(title: "打开设置", binding: $store.settings.hotkeys.settings)
            } header: {
                STSectionHeader(title: "全局快捷键", systemImage: "command")
            }

            Section {
                Text("快捷键至少需要一个修饰键（⌘/⌥/⌃/⇧）。冲突的组合会被跳过，并在系统日志里记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("恢复默认快捷键") {
                    store.settings.hotkeys = .default
                }
                .buttonStyle(.bordered)
            } header: {
                STSectionHeader(title: "默认与冲突", systemImage: "arrow.counterclockwise")
            }
        }
        .stFormSurface()
    }

    // MARK: - Data & permissions

    private var dataTab: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Button {
                        onOpenLibrary()
                    } label: {
                        Label("历史与生词本", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onOpenInput()
                    } label: {
                        Label("输入翻译", systemImage: "keyboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onRunOCR()
                    } label: {
                        Label("截图 OCR", systemImage: "viewfinder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
            } header: {
                STSectionHeader(title: "工具", systemImage: "wrench.and.screwdriver")
            }

            Section {
                if store.settings.excludedBundleIDs.isEmpty {
                    Text("目前没有排除的 App。终端、密码框和某些 Electron App 可以在下面加入排除名单。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(store.settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            Text(appDisplayName(for: bundleID))
                                .font(.system(size: 12))
                            Text(bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                store.settings.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 16)
                            }
                            .buttonStyle(.borderless)
                            .help("从这个排除名单移除")
                        }
                    }
                }

                Menu {
                    if addableApps.isEmpty {
                        Text("没有可添加的前台 App")
                    } else {
                        ForEach(addableApps) { app in
                            Button(app.name) {
                                guard !store.settings.excludedBundleIDs.contains(app.id) else { return }
                                store.settings.excludedBundleIDs.append(app.id)
                            }
                        }
                    }
                } label: {
                    Label("添加正在运行的 App", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("排除后鼠标划词不出现“译”图标，快捷键也会提示已排除；剪贴板、输入翻译和截图 OCR 不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                STSectionHeader(title: "按 App 排除", systemImage: "app.dashed")
            }

            Section {
                HStack(spacing: 8) {
                    Button("检查更新") { onCheckForUpdates() }
                        .buttonStyle(.bordered)

                    Text("由 Sparkle 检查、验证 EdDSA 签名并安装；自动检查每天最多一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("更新源：GitHub appcast；不会上传翻译内容或本地历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                STSectionHeader(title: "更新", systemImage: "arrow.triangle.2.circlepath")
            }

            Section {
                HStack(spacing: 8) {
                    Button {
                        onOpenPrivacy()
                    } label: {
                        Label("查看隐私说明", systemImage: "lock.shield")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onShowOnboarding()
                    } label: {
                        Label("重新查看首次引导", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }

                Text("历史、生词本和 API Key 默认只在本机；只有主动翻译时才会把文字发送到你配置的模型服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                STSectionHeader(title: "隐私与引导", systemImage: "hand.raised")
            }

            Section {
                HStack(spacing: 10) {
                    Button("清空翻译缓存") {
                        TranslationCache.shared.clear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("缓存只存在内存里，退出 App 自动消失。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            } header: {
                STSectionHeader(title: "缓存", systemImage: "memorychip")
            }

            Section {
                LabeledContent("辅助功能") {
                    STStatusBadge(
                        text: accessibilityTrusted ? "已授权" : "未授权",
                        tone: accessibilityTrusted ? .success : .warning
                    )
                }

                LabeledContent("屏幕录制") {
                    STStatusBadge(
                        text: screenRecordingTrusted ? "已授权" : "未授权",
                        tone: screenRecordingTrusted ? .success : .warning
                    )
                }

                Text("\(store.settings.hotkeys.selection.display) 需要辅助功能；\(store.settings.hotkeys.clipboard.display)、\(store.settings.hotkeys.input.display) 不需要。\(store.settings.hotkeys.ocr.display)、\(store.settings.hotkeys.silentOCR.display) 需要屏幕录制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("打开辅助功能设置") {
                        Permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Button("打开屏幕录制设置") {
                        Permissions.openScreenRecordingSettings()
                    }
                    .buttonStyle(.bordered)

                    if !screenRecordingTrusted {
                        Button("请求屏幕录制权限") {
                            let granted = Permissions.requestScreenRecordingPermission()
                            screenRecordingTrusted = granted || Permissions.hasScreenRecordingPermission()
                            if !screenRecordingTrusted {
                                Permissions.openScreenRecordingSettings()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("重新检查") {
                        accessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
                        screenRecordingTrusted = Permissions.hasScreenRecordingPermission()
                    }
                    .buttonStyle(.borderless)
                }

                Text("授权后 App 会直接使用系统能力，不重复弹窗；如果状态没变，重启一次 App。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                STSectionHeader(title: "权限", systemImage: "lock.shield")
            }
        }
        .stFormSurface()
    }

    // MARK: - Actions

    private var addableApps: [RunningAppOption] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let excluded = Set(store.settings.excludedBundleIDs)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  bundleID != ownBundleID,
                  !excluded.contains(bundleID),
                  app.activationPolicy == .regular,
                  seen.insert(bundleID).inserted else { return nil }
            return RunningAppOption(
                id: bundleID,
                name: app.localizedName ?? bundleID
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func appDisplayName(for bundleID: String) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName ?? bundleID
    }

    private func fieldRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 16)
            content()
                .labelsHidden()
        }
    }

    private func apply(_ preset: ProviderPreset) {
        store.settings.providerName = preset.name
        store.settings.apiBaseURL = preset.baseURL
        store.settings.model = preset.model
        health = nil
    }

    private func loadDocumentContext() {
        documentSaveTask?.cancel()
        switch DocumentContextRepository.loadResult(accountID: accountStore.activeID) {
        case .loaded(let text):
            documentContextLoaded = true
            documentContextError = nil
            documentContext = text
        case .empty:
            documentContextLoaded = true
            documentContextError = nil
            documentContext = ""
        case .unavailable:
            // Keep the editor read-only for persistence until the key is
            // available again; do not schedule a save over the encrypted file.
            documentContextLoaded = false
            documentContext = ""
            documentContextError = "无法读取已加密的文档上下文。请检查钥匙串访问权限后重新打开设置；为避免覆盖原文件，自动保存已暂停。"
        }
    }

    private func importPDF() {
        let panel = NSOpenPanel()
        panel.title = "选择要作为上下文的 PDF"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.isImportingPDF = true
            self.pdfImportMessage = nil
            Task { @MainActor in
                do {
                    let text = try await Task.detached(priority: .userInitiated) {
                        try PDFTextExtractor.extract(
                            url: url,
                            maxCharacters: DocumentContextRepository.maxStoredCharacters
                        )
                    }.value
                    self.documentContext = text
                    DocumentContextRepository.write(text, accountID: self.accountStore.activeID)
                    self.pdfImportMessage = "已导入 \(text.count) 字符。翻译时只会发送与选区相关的一段。"
                } catch {
                    self.pdfImportMessage = "PDF 导入失败：\(error.localizedDescription)"
                }
                self.isImportingPDF = false
            }
        }
    }

    private func testAnki() {
        isTestingAnki = true
        ankiHealth = nil
        let url = store.settings.ankiURL
        Task {
            do {
                let message = try await AnkiConnectService.test(urlString: url)
                await MainActor.run {
                    ankiHealth = message
                    isTestingAnki = false
                }
            } catch {
                await MainActor.run {
                    ankiHealth = error.localizedDescription
                    isTestingAnki = false
                }
            }
        }
    }

    private func sendFavoritesToAnki() {
        isExportingAnki = true
        ankiExportMessage = nil
        let settings = store.settings
        let accountID = accountStore.activeID
        Task {
            do {
                let favorites = try await HistoryStore.shared.records(
                    accountID: accountID,
                    favoritesOnly: true,
                    limit: 100_000
                )
                guard !favorites.isEmpty else {
                    await MainActor.run {
                        ankiExportMessage = "生词本为空，先收藏几条再发送。"
                        isExportingAnki = false
                    }
                    return
                }
                let count = try await AnkiConnectService.addNotes(
                    records: favorites,
                    urlString: settings.ankiURL,
                    deck: settings.ankiDeck,
                    model: settings.ankiModel,
                    tags: settings.ankiTags
                )
                await MainActor.run {
                    ankiExportMessage = "已发送 \(count) 条到 Anki。"
                    isExportingAnki = false
                }
            } catch {
                await MainActor.run {
                    ankiExportMessage = error.localizedDescription
                    isExportingAnki = false
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        health = nil
        Task {
            let result = await ProviderHealth.check(
                baseURL: store.settings.apiBaseURL,
                apiKey: apiKey,
                model: store.settings.model
            )
            await MainActor.run {
                health = result
                isTesting = false
            }
        }
    }

    private func refreshOllama() {
        Task { @MainActor in
            guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let tags = try JSONDecoder().decode(OllamaTags.self, from: data)
                ollamaModels = tags.models.map(\.name)
            } catch {
                ollamaModels = []
            }
        }
    }

    private func refreshProfileStats() {
        let accountID = accountStore.activeID
        Task {
            let stats = (try? await HistoryStore.shared.stats(accountID: accountID)) ?? HistoryStats()
            await MainActor.run {
                guard accountStore.activeID == accountID else { return }
                profileStats = stats
            }
        }
    }
}

private struct HotKeyRow: View {
    let title: String
    @Binding var binding: HotKeyBinding

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 118, alignment: .leading)

            Picker("", selection: $binding.key) {
                ForEach(HotKeyKey.allCases.sorted { $0.displayName < $1.displayName }, id: \.rawValue) { key in
                    Text(key.displayName).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 62)

            modifierButton("⌘", active: binding.command) { binding.command.toggle() }
            modifierButton("⌥", active: binding.option) { binding.option.toggle() }
            modifierButton("⌃", active: binding.control) { binding.control.toggle() }
            modifierButton("⇧", active: binding.shift) { binding.shift.toggle() }

            Spacer()

            Text(binding.display)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func modifierButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            active ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
    }
}
