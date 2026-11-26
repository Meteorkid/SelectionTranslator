import Foundation
import AppKit
import ApplicationServices

enum AX {
    static func copy<T>(_ element: AXUIElement, _ attribute: String, as type: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return value as? T
    }

    static func focusedElement() -> AXUIElement? {
        // Querying the frontmost app directly is more reliable than the system-wide
        // element on recent macOS versions, and it avoids -25204 "cannot complete".
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if let focused: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute, as: AXUIElement.self) {
                return focused
            }
            if let window: AXUIElement = copy(appElement, kAXFocusedWindowAttribute, as: AXUIElement.self),
               let focused: AXUIElement = copy(window, kAXFocusedUIElementAttribute, as: AXUIElement.self) {
                return focused
            }
        }
        let system = AXUIElementCreateSystemWide()
        return copy(system, kAXFocusedUIElementAttribute, as: AXUIElement.self)
    }

    static func selectedText(of element: AXUIElement) -> String? {
        if let text: String = copy(element, kAXSelectedTextAttribute), !text.isEmpty {
            return text
        }
        if let range = selectedRange(of: element), range.length > 0 {
            return string(for: range, in: element)
        }
        return nil
    }

    static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = copy(element, kAXSelectedTextRangeAttribute, as: AXValue.self) else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    static func string(for range: CFRange, in element: AXUIElement) -> String? {
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
        copy(element, kAXValueAttribute, as: String.self)
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
