import Foundation
import Carbon.HIToolbox
import os.log

/// Registers global hotkeys through Carbon. Carbon hotkeys do not require
/// Accessibility permission, so clipboard/input/OCR modes work before the user grants it.
final class HotKeyManager {
    private let log = Logger(subsystem: "com.meteor.SelectionTranslator", category: "hotkey")
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    var actionHandler: ((HotKeyAction) -> Void)?

    private static let signature = OSType(0x53544C52) // STLR

    func register(_ settings: HotKeySettings) {
        unregisterAll()
        installHandlerIfNeeded()

        var used = Set<String>()
        for action in HotKeyAction.allCases {
            let binding = settings.binding(for: action)
            guard binding.hasModifier else {
                log.info("Skip hotkey \(action.title, privacy: .public): no modifier")
                continue
            }
            let signatureKey = "\(binding.carbonModifiers)-\(binding.key.rawValue)"
            guard used.insert(signatureKey).inserted else {
                log.info("Skip duplicate hotkey \(action.title, privacy: .public): \(binding.display, privacy: .public)")
                continue
            }
            register(binding: binding, id: action.rawValue, title: action.title)
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let action = HotKeyAction(rawValue: hotKeyID.id) else {
                    return status
                }

                DispatchQueue.main.async {
                    manager.actionHandler?(action)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        log.info("InstallEventHandler status: \(handlerStatus)")
    }

    private func register(binding: HotKeyBinding, id: UInt32, title: String) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.key.rawValue,
            binding.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if let ref, status == noErr {
            hotKeyRefs.append(ref)
        }
        log.info("RegisterEventHotKey \(title, privacy: .public) \(binding.display, privacy: .public) status: \(status)")
    }

    private func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
