import SwiftUI
import AppKit

@main
struct SelectionTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("划词翻译", systemImage: "character.bubble") {
            Button("划词翻译（\(appState.settingsStore.settings.hotkeys.selection.display)）") {
                appState.translateSelection()
            }
            Button("剪贴板翻译（\(appState.settingsStore.settings.hotkeys.clipboard.display)）") {
                appState.translateClipboard()
            }
            Button("输入翻译…（\(appState.settingsStore.settings.hotkeys.input.display)）") {
                appState.openInput()
            }
            Button("截图 OCR（\(appState.settingsStore.settings.hotkeys.ocr.display)）") {
                appState.translateOCR()
            }
            Button("静默 OCR（\(appState.settingsStore.settings.hotkeys.silentOCR.display)）") {
                appState.copyOCRText()
            }
            Divider()
            Button("历史与生词本…（\(appState.settingsStore.settings.hotkeys.library.display)）") {
                appState.openLibrary()
            }
            Button("设置…（\(appState.settingsStore.settings.hotkeys.settings.display)）") {
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
        .menuBarExtraStyle(.menu)
    }
}
