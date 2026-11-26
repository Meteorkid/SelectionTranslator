import AppKit
import ApplicationServices
import os.log

/// Easydict-style passive selection watcher.
///
/// It intentionally does not copy the selection: no clipboard side effects.
/// A short debounce after mouse-up lets the target app finish its selection
/// before Accessibility is queried.
@MainActor
final class MouseSelectionMonitor {
    private let log = Logger(subsystem: "com.meteor.SelectionTranslator", category: "mouse-selection")

    var onSelection: ((CaptureResult, NSPoint) -> Void)?
    var maxContextLength: Int = 1_600

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pendingTask: Task<Void, Never>?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard Permissions.isAccessibilityTrusted(prompt: false) else {
            log.info("mouse selection not started: accessibility missing")
            return
        }
        guard let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp],
            handler: { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        ) else {
            log.info("mouse selection monitor unavailable")
            return
        }
        self.globalMonitor = globalMonitor

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.hideSelection()
            return event
        }
        isRunning = true
        log.info("mouse selection monitor started")
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        hideSelection()
        isRunning = false
        log.info("mouse selection monitor stopped")
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            hideSelection()
        case .leftMouseUp:
            scheduleCapture()
        default:
            break
        }
    }

    private func scheduleCapture() {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, let self else { return }
            self.captureSelection()
        }
    }

    private func captureSelection() {
        guard isRunning else { return }
        guard Permissions.isAccessibilityTrusted(prompt: false) else { return }

        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        guard let capture = SelectionCaptureService.accessibilityCapture(
            maxContextLength: maxContextLength
        ) else {
            return
        }
        guard !capture.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        log.info("mouse selection captured app=\(capture.appName, privacy: .public) len=\(capture.selectedText.count, privacy: .public)")
        onSelection?(capture, NSEvent.mouseLocation)
    }

    private func hideSelection() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
