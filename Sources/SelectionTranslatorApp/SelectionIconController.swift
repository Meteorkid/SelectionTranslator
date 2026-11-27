import AppKit
import SwiftUI

private final class SelectionIconPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct SelectionIconView: View {
    var onActivate: () -> Void
    var onHoverChange: (Bool) -> Void

    var body: some View {
        Button(action: onActivate) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
                )
        }
        .buttonStyle(.plain)
        .padding(4)
        .contentShape(Circle())
        .onHover { hovering in onHoverChange(hovering) }
        .help("翻译选中的文字")
    }
}

@MainActor
final class SelectionIconController {
    private var panel: SelectionIconPanel?
    private var capture: CaptureResult?
    private var onActivate: ((CaptureResult) -> Void)?
    private var hideTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?

    func show(
        capture: CaptureResult,
        near point: NSPoint,
        hoverToTranslate: Bool,
        onActivate: @escaping (CaptureResult) -> Void
    ) {
        hide()

        self.capture = capture
        self.onActivate = onActivate

        let view = SelectionIconView(
            onActivate: { [weak self] in self?.activate() },
            onHoverChange: { [weak self] hovering in
                if hovering {
                    self?.scheduleHover(enabled: hoverToTranslate)
                } else {
                    self?.hoverTask?.cancel()
                    self?.hoverTask = nil
                }
            }
        )
        let panel = SelectionIconPanel(
            contentRect: NSRect(x: 0, y: 0, width: 42, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstMouseHostingView(rootView: view)
        self.panel = panel

        position(panel, near: point)
        panel.orderFrontRegardless()

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        hoverTask?.cancel()
        hoverTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        capture = nil
        onActivate = nil
    }

    private func scheduleHover(enabled: Bool) {
        guard enabled else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            self?.activate()
        }
    }

    private func activate() {
        guard let capture, let onActivate else { return }
        hide()
        onActivate(capture)
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: point.x + 12, y: point.y - panel.frame.height - 10)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - panel.frame.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - panel.frame.height - 4)
        }
        panel.setFrameOrigin(origin)
    }
}
