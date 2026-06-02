import CoreGraphics

/// Pure math for depth-based parallax: maps the pointer position to a normalized
/// "look" vector, turns each layer's parallax depth into a pixel offset, and
/// smooths motion frame-to-frame. Kept free of AppKit so it is unit-testable.
enum SceneParallax {
    /// Maps a global mouse location to a look vector in `[-1, 1]` per axis,
    /// y-up, with the screen centre as the origin.
    static func look(mouse: CGPoint, in screen: CGRect) -> CGPoint {
        guard screen.width > 0, screen.height > 0 else { return .zero }
        let nx = (mouse.x - screen.midX) / (screen.width / 2)
        let ny = (mouse.y - screen.midY) / (screen.height / 2)
        return CGPoint(x: clamp(nx), y: clamp(ny))
    }

    /// Pixel offset for a layer: it shifts *opposite* the look direction,
    /// proportionally to its parallax depth and the overall strength.
    static func offset(parallaxDepth: CGPoint, look: CGPoint, strength: CGFloat) -> CGPoint {
        CGPoint(x: -look.x * parallaxDepth.x * strength,
                y: -look.y * parallaxDepth.y * strength)
    }

    /// Exponential smoothing toward `target` (factor 0…1; higher = snappier).
    static func smoothed(_ current: CGPoint, toward target: CGPoint, factor: CGFloat) -> CGPoint {
        let f = min(max(factor, 0), 1)
        return CGPoint(x: current.x + (target.x - current.x) * f,
                       y: current.y + (target.y - current.y) * f)
    }

    /// True when two vectors are within `epsilon` on both axes (motion settled).
    static func settled(_ a: CGPoint, _ b: CGPoint, epsilon: CGFloat = 0.0005) -> Bool {
        abs(a.x - b.x) < epsilon && abs(a.y - b.y) < epsilon
    }

    private static func clamp(_ value: CGFloat) -> CGFloat { min(max(value, -1), 1) }
}
