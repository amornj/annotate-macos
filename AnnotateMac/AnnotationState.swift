import AppKit

final class AnnotationState {
    enum Tool: String, CaseIterable {
        case draw, arrow, line, square, circle, text, callout
        case triangle, pentagon, hexagon, octagon
        case select

        var displayName: String {
            switch self {
            case .draw: return "Draw"
            case .arrow: return "Arrow"
            case .line: return "Line"
            case .square: return "Square"
            case .circle: return "Circle"
            case .text: return "Text"
            case .callout: return "Callout"
            case .triangle: return "Triangle"
            case .pentagon: return "Pentagon"
            case .hexagon: return "Hexagon"
            case .octagon: return "Octagon"
            case .select: return "Select"
            }
        }
    }

    /// Background mode for whiteboard / blackboard overlay
    enum BackgroundMode: String {
        case none
        case whiteboard  // solid white background
        case blackboard   // solid dark background
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
        case callout(x: CGFloat, y: CGFloat, n: Int, color: NSColor, radius: CGFloat)
        case polygon(cx: CGFloat, cy: CGFloat, vx: CGFloat, vy: CGFloat, sides: Int, color: NSColor, lineWidth: CGFloat)
    }

    var tool: Tool = .draw { didSet { notifyPreviewChange() } }
    var backgroundMode: BackgroundMode = .none { didSet { notifyBackgroundChange() } }
    var color: NSColor = .systemRed { didSet { persist(); notifyPreviewChange() } }
    var lineWidth: CGFloat = 3 { didSet { persist(); notifyPreviewChange() } }
    var fontSize: CGFloat = 18 { didSet { notifyPreviewChange() } }

    private(set) var actions: [Action] = []
    private var redoStack: [Action] = []
    private var bulkUndoStack: [[Action]] = []

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

    /// Clears all annotations but saves a snapshot so ⌘Z can restore them in one step.
    func clearWithUndo() {
        guard !actions.isEmpty else { return }
        bulkUndoStack.append(actions)
        actions.removeAll()
        redoStack.removeAll()
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    /// Restores the most recent bulk-cleared snapshot. Call when normal undo has nothing to do.
    func undoBulkIfAvailable() {
        guard let snapshot = bulkUndoStack.popLast() else { return }
        actions = snapshot
        redoStack.removeAll()
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func hasActions() -> Bool { !actions.isEmpty }

    func remove(at index: Int) {
        guard index >= 0 && index < actions.count else { return }
        actions.remove(at: index)
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func removeMultiple(at indices: [Int]) {
        for i in indices.sorted(by: >) {
            guard i >= 0 && i < actions.count else { continue }
            actions.remove(at: i)
        }
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    func replace(at index: Int, with action: Action) {
        guard index >= 0 && index < actions.count else { return }
        actions[index] = action
        committedVersion += 1
        onActionListChange?()
        onChange?()
    }

    /// Returns the bounding rectangle of an action, including stroke padding.
    func boundingRect(for action: Action) -> CGRect {
        switch action {
        case let .draw(points, _, lineWidth):
            guard let first = points.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let pad = lineWidth / 2 + 2
            return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
        case let .arrow(x1, y1, x2, y2, _, lineWidth):
            let pad = lineWidth / 2 + 16
            return CGRect(x: min(x1,x2) - pad, y: min(y1,y2) - pad, width: abs(x2-x1) + pad*2, height: abs(y2-y1) + pad*2)
        case let .line(x1, y1, x2, y2, _, lineWidth):
            let pad = lineWidth / 2 + 4
            return CGRect(x: min(x1,x2) - pad, y: min(y1,y2) - pad, width: abs(x2-x1) + pad*2, height: abs(y2-y1) + pad*2)
        case let .square(x1, y1, x2, y2, _, lineWidth):
            let pad = lineWidth / 2
            return CGRect(x: min(x1,x2) - pad, y: min(y1,y2) - pad, width: abs(x2-x1) + pad*2, height: abs(y2-y1) + pad*2)
        case let .circle(x1, y1, x2, y2, _, lineWidth):
            let pad = lineWidth / 2
            return CGRect(x: min(x1,x2) - pad, y: min(y1,y2) - pad, width: abs(x2-x1) + pad*2, height: abs(y2-y1) + pad*2)
        case let .text(text, x, y, fontSize, _):
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
            let size = (text as NSString).boundingRect(
                with: CGSize(width: 300, height: 10_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            ).size
            return CGRect(x: x, y: y, width: max(size.width, 40), height: max(size.height, fontSize * 1.5))
        case let .callout(x, y, _, _, radius):
            return CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        case let .polygon(cx, cy, vx, vy, _, _, lineWidth):
            let radius = hypot(vx - cx, vy - cy) + lineWidth / 2
            return CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        }
    }

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

    private func notifyBackgroundChange() {
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
