import Foundation

@main
struct SelectionProbe {
    static func main() async {
        let trusted = Permissions.isAccessibilityTrusted(prompt: false)
        print("Accessibility: \(trusted ? "granted" : "NOT granted")")
        guard trusted else {
            print("请给运行它的终端（Terminal / iTerm）授予「辅助功能」权限，然后重试。")
            return
        }

        let result = await MainActor.run {
            SelectionCaptureService.accessibilityCapture(maxContextLength: 1600)
        }
        guard let result else {
            print("没有取到选中文字。先在 Safari / Preview / Word 里选中一段文字，再运行。")
            return
        }

        print("App: \(result.appName) [\(result.bundleID ?? "-")]")
        print("Window: \(result.windowTitle ?? "-")")
        print("Source: \(result.source.rawValue)")
        print("Selected (\(result.selectedText.count) chars):")
        print(result.selectedText)
        print("Context (\(result.context.count) chars):")
        print(result.context)

        if let data = try? JSONEncoder().encode(result) {
            let url = URL(fileURLWithPath: "/tmp/selection-probe.json")
            try? data.write(to: url)
            print("JSON: \(url.path)")
        }
    }
}
