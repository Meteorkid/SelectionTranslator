import Foundation
import AppKit
import ApplicationServices

enum AX {
    /// AX is a cross-process API. Without a short messaging timeout a single
    /// unresponsive app can block a selection read for several seconds.
    static let messagingTimeout: Float = 0.20

    /// Chromium exposes its accessibility tree only after a client opts in
    /// with AXEnhancedUserInterface. Electron responds to AXManualAccessibility.
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.dev",
        "com.brave.Browser.nightly",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.pushplaylabs.sidekick"
    ]

    static func copy<T>(_ element: AXUIElement, _ attribute: String, as type: T.Type = T.self) -> T? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return value as? T
    }

    static func applicationElement(for app: NSRunningApplication) -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    /// Preparing this before the user selects text gives Chromium/Electron
    /// time to build its lazily-created accessibility tree.
    static func prepareAccessibility(for app: NSRunningApplication?) {
        guard let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              AXIsProcessTrusted() else {
            return
        }

        let appElement = applicationElement(for: app)
        let manual = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        if manual != .success, isChromiumBrowser(app) {
            AXUIElementSetAttributeValue(
                appElement,
                "AXEnhancedUserInterface" as CFString,
                kCFBooleanTrue
            )
        }
    }

    static func isChromiumBrowser(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return chromiumBundleIDs.contains(bundleID)
    }

    static func focusedElement() -> AXUIElement? {
        // Querying the frontmost app directly is more reliable than the system-wide
        // element on recent macOS versions, and it avoids -25204 "cannot complete".
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = applicationElement(for: app)
            if let focused: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute, as: AXUIElement.self) {
                return focused
            }
            if let window: AXUIElement = copy(appElement, kAXFocusedWindowAttribute, as: AXUIElement.self),
               let focused: AXUIElement = copy(window, kAXFocusedUIElementAttribute, as: AXUIElement.self) {
                return focused
            }
            // Chromium may omit the root focused-element attribute until its tree is ready.
            if isChromiumBrowser(app), let focused = focusedTextElement(in: appElement) {
                return focused
            }
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        guard let systemFocused: AXUIElement = copy(
            system,
            kAXFocusedUIElementAttribute,
            as: AXUIElement.self
        ) else {
            return nil
        }

        // A system-wide query can return a focused element owned by another
        // process, such as our own non-activating panel. Reject it instead of
        // translating a stale selection from the wrong app.
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            var pid: pid_t = 0
            guard AXUIElementGetPid(systemFocused, &pid) == .success,
                  pid == frontApp.processIdentifier else {
                return nil
            }
        }
        return systemFocused
    }

    static func isSecureTextField(_ element: AXUIElement) -> Bool {
        let subrole: String? = copy(element, kAXSubroleAttribute)
        return subrole == kAXSecureTextFieldSubrole
    }

    /// A bounded fallback for Chromium, whose focused element is sometimes
    /// missing from the application root. Only an explicitly focused text
    /// field is accepted; never guess by text or pick the first editor.
    private static func focusedTextElement(in app: AXUIElement) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(0.12)
        var remaining = 100

        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 18, remaining > 0, Date() < deadline else { return nil }
            remaining -= 1

            let role: String? = copy(element, kAXRoleAttribute)
            if let role, [kAXTextAreaRole, kAXTextFieldRole].contains(role),
               let focused: Bool = copy(element, kAXFocusedAttribute), focused {
                return element
            }
            for child in copy(element, kAXChildrenAttribute, as: [AXUIElement].self) ?? [] {
                if let found = find(child, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }

        return find(app, depth: 0)
    }

    static func selectedText(of element: AXUIElement) -> String? {
        if let text: String = copy(element, kAXSelectedTextAttribute),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let text = selectedTextMarkerText(of: element),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let range = selectedRange(of: element), range.length > 0 {
            return string(for: range, in: element)
        }
        return nil
    }

    static func selectedRange(
        of element: AXUIElement,
        matching selectedText: String? = nil
    ) -> CFRange? {
        if let range = selectedRangeFromAttribute(of: element) {
            return range
        }
        guard let selectedText,
              let fullText = fullText(of: element),
              let range = TextRangeResolver.firstRange(
                  of: selectedText,
                  in: fullText
              ) else {
            return nil
        }
        return CFRange(location: range.location, length: range.length)
    }

    private static func selectedRangeFromAttribute(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = copy(
            element,
            kAXSelectedTextRangeAttribute,
            as: AXValue.self
        ) else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    /// WebKit/Chromium apps may expose only `AXSelectedTextMarkerRange`.
    private static func selectedTextMarkerText(of element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRange
        ) == .success, let markerRange else {
            return nil
        }
        return string(for: markerRange, in: element)
    }

    private static func string(for markerRange: CFTypeRef, in element: AXUIElement) -> String? {
        for attribute in [
            "AXStringForTextMarkerRange",
            "AXAttributedStringForTextMarkerRange"
        ] {
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element,
                attribute as CFString,
                markerRange,
                &value
            ) == .success, let value else {
                continue
            }
            if let text = value as? String, !text.isEmpty {
                return text
            }
            if let text = value as? NSAttributedString, text.length > 0 {
                return text.string
            }
        }
        return nil
    }

    static func string(for range: CFRange, in element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &value
        )
        guard result == .success else { return nil }
        return value as? String
    }

    static func fullText(of element: AXUIElement) -> String? {
        if let value: String = copy(element, kAXValueAttribute), !value.isEmpty {
            return value
        }
        return textMarkerText(of: element)
    }

    /// Chromium does not expose the page text through AXValue. It does expose
    /// the page through AX text markers, which can be converted back to text.
    /// This keeps the context-first promise working for browser selections.
    private static func textMarkerText(of element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var markerRange: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXTextMarkerRangeForUIElement" as CFString,
            element,
            &markerRange
        ) == .success, let markerRange else {
            return nil
        }

        for attribute in ["AXAttributedStringForTextMarkerRange", "AXStringForTextMarkerRange"] {
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element,
                attribute as CFString,
                markerRange,
                &value
            ) == .success, let value else {
                continue
            }
            if let text = value as? String, !text.isEmpty {
                return text
            }
            if let text = value as? NSAttributedString, text.length > 0 {
                return text.string
            }
        }
        return nil
    }

    /// Returns the focused element's frame in AX screen coordinates.
    /// Some apps do not expose position or size; callers treat that as
    /// "cannot validate" rather than rejecting a valid selection.
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copy(
            element,
            kAXPositionAttribute,
            as: AXValue.self
        ),
        let sizeValue: AXValue = copy(
            element,
            kAXSizeAttribute,
            as: AXValue.self
        ) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func windowTitle(of element: AXUIElement) -> String? {
        if let title: String = copy(element, kAXTitleAttribute) {
            return title
        }
        if let window: AXUIElement = copy(element, kAXFocusedWindowAttribute, as: AXUIElement.self) {
            return copy(window, kAXTitleAttribute, as: String.self)
        }
        return nil
    }
}
