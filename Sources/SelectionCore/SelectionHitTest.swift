import CoreGraphics
import Foundation

/// Guards mouse-triggered selection reads against stale AX selections.
///
/// Accessibility can still report the last selected text after the user clicks
/// a toolbar, a sidebar, or another non-text part of the same window. MoePeek
/// solves this by checking the release point against the focused element's
/// bounds; this helper keeps that policy small and unit-testable.
enum SelectionHitTest {
    static let tolerance: CGFloat = 20

    /// Cocoa mouse coordinates grow upward from the primary screen's bottom;
    /// AX position/size coordinates grow downward from its top.
    static func accessibilityPoint(
        fromCocoa point: CGPoint,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func isPoint(
        _ point: CGPoint,
        near frame: CGRect,
        tolerance: CGFloat = tolerance
    ) -> Bool {
        frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}
