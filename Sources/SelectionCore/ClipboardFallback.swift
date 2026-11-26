import AppKit
import Carbon.HIToolbox
import CoreGraphics

enum ClipboardFallback {
    /// Ask clipboard managers not to record the restored snapshot.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Sends ⌘C to the target app, reads only a real text copy, and puts the
    /// original pasteboard back. Unlike a "clear then sleep" implementation,
    /// this waits for the target app to actually change the pasteboard.
    static func copySelection(
        targetPID: pid_t? = nil,
        timeout: TimeInterval = 0.28,
        lateRestoreWindow: TimeInterval = 0.8
    ) -> String? {
        guard !IsSecureEventInputEnabled() else { return nil }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotItems(pasteboard)
        let originalChangeCount = pasteboard.changeCount

        guard postCopyCommand(to: targetPID) else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        var sawCopy = false
        repeat {
            if pasteboard.changeCount != originalChangeCount,
               pasteboard.types?.isEmpty == false {
                sawCopy = true
                break
            }
            Thread.sleep(forTimeInterval: 0.008)
        } while Date() < deadline

        guard sawCopy else {
            // A slow app may copy after our deadline. Put that copy back only
            // when the change count proves it was the one we triggered.
            scheduleLateRestore(
                pasteboard: pasteboard,
                originalChangeCount: originalChangeCount,
                snapshot: snapshot,
                after: lateRestoreWindow
            )
            return nil
        }

        let text = copiedText(on: pasteboard)
        restore(snapshot, to: pasteboard)
        return text
    }

    private static func postCopyCommand(to processIdentifier: pid_t?) -> Bool {
        guard !IsSecureEventInputEnabled(),
              let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        else {
            return false
        }

        // Only Command is held: the user may still be holding the shortcut's
        // modifiers, and Option-Command-C is a different command in some apps.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        if let processIdentifier {
            keyDown.postToPid(processIdentifier)
            keyUp.postToPid(processIdentifier)
        } else {
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
        return true
    }

    private static func copiedText(on pasteboard: NSPasteboard) -> String? {
        // Finder's file copy also exposes filenames as text. Do not translate
        // a copied file as if it were selected prose.
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard fileURLs.isEmpty else { return nil }

        guard let string = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !string.isEmpty else {
            return nil
        }
        return string
    }

    private static func scheduleLateRestore(
        pasteboard: NSPasteboard,
        originalChangeCount: Int,
        snapshot: [[NSPasteboard.PasteboardType: Data]],
        after delay: TimeInterval
    ) {
        guard !snapshot.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            // One change after our command is the late copy. Any larger jump
            // means someone else owns the clipboard now; leave it alone.
            guard pasteboard.changeCount == originalChangeCount + 1 else { return }
            restore(snapshot, to: pasteboard)
        }
    }

    private static func snapshotItems(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private static func restore(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        items[0].setData(Data(), forType: transientType)
        pasteboard.writeObjects(items)
    }
}
