import AppKit

final class AnnotationState {
    enum Tool: String, CaseIterable {
        case draw, arrow, line, square, circle, text, highlight, blackboard, callout

        var displayName: String {
            switch self {
            case .draw: return "Draw"
            case .arrow: return "Arrow"
            case .line: return "Line"
            case .square: return "Square"
            case .circle: return "Circle"
            case .text: return "Text"
            case .highlight: return "Highlight"
            case .blackboard: return "Blackboard"
            case .callout: return "Callout"
            }
        }
    }

    struct StrokePoint {
        let x: CGFloat
        let y: CGFloat
    }

    enum Action {
        case draw(points: [StrokePoint], color: NSColor, lineWidth: CGFloat)
        case arrow(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor, lineWidth: CGFloat)
        case line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor, lineWidth: CGFloat)
        case square(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor, lineWidth: CGFloat)
        case circle(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor, lineWidth: CGFloat)
        case text(text: String, x: CGFloat, y: CGFloat, fontSize: CGFloat, color: NSColor)
        case highlight(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: NSColor)
        case blackboard(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
        case callout(x: CGFloat, y: CGFloat, n: Int, color: NSColor, radius: CGFloat)
    }

    var tool: Tool = .draw { didSet { notifyPreviewChange() } }
    var color: NSColor = .systemRed { didSet { persist(); notifyPreviewChange() } }
    var lineWidth: CGFloat = 3 { didSet { persist(); notifyPreviewChange() } }
    var fontSize: CGFloat = 18 { didSet { notifyPreviewChange() } }

    private(set) var actions: [Action] = []
    private var redoStack: [Action] = []

    /// Incremented whenever committed actions change (add/undo/redo/clear).
    /// The overlay uses this to decide whether to rebuild its cached render.
    private(set) var committedVersion: Int = 0

    /// Called for any state change — used by the control panel to sync UI.
    var onChange: (() -> Void)?

    /// Called only when the committed action list changes.
    /// Used by the overlay to invalidate its cached render.
    var onActionListChange: (() -> Void)?

    init() {
        restore()
    }

    func add(_ action: Action) {
        actions.append(action)
        redoStack.removeAll()
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func undo() {
        guard let last = actions.popLast() else { return }
        redoStack.append(last)
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        actions.append(last)
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func clear() {
        actions.removeAll()
        redoStack.removeAll()
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func hasActions() -> Bool { !actions.isEmpty }

    func calloutCount() -> Int {
        actions.reduce(0) { partial, action in
            if case .callout = action { return partial + 1 }
            return partial
        }
    }

    func increaseSize() {
        if tool == .text { fontSize = min(fontSize + 2, 72) }
        else { lineWidth = min(lineWidth + 1, 20) }
    }

    func decreaseSize() {
        if tool == .text { fontSize = max(fontSize - 2, 8) }
        else { lineWidth = max(lineWidth - 1, 1) }
    }

    /// Called for preview-only changes (tool, color, width, fontSize).
    /// Does NOT increment committedVersion — no cache rebuild needed.
    private func notifyPreviewChange() {
        onChange?()
    }

    private func persist() {
        if let rgb = color.usingColorSpace(.deviceRGB) {
            UserDefaults.standard.set([rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent], forKey: "annotate_color")
        }
        UserDefaults.standard.set(lineWidth, forKey: "annotate_lineWidth")
    }

    private func restore() {
        if let comps = UserDefaults.standard.array(forKey: "annotate_color") as? [CGFloat], comps.count == 4 {
            color = NSColor(calibratedRed: comps[0], green: comps[1], blue: comps[2], alpha: comps[3])
        }
        let storedLineWidth = UserDefaults.standard.double(forKey: "annotate_lineWidth")
        if storedLineWidth > 0 { lineWidth = storedLineWidth }
    }
}
