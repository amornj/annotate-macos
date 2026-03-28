import AppKit

final class AnnotationOverlayView: NSView {
    var onExitRequested: (() -> Void)?
    var onSaveRequested: (() -> Void)?
    var onToggleRequested: (() -> Void)?

    private let state: AnnotationState
    private var currentPath: [AnnotationState.StrokePoint] = []
    private var isDrawing = false
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var activeTextView: NSTextView?
    private var allSelected = false
    private var indicatorView = ToolIndicatorView(frame: NSRect(x: 24, y: 24, width: 44, height: 44))
    private var indicatorPanOffset: CGPoint = .zero
    private var isDraggingIndicator = false
    private var wasDrawingBeforeIndicatorDrag = false
    private var indicatorMoved = false
    private var selectHint: NSTextField?
    private var localMonitor: Any?
    private var lastEscTime: Date?

    // --- Cached rendering: separates committed actions from live preview ---
    private var committedCache: NSImage?
    private var lastCommittedVersion: Int = 0

    /// Shared color palette
    private static let sharedColors: [NSColor] = [
        .systemRed,
        .systemBlue,
        .systemGreen,
        NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.05, alpha: 1),
        NSColor(calibratedWhite: 0.82, alpha: 1),
        NSColor(calibratedWhite: 0.43, alpha: 1)
    ]

    init(frame frameRect: NSRect, state: AnnotationState) {
        self.state = state
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        postsFrameChangedNotifications = true
        setupIndicator()
        state.onActionListChange = { [weak self] in
            self?.invalidateCache()
            self?.needsDisplay = true
        }
        state.onChange = { [weak self] in
            self?.updateIndicator()
            self?.needsDisplay = true
        }
        updateIndicator()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Ensure the overlay view becomes first responder when added to window.
            window?.makeFirstResponder(self)
            // Set up a local event monitor so keyDown events that arrive at the app
            // (even if another app's window is momentarily key) are routed here.
            setupLocalEventMonitor()
        }
    }

    private func setupLocalEventMonitor() {
        // Remove any existing monitor first.
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            // Route the event to this view's keyDown handler.
            self.keyDown(with: event)
            return nil  // Consume the event — we handled it.
        }
    }

    private func removeLocalEventMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func setupIndicator() {
        positionIndicator()
        indicatorView.onMouseDown = { [weak self] point in
            guard let self else { return }
            self.wasDrawingBeforeIndicatorDrag = self.isDrawing
            self.isDrawing = false
            self.isDraggingIndicator = true
            self.indicatorMoved = false
            self.indicatorPanOffset = point
        }
        indicatorView.onMouseUp = { [weak self] in
            guard let self else { return }
            defer { self.isDraggingIndicator = false }
            if !self.indicatorMoved {
                self.showHelpPanel()
            }
        }
        addSubview(indicatorView)
    }

    private func positionIndicator() {
        let tileSize: CGFloat = 44
        let margin: CGFloat = 24
        indicatorView.frame = NSRect(
            x: bounds.width - tileSize - margin,
            y: margin,
            width: tileSize,
            height: tileSize
        )
        indicatorView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
    }

    func showIndicator() {
        indicatorView.isHidden = false
        positionIndicator()
    }

    func hideIndicator() {
        cancelTextInput()
        indicatorView.isHidden = true
    }

    func compositeImage(with background: NSImage?) -> NSImage? {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        // In whiteboard/blackboard mode: fill background first, then draw annotations on top.
        // In normal mode: draw captured screenshot as base, then annotations on top.
        if state.backgroundMode != .none {
            if let ctx = NSGraphicsContext.current?.cgContext {
                drawBackground(in: ctx)
            }
        } else {
            background?.draw(in: bounds)
        }
        if let ctx = NSGraphicsContext.current?.cgContext {
            for action in state.actions {
                renderAction(action, in: ctx)
            }
            if isDrawing, state.tool == .draw, currentPath.count >= 1 {
                renderDrawStroke(currentPath, color: state.color, lineWidth: state.lineWidth, in: ctx)
            }
            if isDrawing, let start = dragStart, let current = dragCurrent {
                renderShapePreview(from: start, to: current, in: ctx)
            }
        }
        image.unlockFocus()
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Step 1: Fill background if whiteboard/blackboard mode active
        drawBackground(in: ctx)

        // Step 2: rebuild committed cache if stale
        if state.committedVersion != lastCommittedVersion || committedCache == nil {
            committedCache = nil
            committedCache = renderCommittedActions()
            lastCommittedVersion = state.committedVersion
        }

        // Step 3: draw cached committed actions
        if let cache = committedCache {
            cache.draw(in: bounds)
        }

        // Step 4: draw live preview on top
        drawPreview(in: ctx)

        if allSelected && state.hasActions() {
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.12).cgColor)
            ctx.fill(bounds)
        }
    }

    /// Draws the whiteboard or blackboard background fill.
    private func drawBackground(in ctx: CGContext?) {
        guard let ctx else { return }
        switch state.backgroundMode {
        case .none:
            break
        case .whiteboard:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(bounds)
        case .blackboard:
            ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor)
            ctx.fill(bounds)
        }
    }

    /// Renders all committed actions to a cached image.
    private func renderCommittedActions() -> NSImage {
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            for action in state.actions {
                renderAction(action, in: ctx)
            }
        }
        img.unlockFocus()
        return img
    }

    /// Draws only the in-progress preview (current drag stroke) on top of the cache.
    private func drawPreview(in ctx: CGContext) {
        if isDrawing, state.tool == .draw, currentPath.count >= 1 {
            renderDrawStroke(currentPath, color: state.color, lineWidth: state.lineWidth, in: ctx)
        }
        if isDrawing, let start = dragStart, let current = dragCurrent {
            renderShapePreview(from: start, to: current, in: ctx)
        }
    }

    private func renderAction(_ action: AnnotationState.Action, in ctx: CGContext) {
        ctx.saveGState()
        switch action {
        case let .draw(points, color, lineWidth):
            renderDrawStroke(points, color: color, lineWidth: lineWidth, in: ctx)
        case let .arrow(x1, y1, x2, y2, color, lineWidth):
            color.setStroke(); color.setFill(); ctx.setLineWidth(lineWidth); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            drawArrowShape(in: ctx, from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2), lineWidth: lineWidth)
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
            let font = NSFont.systemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let br = attrStr.boundingRect(
                with: CGSize(width: 300, height: 2000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            attrStr.draw(in: NSRect(x: x, y: y, width: ceil(br.width) + 4, height: ceil(br.height) + 8))
        case let .callout(x, y, n, color, radius):
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: radius * 1.1), .foregroundColor: NSColor.white]
            let text = NSString(string: String(n))
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2), withAttributes: attrs)
        }
        ctx.restoreGState()
    }

    private func renderDrawStroke(_ points: [AnnotationState.StrokePoint], color: NSColor, lineWidth: CGFloat, in ctx: CGContext) {
        color.setStroke()
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if points.count < 2 {
            if let p = points.first {
                let rect = CGRect(x: p.x - lineWidth / 2, y: p.y - lineWidth / 2, width: lineWidth, height: lineWidth)
                ctx.fillEllipse(in: rect)
            }
        } else if let first = points.first {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: first.x, y: first.y))
            for p in points.dropFirst() {
                ctx.addLine(to: CGPoint(x: p.x, y: p.y))
            }
            ctx.strokePath()
        }
    }

    private func renderShapePreview(from start: CGPoint, to end: CGPoint, in ctx: CGContext) {
        switch state.tool {
        case .draw: break
        case .arrow: renderAction(.arrow(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .line: renderAction(.line(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .square: renderAction(.square(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .circle: renderAction(.circle(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .text, .callout: break
        }
    }

    private func drawArrowShape(in ctx: CGContext, from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
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

    // MARK: - Cache invalidation

    private func invalidateCache() {
        committedCache = nil
    }

    deinit {
        removeLocalEventMonitor()
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        if indicatorView.frame.contains(location) { return }
        if allSelected { exitSelectAll() }
        if state.tool == .text { startTextInput(at: location); return }
        if state.tool == .callout { placeCallout(at: location); return }
        isDrawing = true
        dragStart = location
        dragCurrent = location
        if state.tool == .draw {
            currentPath = [AnnotationState.StrokePoint(x: location.x, y: location.y)]
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
        dragCurrent = location
        if state.tool == .draw {
            currentPath.append(AnnotationState.StrokePoint(x: location.x, y: location.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingIndicator {
            isDraggingIndicator = false
            isDrawing = wasDrawingBeforeIndicatorDrag
            if !indicatorMoved { showHelpPanel() }
            return
        }
        guard isDrawing else { return }
        isDrawing = false
        let location = convert(event.locationInWindow, from: nil)
        guard let start = dragStart else { return }
        defer { dragStart = nil; dragCurrent = nil; currentPath = [] }

        switch state.tool {
        case .draw:
            var points = currentPath
            if points.count == 1 { points.append(points[0]) }
            state.add(.draw(points: points, color: state.color, lineWidth: state.lineWidth))
        case .arrow:  state.add(.arrow(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth))
        case .line:   state.add(.line(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth))
        case .square: state.add(.square(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth))
        case .circle: state.add(.circle(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth))
        case .text, .callout: break
        }
        needsDisplay = true
    }

    // MARK: - Keyboard events

    override func keyDown(with event: NSEvent) {
        // If a text view is active, forward all input directly to it.
        if let tv = activeTextView {
            tv.keyDown(with: event)
            return
        }

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let hasCmd = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        let hasOpt  = event.modifierFlags.contains(.option)

        // Option+1: toggle overlay
        if hasOpt && chars == "1" && !hasCmd {
            onToggleRequested?()
            return
        }

        // ⌘A — select all
        if hasCmd && chars == "a" {
            if state.hasActions() { enterSelectAll() }
            return
        }

        // Delete / Backspace in select-all mode
        if allSelected && (event.keyCode == 51 || event.keyCode == 117) {
            state.clear(); exitSelectAll(); return
        }

        // Esc: single = clear all annotations, double = exit app
        if event.keyCode == 53 {
            if allSelected { exitSelectAll() }
            let now = Date()
            if let last = lastEscTime, now.timeIntervalSince(last) < 0.5 {
                lastEscTime = nil
                state.clear()
                indicatorView.isHidden = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            } else {
                lastEscTime = now
                state.clear()
                needsDisplay = true
            }
            return
        }

        // ⌘Z — undo
        if hasCmd && chars == "z" && !hasShift {
            state.undo(); return
        }

        // ⌘⇧Z or ⌘Y — redo
        if hasCmd && (chars == "y" || (chars == "z" && hasShift)) {
            state.redo(); return
        }

        // No-modifier shortcuts
        if !hasCmd && !hasShift && !hasOpt {
            // F mode: tool is locked — only allow color and size changes
            if state.tool == .text {
                switch chars {
                case "1": state.color = Self.sharedColors[0]
                case "2": state.color = Self.sharedColors[1]
                case "3": state.color = Self.sharedColors[2]
                case "4": state.color = Self.sharedColors[3]
                case "5": state.color = Self.sharedColors[4]
                case "6": state.color = Self.sharedColors[5]
                case "r": state.increaseSize()
                case "e": state.decreaseSize()
                default: break
                }
                updateIndicator()
                needsDisplay = true
                return
            }

            // Normal mode: full tool / color / size shortcuts
            switch chars {
            case "d": state.tool = .draw
            case "a": state.tool = .arrow
            case "l": state.tool = .line
            case "s": state.tool = .square
            case "c": state.tool = .circle
            case "f": state.tool = .text
            case "n": state.tool = .callout
            case "w": state.backgroundMode = .whiteboard; state.tool = .draw
            case "b": state.backgroundMode = .blackboard; state.tool = .draw
            case "1": state.color = Self.sharedColors[0]
            case "2": state.color = Self.sharedColors[1]
            case "3": state.color = Self.sharedColors[2]
            case "4": state.color = Self.sharedColors[3]
            case "5": state.color = Self.sharedColors[4]
            case "6": state.color = Self.sharedColors[5]
            case "r": state.increaseSize()
            case "e": state.decreaseSize()
            default:
                updateIndicator(); return
            }
            updateIndicator()
            needsDisplay = true
            return
        }

        super.keyDown(with: event)
    }

    private func updateIndicator() {
        indicatorView.tool = state.tool
        indicatorView.color = state.color
        indicatorView.weight = state.tool == .text ? max(1, (state.fontSize - 8) / 3.5) : state.lineWidth
    }

    // MARK: - Text input

    private func startTextInput(at point: CGPoint) {
        commitTextIfNeeded()

        window?.makeKey()

        let fontSize = state.fontSize
        let initialHeight = max(30, fontSize * 1.8)
        // Anchor the top of the text view at the click point; new lines grow downward.
        let tv = NSTextView(frame: NSRect(
            x: point.x,
            y: point.y - initialHeight,
            width: 300,
            height: initialHeight
        ))
        tv.isEditable = true
        tv.isSelectable = true
        tv.font = .systemFont(ofSize: fontSize)
        tv.textColor = state.color
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isRichText = false
        tv.usesRuler = false
        tv.usesFontPanel = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.maxSize = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        tv.insertionPointColor = state.color
        tv.delegate = self
        // Subtle dashed border so user can see the active text area
        tv.wantsLayer = true
        tv.layer?.borderColor = state.color.withAlphaComponent(0.5).cgColor
        tv.layer?.borderWidth = 1
        tv.layer?.cornerRadius = 2

        addSubview(tv)
        window?.makeFirstResponder(tv)
        activeTextView = tv
    }

    private func commitTextIfNeeded() {
        guard let tv = activeTextView else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            state.add(.text(text: text, x: tv.frame.minX, y: tv.frame.minY, fontSize: state.fontSize, color: state.color))
        }
        if tv.window?.firstResponder === tv {
            tv.window?.makeFirstResponder(self)
        }
        tv.removeFromSuperview()
        activeTextView = nil
        needsDisplay = true
    }

    private func cancelTextInput() {
        guard let tv = activeTextView else { return }
        if tv.window?.firstResponder === tv {
            tv.window?.makeFirstResponder(self)
        }
        tv.removeFromSuperview()
        activeTextView = nil
        needsDisplay = true
    }

    private func placeCallout(at point: CGPoint) {
        let count = state.calloutCount() + 1
        state.add(.callout(x: point.x, y: point.y, n: count, color: state.color, radius: max(12, state.lineWidth * 3)))
        needsDisplay = true
    }

    // MARK: - Select all

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
            label.frame = NSRect(x: bounds.midX - 200, y: bounds.height - 40, width: 400, height: 24)
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

    // MARK: - Panels

    private func showHelpPanel() {
        let alert = NSAlert()
        alert.messageText = "Annotate — Shortcuts"
        alert.informativeText = """
        Option+1: toggle overlay on/off
        D draw  A arrow  L line  S square  C circle
        W whiteboard  B blackboard  F text  N callout
        1-6: colors (red, blue, green, yellow, light grey, dark grey)
        R/E: increase/decrease line width or font size
        ⌘Z undo  ⌘Y redo  ⌘A select all
        Esc: exit
        """
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window!)
    }


}

extension AnnotationOverlayView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSEvent.modifierFlags.contains(.shift) {
                // Shift+Enter: insert a real newline and resize
                textView.insertNewlineIgnoringFieldEditor(nil)
                resizeActiveTextView()
                return true
            }
            // Enter: commit text and stay in F mode for next click
            commitTextIfNeeded()
            updateIndicator()
            needsDisplay = true
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextInput()
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        resizeActiveTextView()
    }

    private func resizeActiveTextView() {
        guard let tv = activeTextView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let newHeight = max(state.fontSize * 1.8, used.height + 8)
        if abs(tv.frame.height - newHeight) > 1 {
            // Keep the top (maxY) fixed; grow the bottom downward.
            let top = tv.frame.maxY
            tv.frame.size.height = newHeight
            tv.frame.origin.y = top - newHeight
        }
    }
}
