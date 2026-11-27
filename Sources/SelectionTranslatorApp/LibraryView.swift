import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var records: [QueryRecord] = []
    @Published var stats = HistoryStats()
    @Published var search = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    private var currentAccountID: UUID?
    private var reloadGeneration = 0

    func reload(accountID: UUID, favoritesOnly: Bool, search: String) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        currentAccountID = accountID
        isLoading = true
        errorMessage = nil
        do {
            async let recordsTask = HistoryStore.shared.records(
                accountID: accountID,
                search: search,
                favoritesOnly: favoritesOnly
            )
            async let statsTask = HistoryStore.shared.stats(accountID: accountID)
            let (loadedRecords, loadedStats) = try await (recordsTask, statsTask)
            guard generation == reloadGeneration else { return }
            records = loadedRecords
            stats = loadedStats
        } catch {
            guard generation == reloadGeneration else { return }
            errorMessage = error.localizedDescription
        }
        if generation == reloadGeneration {
            isLoading = false
        }
    }

    func toggleFavorite(_ record: QueryRecord) async {
        do {
            try await HistoryStore.shared.setFavorite(id: record.id, isFavorite: !record.isFavorite)
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index].isFavorite.toggle()
            }
            if let accountID = currentAccountID ?? records.first?.accountID {
                stats = try await HistoryStore.shared.stats(accountID: accountID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ record: QueryRecord) async {
        do {
            try await HistoryStore.shared.delete(id: record.id)
            records.removeAll { $0.id == record.id }
            if let accountID = currentAccountID ?? records.first?.accountID {
                stats = try await HistoryStore.shared.stats(accountID: accountID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportJSONL(accountID: UUID, to url: URL) async {
        do {
            try await HistoryStore.shared.exportJSONL(accountID: accountID, to: url)
            noticeMessage = "已导出 JSONL。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCSV(accountID: UUID, to url: URL) async {
        do {
            try await HistoryStore.shared.exportCSV(accountID: accountID, to: url)
            noticeMessage = "已导出 CSV，可直接导入表格或 Anki。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportToAnki(accountID: UUID, settings: AppSettings) async {
        guard await HistoryStore.shared.encryptionAvailable else {
            errorMessage = HistoryCipherError.keyUnavailable.localizedDescription
            return
        }
        do {
            let favorites = try await HistoryStore.shared.records(
                accountID: accountID,
                favoritesOnly: true,
                limit: 100_000
            )
            guard !favorites.isEmpty else {
                noticeMessage = "生词本还是空的，先点浮窗里的星标收藏几条。"
                return
            }
            let count = try await AnkiConnectService.addNotes(
                records: favorites,
                urlString: settings.ankiURL,
                deck: settings.ankiDeck,
                model: settings.ankiModel,
                tags: settings.ankiTags
            )
            noticeMessage = "已向 Anki 添加 \(count) 条（重复项会自动跳过）。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LibraryView: View {
    @ObservedObject var accountStore: LocalAccountStore
    @ObservedObject var settingsStore: SettingsStore
    @StateObject private var model = LibraryViewModel()
    @State private var selectedTab = 0
    @State private var showingNewAccount = false
    @State private var newAccountName = ""
    @Environment(\.stAppearance) private var stAppearance

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            filterBar
            Divider().opacity(0.35)

            if let error = model.errorMessage {
                notice(error, tone: .danger)
            }
            if let successMessage = model.noticeMessage {
                notice(successMessage, tone: .success)
            }

            if model.records.isEmpty, !model.isLoading {
                emptyState
            } else {
                recordsList
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(STWindowBackdrop(appearance: settingsStore.settings.appearance))
        .stAppearance(settingsStore.settings.appearance)
        .task(id: reloadKey) {
            // Typing in the search field should not queue a full decrypt/scan
            // for every keystroke. The task identity already cancels the
            // previous wait when the query changes.
            if !model.search.isEmpty {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            await model.reload(
                accountID: accountStore.activeID,
                favoritesOnly: selectedTab == 1,
                search: model.search
            )
        }
        .sheet(isPresented: $showingNewAccount) {
            VStack(alignment: .leading, spacing: 14) {
                Text("新建本地账户")
                    .font(.system(size: 17, weight: .semibold))
                Text("账户和历史只保存在本机，不会上传云端。")
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

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: accountStore.activeProfile.avatarSymbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)
            .overlay {
                Circle().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(accountStore.activeProfile.name)
                    .font(.system(size: 15, weight: .semibold))
                Text("本地账户 · 数据只保存在这台 Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Picker("账户", selection: Binding(
                get: { accountStore.activeID },
                set: { accountStore.switchTo($0) }
            )) {
                ForEach(accountStore.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Button {
                newAccountName = ""
                showingNewAccount = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help("新建本地账户")

            Spacer()

            Menu {
                Button("导出 JSONL") { exportJSONL() }
                Button("导出 CSV") { exportCSV() }
                Divider()
                Button("发送收藏到 Anki") {
                    Task {
                        await model.exportToAnki(
                            accountID: accountStore.activeID,
                            settings: settingsStore.settings
                        )
                    }
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.records.isEmpty && model.stats.favorites == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(STHeaderSurface())
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                TextField("搜索原文、译文、上下文、来源 App", text: $model.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !model.search.isEmpty {
                    Button {
                        model.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                if stAppearance == .liquidGlass {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.10), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        stAppearance == .liquidGlass
                            ? Color.white.opacity(0.13)
                            : Color.primary.opacity(0.07),
                        lineWidth: 0.8
                    )
            }
            .frame(maxWidth: 360)

            Picker("范围", selection: $selectedTab) {
                Text("历史").tag(0)
                Text("生词本").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            Spacer()

            if model.isLoading {
                ProgressView().controlSize(.small)
            }

            Text(model.stats.summary)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var recordsList: some View {
        List {
            ForEach(model.records) { record in
                QueryRecordRow(
                    record: record,
                    onToggleFavorite: {
                        Task { await model.toggleFavorite(record) }
                    },
                    onDelete: {
                        Task { await model.delete(record) }
                    }
                )
                .listRowInsets(EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14))
                .listRowSeparatorTint(Color.primary.opacity(0.06))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.045))
                Image(systemName: selectedTab == 1 ? "star" : "clock.arrow.circlepath")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)

            Text(selectedTab == 1 ? "还没有收藏的单词或句子" : "还没有翻译记录")
                .font(.system(size: 15, weight: .semibold))
            Text(selectedTab == 1 ? "翻译完成后，点浮窗里的星标即可收藏。" : "按 ⌥D / ⌥V / ⌥O 翻译一次，就会出现在这里。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func notice(_ message: String, tone: STStatusTone) -> some View {
        HStack(spacing: 7) {
            Image(systemName: tone.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tone.color)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(tone.color.opacity(0.055))
    }

    private var reloadKey: String {
        "\(accountStore.activeID.uuidString)|\(selectedTab)|\(model.search)"
    }

    private func exportJSONL() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "selection-history.jsonl"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.exportJSONL(accountID: accountStore.activeID, to: url)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "selection-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.exportCSV(accountID: accountStore.activeID, to: url)
        }
    }
}

private struct QueryRecordRow: View {
    let record: QueryRecord
    var onToggleFavorite: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(record.sourceText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(3)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Button(action: onToggleFavorite) {
                    Image(systemName: record.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(record.isFavorite ? Color.yellow : Color.secondary.opacity(0.75))
                }
                .buttonStyle(.borderless)
                .help(record.isFavorite ? "取消收藏" : "收藏到生词本")
            }

            Text(record.translatedText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(6)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                metadata(record.appName.isEmpty ? "未知来源" : record.appName)
                if sourceLabel != record.appName {
                    dot
                    metadata(sourceLabel)
                }
                dot
                metadata(record.engine)
                dot
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    rowButton("doc", help: "复制原文") { copy(record.sourceText) }
                    rowButton("doc.on.doc", help: "复制译文") { copy(record.translatedText) }
                    rowButton("speaker.wave.2", help: "朗读原文") { SpeechService.shared.speak(record.sourceText) }
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .frame(width: 22, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help("删除这条记录")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)

            if !record.context.isEmpty {
                DisclosureGroup {
                    Text(record.context)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9))
                        Text("上下文")
                            .font(.system(size: 10, weight: .medium))
                        Text("\(record.context.count) 字符")
                            .font(.system(size: 9, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var dot: some View {
        Text("·")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
    }

    private func metadata(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var sourceLabel: String {
        CaptureSource(rawValue: record.sourceKind)?.displayName ?? record.sourceKind
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
final class LibraryWindowController {
    private var window: NSWindow?

    func show(accountStore: LocalAccountStore, settingsStore: SettingsStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = LibraryView(accountStore: accountStore, settingsStore: settingsStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "历史与生词本"
        window.minSize = NSSize(width: 780, height: 560)
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
