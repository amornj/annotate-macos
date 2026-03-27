import AppKit

final class AnnotationOverlayView: NSView {
    enum Tool: String, CaseIterable {
        case draw, arrow, line, square, circle, text, highlight, blackboard, callout
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

    var onExitRequested: (() -> Void)?
    var onSaveRequested: (() -> Void)?

    private(set) var tool: Tool = .draw
    private(set) var color: NSColor = .systemRed
    private(set) var lineWidth: CGFloat = 3
    private(set) var fontSize: CGFloat = 18

    private var actions: [Action] = []
    private var redoStack: [Action] = []
    private var currentPath: [StrokePoint] = []
    private var isDrawing = false
    private var dragStart: CGPoint?
    private var activeTextField: NSTextField?
    private var textClickPoint: CGPoint?
    private var allSelected = false
    private var indicatorView = ToolIndicatorView(frame: NSRect(x: 24, y: 24, width: 44, height: 44))
    private var indicatorPanOffset: CGPoint = .zero
    private var isDraggingIndicator = false
    private var indicatorMoved = false
    private var exitPanel: ExitPanelView?
    private var selectHint: NSTextField?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        postsFrameChangedNotifications = true
        setupIndicator()
        updateIndicator()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    private func setupIndicator() {
        indicatorView.onMouseDown = { [weak self] point in
            guard let self else { return }
            self.isDraggingIndicator = true
            self.indicatorMoved = false
            self.indicatorPanOffset = point
        }
        indicatorView.onMouseUp = { [weak self] in
            guard let self else { return }
            defer { self.isDraggingIndicator = false }
            if !self.indicatorMoved { self.showHelpPanel() }
        }
        addSubview(indicatorView)
    }

    func compositeImage(with background: NSImage?) -> NSImage? {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        background?.draw(in: bounds)
        drawActions(in: NSGraphicsContext.current!.cgContext)
        image.unlockFocus()
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawActions(in: ctx)
        if allSelected && !actions.isEmpty {
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.12).cgColor)
            ctx.fill(bounds)
        }
    }

    private func drawActions(in ctx: CGContext) {
        for action in actions {
            render(action, in: ctx)
        }
        if isDrawing, let start = dragStart {
            renderPreview(from: start, to: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil), in: ctx)
        }
    }

    private func render(_ action: Action, in ctx: CGContext) {
        ctx.saveGState()
        switch action {
        case let .draw(points, color, lineWidth):
            color.setStroke()
            color.setFill()
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if points.count < 2, let p = points.first {
                let rect = CGRect(x: p.x - lineWidth / 2, y: p.y - lineWidth / 2, width: lineWidth, height: lineWidth)
                ctx.fillEllipse(in: rect)
            } else if let first = points.first {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: first.x, y: first.y))
                for p in points.dropFirst() {
                    ctx.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                ctx.strokePath()
            }
        case let .arrow(x1, y1, x2, y2, color, lineWidth):
            color.setStroke(); color.setFill(); ctx.setLineWidth(lineWidth); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            drawArrow(in: ctx, from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), lineWidth: lineWidth)
        case let .line(x1, y1, x2, y2, color, lineWidth):
            color.setStroke(); ctx.setLineWidth(lineWidth); ctx.setLineCap(.round)
            ctx.beginPath(); ctx.move(to: CGPoint(x: x1, y: y1)); ctx.addLine(to: CGPoint(x: x2, y: y2)); ctx.strokePath()
        case let .square(x1, y1, x2, y2, color, lineWidth):
            color.setStroke(); ctx.setLineWidth(lineWidth)
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            ctx.stroke(rect)
        case let .circle(x1, y1, x2, y2, color, lineWidth):
            color.setStroke(); ctx.setLineWidth(lineWidth)
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            ctx.strokeEllipse(in: rect)
        case let .text(text, x, y, fontSize, color):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: color
            ]
            NSString(string: text).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        case let .highlight(x1, y1, x2, y2, color):
            ctx.setFillColor(color.withAlphaComponent(0.35).cgColor)
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            ctx.fill(rect)
        case let .blackboard(x1, y1, x2, y2):
            ctx.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.95).cgColor)
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            ctx.fill(rect)
        case let .callout(x, y, n, color, radius):
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
                .foregroundColor: NSColor.white
            ]
            let text = NSString(string: String(n))
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2), withAttributes: attrs)
        }
        ctx.restoreGState()
    }

    private func renderPreview(from start: CGPoint, to end: CGPoint, in ctx: CGContext) {
        switch tool {
        case .draw:
            break
        case .arrow:
            render(.arrow(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: color, lineWidth: lineWidth), in: ctx)
        case .line:
            render(.line(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: color, lineWidth: lineWidth), in: ctx)
        case .square:
            render(.square(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: color, lineWidth: lineWidth), in: ctx)
        case .circle:
            render(.circle(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: color, lineWidth: lineWidth), in: ctx)
        case .highlight:
            render(.highlight(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: color), in: ctx)
        case .blackboard:
            render(.blackboard(x1: start.x, y1: start.y, x2: end.x, y2: end.y), in: ctx)
        case .text, .callout:
            break
        }
    }

    private func drawArrow(in ctx: CGContext, from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        let headLen = max(lineWidth * 4, 12)
        let angle = atan2(end.y - start.y, end.x - start.x)
        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: CGPoint(x: end.x - headLen * cos(angle - .pi / 6), y: end.y - headLen * sin(angle - .pi / 6)))
        ctx.addLine(to: CGPoint(x: end.x - headLen * cos(angle + .pi / 6), y: end.y - headLen * sin(angle + .pi / 6)))
        ctx.closePath()
        ctx.fillPath()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        if indicatorView.frame.contains(location) { return }
        if allSelected { exitSelectAll() }
        if tool == .text {
            startTextInput(at: location)
            return
        }
        if tool == .callout {
            placeCallout(at: location)
            return
        }
        isDrawing = true
        dragStart = location
        if tool == .draw {
            currentPath = [StrokePoint(x: location.x, y: location.y)]
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if isDraggingIndicator {
            indicatorMoved = true
            indicatorView.frame.origin = CGPoint(x: location.x - indicatorPanOffset.x, y: location.y - indicatorPanOffset.y)
            return
        }
        guard isDrawing else { return }
        if tool == .draw {
            currentPath.append(StrokePoint(x: location.x, y: location.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingIndicator {
            isDraggingIndicator = false
            if !indicatorMoved { showHelpPanel() }
            return
        }
        guard isDrawing else { return }
        isDrawing = false
        let location = convert(event.locationInWindow, from: nil)
        guard let start = dragStart else { return }
        defer {
            dragStart = nil
            needsDisplay = true
        }
        switch tool {
        case .draw:
            if currentPath.count == 1, let first = currentPath.first { currentPath.append(first) }
            actions.append(.draw(points: currentPath, color: color, lineWidth: lineWidth))
            currentPath = []
            redoStack.removeAll()
        case .arrow:
            actions.append(.arrow(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: color, lineWidth: lineWidth))
            redoStack.removeAll()
        case .line:
            actions.append(.line(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: color, lineWidth: lineWidth))
            redoStack.removeAll()
        case .square:
            actions.append(.square(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: color, lineWidth: lineWidth))
            redoStack.removeAll()
        case .circle:
            actions.append(.circle(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: color, lineWidth: lineWidth))
            redoStack.removeAll()
        case .highlight:
            actions.append(.highlight(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: color))
            redoStack.removeAll()
        case .blackboard:
            actions.append(.blackboard(x1: start.x, y1: start.y, x2: location.x, y2: location.y))
            redoStack.removeAll()
        case .text, .callout:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        if let field = activeTextField, window?.firstResponder === field.currentEditor() {
            super.keyDown(with: event)
            return
        }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let mod = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        if mod && chars == "a" {
            if !actions.isEmpty { enterSelectAll() }
            return
        }
        if allSelected && (event.keyCode == 51 || event.keyCode == 117) {
            actions.removeAll(); redoStack.removeAll(); exitSelectAll(); return
        }
        if allSelected && event.keyCode == 53 { exitSelectAll(); return }
        if mod && chars == "z" && !event.modifierFlags.contains(.shift) {
            if let last = actions.popLast() { redoStack.append(last); needsDisplay = true }
            return
        }
        if mod && (chars == "y" || (chars == "z" && event.modifierFlags.contains(.shift))) {
            if let last = redoStack.popLast() { actions.append(last); needsDisplay = true }
            return
        }
        if !mod {
            switch chars {
            case "d": tool = .draw
            case "a": tool = .arrow
            case "l": tool = .line
            case "s": tool = .square
            case "c": tool = .circle
            case "f": tool = .text
            case "h": tool = .highlight
            case "b": tool = .blackboard
            case "n": tool = .callout
            case "1": color = .systemRed
            case "2": color = .systemBlue
            case "3": color = .systemGreen
            case "4": color = NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.05, alpha: 1)
            case "5": color = NSColor(calibratedWhite: 0.82, alpha: 1)
            case "6": color = NSColor(calibratedWhite: 0.43, alpha: 1)
            case "r": if tool == .text { fontSize = min(fontSize + 2, 72) } else { lineWidth = min(lineWidth + 1, 20) }
            case "e": if tool == .text { fontSize = max(fontSize - 2, 8) } else { lineWidth = max(lineWidth - 1, 1) }
            default:
                if event.keyCode == 53 { showExitPanel() }
                updateIndicator(); return
            }
            if let rgb = color.usingColorSpace(.deviceRGB) {
                UserDefaults.standard.set([rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent], forKey: "annotate_color")
            }
            UserDefaults.standard.set(lineWidth, forKey: "annotate_lineWidth")
            updateIndicator()
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    private func updateIndicator() {
        indicatorView.tool = tool
        indicatorView.color = color
        indicatorView.weight = tool == .text ? max(1, (fontSize - 8) / 3.5) : lineWidth
    }

    func restoreDefaults() {
        if let comps = UserDefaults.standard.array(forKey: "annotate_color") as? [CGFloat], comps.count == 4 {
            color = NSColor(calibratedRed: comps[0], green: comps[1], blue: comps[2], alpha: comps[3])
        }
        let storedLineWidth = UserDefaults.standard.double(forKey: "annotate_lineWidth")
        if storedLineWidth > 0 { lineWidth = storedLineWidth }
        updateIndicator()
    }

    private func startTextInput(at point: CGPoint) {
        commitTextIfNeeded()
        let field = NSTextField(frame: NSRect(x: point.x - 5, y: point.y - fontSize * 0.7, width: 220, height: max(32, fontSize * 1.8)))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = color
        field.backgroundColor = .clear
        field.isBezeled = false
        field.stringValue = ""
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        textClickPoint = point
    }

    private func commitTextIfNeeded() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            actions.append(.text(text: text, x: field.frame.minX, y: field.frame.minY, fontSize: fontSize, color: color))
            redoStack.removeAll()
        }
        field.removeFromSuperview()
        activeTextField = nil
        needsDisplay = true
    }

    private func placeCallout(at point: CGPoint) {
        let count = actions.reduce(0) { partial, action in
            if case .callout = action { return partial + 1 }
            return partial
        } + 1
        actions.append(.callout(x: point.x, y: point.y, n: count, color: color, radius: max(12, lineWidth * 3)))
        redoStack.removeAll()
        needsDisplay = true
    }

    private func enterSelectAll() {
        allSelected = true
        if selectHint == nil {
            let label = NSTextField(labelWithString: "All annotations selected — Delete to clear, Esc to cancel")
            label.textColor = .white
            label.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.92)
            label.drawsBackground = true
            label.alignment = .center
            label.font = .systemFont(ofSize: 13)
            label.isBezeled = false
            label.frame = NSRect(x: bounds.midX - 180, y: bounds.height - 40, width: 360, height: 24)
            label.wantsLayer = true
            label.layer?.cornerRadius = 8
            addSubview(label)
            selectHint = label
        }
        needsDisplay = true
    }

    private func exitSelectAll() {
        allSelected = false
        selectHint?.removeFromSuperview()
        selectHint = nil
        needsDisplay = true
    }

    private func showHelpPanel() {
        let alert = NSAlert()
        alert.messageText = "Annotate — Shortcuts"
        alert.informativeText = "D draw\nA arrow\nL line\nS square\nC circle\nH highlight\nB blackboard\nF text\nN callout\n1-6 colors\nR/E size\n⌘Z undo\n⌘Y redo\n⌘A select all\nEsc exit"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window!)
    }

    private func showExitPanel() {
        if exitPanel != nil {
            exitPanel?.removeFromSuperview()
            exitPanel = nil
            return
        }
        let panel = ExitPanelView(frame: NSRect(x: bounds.width - 220, y: 80, width: 180, height: 92))
        panel.onSave = { [weak self] in self?.onSaveRequested?() }
        panel.onExit = { [weak self] in self?.onExitRequested?() }
        addSubview(panel)
        exitPanel = panel
    }
}

extension AnnotationOverlayView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitTextIfNeeded()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            activeTextField?.removeFromSuperview()
            activeTextField = nil
            return true
        }
        return false
    }
}
