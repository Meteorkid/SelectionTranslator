import SwiftUI
import AppKit

@main
struct SelectionTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("划词翻译", systemImage: "character.bubble") {
            MenuBarContent(appState: appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu items read the current hotkey display strings. Observing the settings
/// store directly (instead of relying on the scene to observe AppState) keeps
/// the menu labels correct after the user edits a shortcut.
private struct MenuBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsStore

    init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settingsStore
    }

    var body: some View {
        Button("划词翻译（\(settings.settings.hotkeys.selection.display)）") {
            appState.translateSelection()
        }
        Button("剪贴板翻译（\(settings.settings.hotkeys.clipboard.display)）") {
            appState.translateClipboard()
        }
        Button("输入翻译…（\(settings.settings.hotkeys.input.display)）") {
            appState.openInput()
        }
        Button("截图 OCR（\(settings.settings.hotkeys.ocr.display)）") {
            appState.translateOCR()
        }
        Button("静默 OCR（\(settings.settings.hotkeys.silentOCR.display)）") {
            appState.copyOCRText()
        }
        Divider()
        Button("历史与生词本…（\(settings.settings.hotkeys.library.display)）") {
            appState.openLibrary()
        }
        Button("设置…（\(settings.settings.hotkeys.settings.display)）") {
            appState.openSettings()
        }
        Button("检查更新…") {
            appState.checkForUpdates()
        }
        Divider()
        Button("退出") {
            NSApp.terminate(nil)
        }
    }
}
