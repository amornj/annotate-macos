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

    // --- Multi-selection state ---
    private var selectedIndices: [Int] = []

    // Rubber-band marquee
    private var isDrawingMarquee: Bool = false
    private var marqueeStart: CGPoint?
    private var marqueeCurrent: CGPoint?

    // Move drag
    private var isDraggingSelection: Bool = false
    private var selectionMoveOrigin: CGPoint?
    private var selectionMoveOriginals: [(index: Int, action: AnnotationState.Action)] = []

    // Resize drag
    private var isResizingSelection: Bool = false
    private var selectionResizeBBox: CGRect?
    private var selectionResizeOriginals: [(index: Int, action: AnnotationState.Action)] = []

    // Rotate drag
    private var isRotatingSelection: Bool = false
    private var selectionRotateCenter: CGPoint?
    private var selectionRotateStartAngle: CGFloat?
    private var selectionRotateOriginals: [(index: Int, action: AnnotationState.Action)] = []

    // Text editing from select mode
    private var editingFromSelectMode: Bool = false

    // Copy / paste
    private var clipboard: [AnnotationState.Action] = []
    private var pasteTargetPoint: CGPoint?      // set by clicking empty area; consumed by ⌘V

    private var clipboardBBox: CGRect? {
        guard !clipboard.isEmpty else { return nil }
        return clipboard.reduce(CGRect.null) { $0.union(state.boundingRect(for: $1)) }
    }

    // Union bbox of all currently selected annotations
    private var selectionBBox: CGRect? {
        let valid = selectedIndices.filter { $0 < state.actions.count }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(CGRect.null) { $0.union(state.boundingRect(for: state.actions[$1])) }
    }

    // --- Cached rendering: separates committed actions from live preview ---
    private var committedCache: NSImage?
    private var lastCommittedVersion: Int = 0

    /// Grid line spacing in points (also used to snap moves on whiteboard/blackboard).
    private static let gridSpacing: CGFloat = 40

    /// Shared color palette
    private static let sharedColors: [NSColor] = [
        .systemRed,
        .systemBlue,
        .systemGreen,
        NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.05, alpha: 1),
        NSColor(calibratedWhite: 0.82, alpha: 1),
        NSColor(calibratedWhite: 0.43, alpha: 1),
        .systemOrange,
        NSColor(calibratedRed: 0.60, green: 0.20, blue: 0.80, alpha: 1)
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

        drawSelectionOverlay(in: ctx)
    }

    /// Draws the whiteboard or blackboard background fill, plus grid lines.
    private func drawBackground(in ctx: CGContext?) {
        guard let ctx else { return }
        switch state.backgroundMode {
        case .none:
            break
        case .whiteboard:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(bounds)
            drawGrid(in: ctx)
        case .blackboard:
            ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor)
            ctx.fill(bounds)
            drawGrid(in: ctx)
        }
    }

    /// Draws evenly-spaced grey grid lines to aid alignment.
    private func drawGrid(in ctx: CGContext) {
        let spacing = Self.gridSpacing
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.5, alpha: 0.15).cgColor)
        ctx.setLineWidth(0.5)
        var x: CGFloat = spacing
        while x < bounds.width {
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); ctx.strokePath()
            x += spacing
        }
        var y: CGFloat = spacing
        while y < bounds.height {
            ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)); ctx.strokePath()
            y += spacing
        }
        ctx.restoreGState()
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
        case let .square(x1, y1, x2, y2, color, lineWidth, rotation):
            color.setStroke(); ctx.setLineWidth(lineWidth)
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)
            ctx.stroke(rect)
        case let .circle(x1, y1, x2, y2, color, lineWidth, rotation):
            color.setStroke(); ctx.setLineWidth(lineWidth)
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)
            ctx.strokeEllipse(in: rect)
        case let .text(text, x, y, fontSize, color):
            let storage = NSTextStorage(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: color
            ])
            let lm = NSLayoutManager()
            storage.addLayoutManager(lm)
            let tc = NSTextContainer(containerSize: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
            tc.lineFragmentPadding = 0
            lm.addTextContainer(tc)
            lm.ensureLayout(for: tc)
            lm.drawGlyphs(forGlyphRange: lm.glyphRange(for: tc), at: CGPoint(x: x, y: y))
        case let .callout(x, y, n, color, radius):
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: radius * 1.1), .foregroundColor: NSColor.white]
            let text = NSString(string: String(n))
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2), withAttributes: attrs)
        case let .polygon(cx, cy, vx, vy, sides, color, lineWidth):
            color.setStroke(); ctx.setLineWidth(lineWidth); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addPath(polygonPath(cx: cx, cy: cy, vx: vx, vy: vy, sides: sides))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func polygonPath(cx: CGFloat, cy: CGFloat, vx: CGFloat, vy: CGFloat, sides: Int) -> CGPath {
        let radius = hypot(vx - cx, vy - cy)
        guard radius > 0 else { return CGMutablePath() }
        let baseAngle = atan2(vy - cy, vx - cx)
        let step = 2 * CGFloat.pi / CGFloat(sides)
        let path = CGMutablePath()
        for i in 0..<sides {
            let a = baseAngle + CGFloat(i) * step
            let pt = CGPoint(x: cx + radius * cos(a), y: cy + radius * sin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
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
        case .square: renderAction(.square(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: state.color, lineWidth: state.lineWidth, rotation: 0), in: ctx)
        case .circle: renderAction(.circle(x1: start.x, y1: start.y, x2: end.x, y2: end.y, color: state.color, lineWidth: state.lineWidth, rotation: 0), in: ctx)
        case .triangle: renderAction(.polygon(cx: start.x, cy: start.y, vx: end.x, vy: end.y, sides: 3, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .pentagon: renderAction(.polygon(cx: start.x, cy: start.y, vx: end.x, vy: end.y, sides: 5, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .hexagon:  renderAction(.polygon(cx: start.x, cy: start.y, vx: end.x, vy: end.y, sides: 6, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .octagon:  renderAction(.polygon(cx: start.x, cy: start.y, vx: end.x, vy: end.y, sides: 8, color: state.color, lineWidth: state.lineWidth), in: ctx)
        case .text, .callout, .select: break
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

    // MARK: - Selection helpers

    /// Move handle: visual top-left (maxY in y-up coords). Blue.
    private func moveHandleRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - 6, y: rect.maxY - 6, width: 12, height: 12)
    }

    /// Resize handle: visual bottom-right (minY in y-up coords). Green.
    private func resizeHandleRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - 6, y: rect.minY - 6, width: 12, height: 12)
    }

    /// Rotate handle: visual top-right (maxX, maxY in y-up coords). Orange circle.
    private func rotateHandleRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 12, height: 12)
    }

    /// Returns the index of the topmost annotation whose bounding rect contains `point`.
    private func hitTestAnnotation(at point: CGPoint) -> Int? {
        for i in stride(from: state.actions.count - 1, through: 0, by: -1) {
            if state.boundingRect(for: state.actions[i]).insetBy(dx: -8, dy: -8).contains(point) {
                return i
            }
        }
        return nil
    }

    /// Draws the live marquee, per-item highlights, union bbox, move handle, and resize handle.
    private func drawSelectionOverlay(in ctx: CGContext) {
        guard state.tool == .select else { return }

        // Paste target crosshair
        if let pt = pasteTargetPoint {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemOrange.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [])
            let r: CGFloat = 10
            ctx.beginPath(); ctx.move(to: CGPoint(x: pt.x - r, y: pt.y)); ctx.addLine(to: CGPoint(x: pt.x + r, y: pt.y)); ctx.strokePath()
            ctx.beginPath(); ctx.move(to: CGPoint(x: pt.x, y: pt.y - r)); ctx.addLine(to: CGPoint(x: pt.x, y: pt.y + r)); ctx.strokePath()
            ctx.strokeEllipse(in: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
            ctx.restoreGState()
        }

        // Live rubber-band marquee
        if isDrawingMarquee, let start = marqueeStart, let current = marqueeCurrent {
            let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                           width: abs(current.x - start.x), height: abs(current.y - start.y))
            ctx.saveGState()
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 3])
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.stroke(r)
            ctx.setLineDash(phase: 4.5, lengths: [6, 3])
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)
            ctx.stroke(r)
            ctx.restoreGState()
            return
        }

        let valid = selectedIndices.filter { $0 < state.actions.count }
        guard !valid.isEmpty else { return }

        ctx.saveGState()

        // Per-item blue tint
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.08).cgColor)
        for i in valid { ctx.fill(state.boundingRect(for: state.actions[i]).insetBy(dx: -4, dy: -4)) }

        // Union bbox with dashed border (white + blue double-pass)
        let bbox = valid.reduce(CGRect.null) { $0.union(state.boundingRect(for: state.actions[$1])) }.insetBy(dx: -4, dy: -4)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 3])
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.stroke(bbox)
        ctx.setLineDash(phase: 4.5, lengths: [6, 3])
        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
        ctx.stroke(bbox)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineWidth(1.0)

        // Move handle — top-left, blue
        let mh = moveHandleRect(for: bbox)
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.fill(mh)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(mh)

        // Resize handle — bottom-right, green square
        let rh = resizeHandleRect(for: bbox)
        ctx.setFillColor(NSColor.systemGreen.cgColor)
        ctx.fill(rh)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.stroke(rh)

        // Rotate handle — top-right, orange circle
        let orth = rotateHandleRect(for: bbox)
        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.fillEllipse(in: orth)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.strokeEllipse(in: orth)

        ctx.restoreGState()
    }

    /// Returns a new action with all coordinates translated by `delta`.
    private func translating(_ action: AnnotationState.Action, by delta: CGPoint) -> AnnotationState.Action {
        let dx = delta.x, dy = delta.y
        switch action {
        case let .draw(points, color, lineWidth):
            return .draw(points: points.map { .init(x: $0.x + dx, y: $0.y + dy) }, color: color, lineWidth: lineWidth)
        case let .arrow(x1, y1, x2, y2, color, lineWidth):
            return .arrow(x1: x1+dx, y1: y1+dy, x2: x2+dx, y2: y2+dy, color: color, lineWidth: lineWidth)
        case let .line(x1, y1, x2, y2, color, lineWidth):
            return .line(x1: x1+dx, y1: y1+dy, x2: x2+dx, y2: y2+dy, color: color, lineWidth: lineWidth)
        case let .square(x1, y1, x2, y2, color, lineWidth, rotation):
            return .square(x1: x1+dx, y1: y1+dy, x2: x2+dx, y2: y2+dy, color: color, lineWidth: lineWidth, rotation: rotation)
        case let .circle(x1, y1, x2, y2, color, lineWidth, rotation):
            return .circle(x1: x1+dx, y1: y1+dy, x2: x2+dx, y2: y2+dy, color: color, lineWidth: lineWidth, rotation: rotation)
        case let .text(text, x, y, fontSize, color):
            return .text(text: text, x: x+dx, y: y+dy, fontSize: fontSize, color: color)
        case let .callout(x, y, n, color, radius):
            return .callout(x: x+dx, y: y+dy, n: n, color: color, radius: radius)
        case let .polygon(cx, cy, vx, vy, sides, color, lineWidth):
            return .polygon(cx: cx+dx, cy: cy+dy, vx: vx+dx, vy: vy+dy, sides: sides, color: color, lineWidth: lineWidth)
        }
    }

    /// Returns a new action with all coordinates scaled from `anchor` by (scaleX, scaleY).
    private func scaling(_ action: AnnotationState.Action, scaleX: CGFloat, scaleY: CGFloat, anchor: CGPoint) -> AnnotationState.Action {
        func sx(_ x: CGFloat) -> CGFloat { anchor.x + (x - anchor.x) * scaleX }
        func sy(_ y: CGFloat) -> CGFloat { anchor.y + (y - anchor.y) * scaleY }
        let uniformScale = sqrt(scaleX * scaleY)
        switch action {
        case let .draw(points, color, lineWidth):
            return .draw(points: points.map { .init(x: sx($0.x), y: sy($0.y)) }, color: color, lineWidth: lineWidth)
        case let .arrow(x1, y1, x2, y2, color, lineWidth):
            return .arrow(x1: sx(x1), y1: sy(y1), x2: sx(x2), y2: sy(y2), color: color, lineWidth: lineWidth)
        case let .line(x1, y1, x2, y2, color, lineWidth):
            return .line(x1: sx(x1), y1: sy(y1), x2: sx(x2), y2: sy(y2), color: color, lineWidth: lineWidth)
        case let .square(x1, y1, x2, y2, color, lineWidth, rotation):
            return .square(x1: sx(x1), y1: sy(y1), x2: sx(x2), y2: sy(y2), color: color, lineWidth: lineWidth, rotation: rotation)
        case let .circle(x1, y1, x2, y2, color, lineWidth, rotation):
            return .circle(x1: sx(x1), y1: sy(y1), x2: sx(x2), y2: sy(y2), color: color, lineWidth: lineWidth, rotation: rotation)
        case let .text(text, x, y, fontSize, color):
            return .text(text: text, x: sx(x), y: sy(y), fontSize: max(6, fontSize * uniformScale), color: color)
        case let .callout(x, y, n, color, radius):
            return .callout(x: sx(x), y: sy(y), n: n, color: color, radius: max(6, radius * uniformScale))
        case let .polygon(cx, cy, vx, vy, sides, color, lineWidth):
            return .polygon(cx: sx(cx), cy: sy(cy), vx: sx(vx), vy: sy(vy), sides: sides, color: color, lineWidth: lineWidth)
        }
    }

    /// Returns a new action with coordinate points rotated by `angle` (radians) around `center`.
    private func rotating(_ action: AnnotationState.Action, by angle: CGFloat, around center: CGPoint) -> AnnotationState.Action {
        func rot(_ p: CGPoint) -> CGPoint {
            let dx = p.x - center.x, dy = p.y - center.y
            return CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle),
                           y: center.y + dx * sin(angle) + dy * cos(angle))
        }
        switch action {
        case let .draw(points, color, lineWidth):
            return .draw(points: points.map { let r = rot(CGPoint(x: $0.x, y: $0.y)); return .init(x: r.x, y: r.y) }, color: color, lineWidth: lineWidth)
        case let .arrow(x1, y1, x2, y2, color, lineWidth):
            let p1 = rot(CGPoint(x: x1, y: y1)), p2 = rot(CGPoint(x: x2, y: y2))
            return .arrow(x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, color: color, lineWidth: lineWidth)
        case let .line(x1, y1, x2, y2, color, lineWidth):
            let p1 = rot(CGPoint(x: x1, y: y1)), p2 = rot(CGPoint(x: x2, y: y2))
            return .line(x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, color: color, lineWidth: lineWidth)
        case let .square(x1, y1, x2, y2, color, lineWidth, rotation):
            let c = rot(CGPoint(x: (x1+x2)/2, y: (y1+y2)/2))
            let hw = abs(x2-x1)/2, hh = abs(y2-y1)/2
            return .square(x1: c.x-hw, y1: c.y-hh, x2: c.x+hw, y2: c.y+hh, color: color, lineWidth: lineWidth, rotation: rotation + angle)
        case let .circle(x1, y1, x2, y2, color, lineWidth, rotation):
            let c = rot(CGPoint(x: (x1+x2)/2, y: (y1+y2)/2))
            let hw = abs(x2-x1)/2, hh = abs(y2-y1)/2
            return .circle(x1: c.x-hw, y1: c.y-hh, x2: c.x+hw, y2: c.y+hh, color: color, lineWidth: lineWidth, rotation: rotation + angle)
        case let .text(text, x, y, fontSize, color):
            let p = rot(CGPoint(x: x, y: y))
            return .text(text: text, x: p.x, y: p.y, fontSize: fontSize, color: color)
        case let .callout(x, y, n, color, radius):
            let p = rot(CGPoint(x: x, y: y))
            return .callout(x: p.x, y: p.y, n: n, color: color, radius: radius)
        case let .polygon(cx, cy, vx, vy, sides, color, lineWidth):
            let pc = rot(CGPoint(x: cx, y: cy)), pv = rot(CGPoint(x: vx, y: vy))
            return .polygon(cx: pc.x, cy: pc.y, vx: pv.x, vy: pv.y, sides: sides, color: color, lineWidth: lineWidth)
        }
    }

    // MARK: - Copy / Paste helpers

    private func pasteAtPoint(_ point: CGPoint) {
        guard let bbox = clipboardBBox else { return }
        let delta = CGPoint(x: point.x - bbox.midX, y: point.y - bbox.midY)
        performPaste(delta: delta)
    }

    private func pasteNearby() {
        performPaste(delta: CGPoint(x: 20, y: -20))
    }

    private func performPaste(delta: CGPoint) {
        let firstNewIndex = state.actions.count
        for action in clipboard {
            state.add(translating(action, by: delta))
        }
        selectedIndices = Array(firstNewIndex ..< state.actions.count)
        state.tool = .select
        needsDisplay = true
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

        if state.tool == .select {
            if let bbox = selectionBBox {
                let expandedBBox = bbox.insetBy(dx: -4, dy: -4)
                // Check move handle (top-left, blue)
                if moveHandleRect(for: expandedBBox).insetBy(dx: -4, dy: -4).contains(location) {
                    isDraggingSelection = true
                    selectionMoveOrigin = location
                    selectionMoveOriginals = selectedIndices.compactMap { i in
                        i < state.actions.count ? (i, state.actions[i]) : nil
                    }
                    return
                }
                // Check resize handle (bottom-right, green)
                if resizeHandleRect(for: expandedBBox).insetBy(dx: -4, dy: -4).contains(location) {
                    isResizingSelection = true
                    selectionResizeBBox = expandedBBox
                    selectionResizeOriginals = selectedIndices.compactMap { i in
                        i < state.actions.count ? (i, state.actions[i]) : nil
                    }
                    return
                }
                // Check rotate handle (top-right, orange)
                if rotateHandleRect(for: expandedBBox).insetBy(dx: -4, dy: -4).contains(location) {
                    isRotatingSelection = true
                    selectionRotateCenter = CGPoint(x: expandedBBox.midX, y: expandedBBox.midY)
                    selectionRotateStartAngle = atan2(location.y - expandedBBox.midY, location.x - expandedBBox.midX)
                    selectionRotateOriginals = selectedIndices.compactMap { i in
                        i < state.actions.count ? (i, state.actions[i]) : nil
                    }
                    return
                }
            }
            // Hit-test a single annotation
            if let i = hitTestAnnotation(at: location) {
                // Second click on already-selected sole text annotation → edit it
                if selectedIndices == [i], case let .text(text, x, y, fontSize, color) = state.actions[i] {
                    selectedIndices = []
                    state.remove(at: i)
                    editingFromSelectMode = true
                    startTextInput(at: CGPoint(x: x, y: y + fontSize * 1.8),
                                   prefill: text, fontSize: fontSize, color: color)
                    return
                }
                pasteTargetPoint = nil
                selectedIndices = [i]
                needsDisplay = true
                return
            }
            // Empty space: if clipboard non-empty, mark paste target; else start marquee
            if !clipboard.isEmpty {
                pasteTargetPoint = location
                needsDisplay = true
                return
            }
            selectedIndices = []
            isDrawingMarquee = true
            marqueeStart = location
            marqueeCurrent = location
            needsDisplay = true
            return
        }

        if state.tool == .text { startTextInput(at: location); return }
        if state.tool == .callout { placeCallout(at: location); return }
        if [.triangle, .pentagon, .hexagon, .octagon].contains(state.tool) {
            isDrawing = true; dragStart = location; dragCurrent = location; needsDisplay = true; return
        }
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
        if isDraggingSelection {
            guard let origin = selectionMoveOrigin else { return }
            var delta = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
            // Snap to grid when whiteboard/blackboard is active. Hold ⌘ to override.
            if state.backgroundMode != .none,
               !event.modifierFlags.contains(.command),
               !selectionMoveOriginals.isEmpty {
                let origBBox = selectionMoveOriginals.reduce(CGRect.null) {
                    $0.union(state.boundingRect(for: $1.action))
                }
                if !origBBox.isNull {
                    let g = Self.gridSpacing
                    let snappedMinX = ((origBBox.minX + delta.x) / g).rounded() * g
                    let snappedMaxY = ((origBBox.maxY + delta.y) / g).rounded() * g
                    delta.x = snappedMinX - origBBox.minX
                    delta.y = snappedMaxY - origBBox.maxY
                }
            }
            for (i, original) in selectionMoveOriginals {
                state.replace(at: i, with: translating(original, by: delta))
            }
            needsDisplay = true
            return
        }
        if isResizingSelection {
            guard let origBBox = selectionResizeBBox else { return }
            // Anchor: visual top-left = (minX, maxY) in y-up coords — stays fixed
            let anchor = CGPoint(x: origBBox.minX, y: origBBox.maxY)
            let origW = max(1, origBBox.width), origH = max(1, origBBox.height)
            let newW = max(origW * 0.05, location.x - anchor.x)
            let newH = max(origH * 0.05, anchor.y - location.y)
            let scaleX = newW / origW, scaleY = newH / origH
            for (i, original) in selectionResizeOriginals {
                state.replace(at: i, with: scaling(original, scaleX: scaleX, scaleY: scaleY, anchor: anchor))
            }
            needsDisplay = true
            return
        }
        if isRotatingSelection {
            guard let center = selectionRotateCenter, let startAngle = selectionRotateStartAngle else { return }
            let currentAngle = atan2(location.y - center.y, location.x - center.x)
            let delta = currentAngle - startAngle
            for (i, original) in selectionRotateOriginals {
                state.replace(at: i, with: rotating(original, by: delta, around: center))
            }
            needsDisplay = true
            return
        }
        if isDrawingMarquee {
            marqueeCurrent = location
            needsDisplay = true
            return
        }
        if isDraggingIndicator {
            indicatorMoved = true
            indicatorView.frame.origin = CGPoint(x: location.x - indicatorPanOffset.x, y: location.y - indicatorPanOffset.y)
            return
        }
        guard isDrawing else { return }
        dragCurrent = constrainedEndpoint(from: dragStart, to: location, event: event)
        if state.tool == .draw {
            currentPath.append(AnnotationState.StrokePoint(x: location.x, y: location.y))
        }
        needsDisplay = true
    }

    /// When shift is held with the square or circle tool, snap the endpoint so
    /// the bounding box is square (yielding a perfect square or circle).
    private func constrainedEndpoint(from start: CGPoint?, to end: CGPoint, event: NSEvent) -> CGPoint {
        guard let start,
              event.modifierFlags.contains(.shift),
              state.tool == .square || state.tool == .circle else { return end }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let size = max(abs(dx), abs(dy))
        let sx: CGFloat = dx >= 0 ? 1 : -1
        let sy: CGFloat = dy >= 0 ? 1 : -1
        return CGPoint(x: start.x + size * sx, y: start.y + size * sy)
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingSelection {
            isDraggingSelection = false
            selectionMoveOrigin = nil
            selectionMoveOriginals = []
            return
        }
        if isResizingSelection {
            isResizingSelection = false
            selectionResizeBBox = nil
            selectionResizeOriginals = []
            return
        }
        if isRotatingSelection {
            isRotatingSelection = false
            selectionRotateCenter = nil
            selectionRotateStartAngle = nil
            selectionRotateOriginals = []
            return
        }
        if isDrawingMarquee {
            isDrawingMarquee = false
            if let start = marqueeStart, let current = marqueeCurrent {
                let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                               width: abs(current.x - start.x), height: abs(current.y - start.y))
                if r.width > 4 || r.height > 4 {
                    selectedIndices = state.actions.indices.filter { i in
                        state.boundingRect(for: state.actions[i]).intersects(r)
                    }
                }
            }
            marqueeStart = nil; marqueeCurrent = nil
            needsDisplay = true
            return
        }
        if isDraggingIndicator {
            isDraggingIndicator = false
            isDrawing = wasDrawingBeforeIndicatorDrag
            if !indicatorMoved { showHelpPanel() }
            return
        }
        guard isDrawing else { return }
        isDrawing = false
        let rawLocation = convert(event.locationInWindow, from: nil)
        guard let start = dragStart else { return }
        let location = constrainedEndpoint(from: start, to: rawLocation, event: event)
        defer { dragStart = nil; dragCurrent = nil; currentPath = [] }

        switch state.tool {
        case .draw:
            var points = currentPath
            if points.count == 1 { points.append(points[0]) }
            state.add(.draw(points: points, color: state.color, lineWidth: state.lineWidth))
        case .arrow:  state.add(.arrow(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth))
        case .line:   state.add(.line(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth))
        case .square: state.add(.square(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth, rotation: 0))
        case .circle: state.add(.circle(x1: start.x, y1: start.y, x2: location.x, y2: location.y, color: state.color, lineWidth: state.lineWidth, rotation: 0))
        case .triangle: state.add(.polygon(cx: start.x, cy: start.y, vx: location.x, vy: location.y, sides: 3, color: state.color, lineWidth: state.lineWidth))
        case .pentagon: state.add(.polygon(cx: start.x, cy: start.y, vx: location.x, vy: location.y, sides: 5, color: state.color, lineWidth: state.lineWidth))
        case .hexagon:  state.add(.polygon(cx: start.x, cy: start.y, vx: location.x, vy: location.y, sides: 6, color: state.color, lineWidth: state.lineWidth))
        case .octagon:  state.add(.polygon(cx: start.x, cy: start.y, vx: location.x, vy: location.y, sides: 8, color: state.color, lineWidth: state.lineWidth))
        case .text, .callout, .select: break
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

        // ⌘C — copy selected annotations (select mode only)
        if hasCmd && chars == "c" {
            if state.tool == .select && !selectedIndices.isEmpty {
                clipboard = selectedIndices.compactMap { $0 < state.actions.count ? state.actions[$0] : nil }
                pasteTargetPoint = nil
            }
            return
        }

        // ⌘V — paste at marked target point, or nearby if no target set
        if hasCmd && chars == "v" {
            if !clipboard.isEmpty {
                if let target = pasteTargetPoint {
                    pasteAtPoint(target)
                } else {
                    pasteNearby()
                }
                pasteTargetPoint = nil
            }
            return
        }

        // Delete / Backspace — clear all (select-all mode) or delete selected annotations
        if event.keyCode == 51 || event.keyCode == 117 {
            if allSelected {
                state.clear(); exitSelectAll(); return
            } else if state.tool == .select, !selectedIndices.isEmpty {
                state.removeMultiple(at: selectedIndices); selectedIndices = []; needsDisplay = true; return
            }
        }

        // Esc: deselect first if in select mode, then clear all (undoable) / double-Esc exit
        if event.keyCode == 53 {
            if allSelected { exitSelectAll(); return }
            if state.tool == .select && !selectedIndices.isEmpty {
                selectedIndices = []; pasteTargetPoint = nil; needsDisplay = true; return
            }
            let now = Date()
            if let last = lastEscTime, now.timeIntervalSince(last) < 0.5 {
                lastEscTime = nil
                state.clearWithUndo()
                indicatorView.isHidden = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.terminate(nil)
                }
            } else {
                lastEscTime = now
                state.clearWithUndo()
                needsDisplay = true
            }
            return
        }

        // ⌘Z — per-action undo, or bulk restore if actions list is empty
        if hasCmd && chars == "z" && !hasShift {
            if state.hasActions() { state.undo() } else { state.undoBulkIfAvailable() }
            return
        }

        // ⌘⇧Z or ⌘Y — redo
        if hasCmd && (chars == "y" || (chars == "z" && hasShift)) {
            state.redo(); return
        }

        // No-modifier shortcuts — tool, color, size (always available when no text box is active)
        if !hasCmd && !hasShift && !hasOpt {
            switch chars {
            case "d": state.tool = .draw;    selectedIndices = []; pasteTargetPoint = nil
            case "a": state.tool = .arrow;   selectedIndices = []; pasteTargetPoint = nil
            case "l": state.tool = .line;    selectedIndices = []; pasteTargetPoint = nil
            case "s": state.tool = .square;  selectedIndices = []; pasteTargetPoint = nil
            case "c": state.tool = .circle;  selectedIndices = []; pasteTargetPoint = nil
            case "f": state.tool = .text;    selectedIndices = []; pasteTargetPoint = nil
            case "n": state.tool = .callout; selectedIndices = []; pasteTargetPoint = nil
            case "t": state.tool = .triangle; selectedIndices = []; pasteTargetPoint = nil
            case "p": state.tool = .pentagon; selectedIndices = []; pasteTargetPoint = nil
            case "h": state.tool = .hexagon;  selectedIndices = []; pasteTargetPoint = nil
            case "o": state.tool = .octagon;  selectedIndices = []; pasteTargetPoint = nil
            case "v": state.tool = .select
            case "w": state.backgroundMode = (state.backgroundMode == .whiteboard) ? .none : .whiteboard
            case "b": state.backgroundMode = (state.backgroundMode == .blackboard) ? .none : .blackboard
            case "1": state.color = Self.sharedColors[0]
            case "2": state.color = Self.sharedColors[1]
            case "3": state.color = Self.sharedColors[2]
            case "4": state.color = Self.sharedColors[3]
            case "5": state.color = Self.sharedColors[4]
            case "6": state.color = Self.sharedColors[5]
            case "7": state.color = Self.sharedColors[6]
            case "8": state.color = Self.sharedColors[7]
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

    /// Starts a text input view at `point` (which is the visual top of the text, i.e. frame.maxY).
    /// Pass `prefill`/`fontSize`/`color` when re-opening a committed annotation for editing.
    private func startTextInput(at point: CGPoint,
                                prefill: String? = nil,
                                fontSize overrideFontSize: CGFloat? = nil,
                                color overrideColor: NSColor? = nil) {
        commitTextIfNeeded()

        window?.makeKey()

        let fontSize = overrideFontSize ?? state.fontSize
        let textColor = overrideColor ?? state.color
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
        tv.textColor = textColor
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
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.insertionPointColor = textColor
        tv.delegate = self
        tv.wantsLayer = true
        tv.layer?.borderColor = textColor.withAlphaComponent(0.5).cgColor
        tv.layer?.borderWidth = 1
        tv.layer?.cornerRadius = 2

        if let text = prefill {
            tv.string = text
            resizeTextView(tv, fontSize: fontSize)
        }

        addSubview(tv)
        window?.makeFirstResponder(tv)
        if prefill != nil {
            // Place cursor at end so it's immediately visible; user can click to reposition
            tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
        }
        activeTextView = tv
    }

    private func commitTextIfNeeded() {
        guard let tv = activeTextView else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use the text view's own font/color so edits preserve original styling
        let fontSize = (tv.font?.pointSize) ?? state.fontSize
        let color = tv.textColor ?? state.color
        if !text.isEmpty {
            state.add(.text(text: text, x: tv.frame.minX, y: tv.frame.minY, fontSize: fontSize, color: color))
        }
        if tv.window?.firstResponder === tv {
            tv.window?.makeFirstResponder(self)
        }
        tv.removeFromSuperview()
        activeTextView = nil
        if editingFromSelectMode {
            editingFromSelectMode = false
            state.tool = .select
        }
        needsDisplay = true
    }

    private func cancelTextInput() {
        guard let tv = activeTextView else { return }
        if tv.window?.firstResponder === tv {
            tv.window?.makeFirstResponder(self)
        }
        tv.removeFromSuperview()
        activeTextView = nil
        editingFromSelectMode = false
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
        T triangle  P pentagon  H hexagon  O octagon
        W whiteboard  B blackboard  F text  N callout
        V select — click to select, ■ move, ■ resize, ◉ rotate, ⌘C copy, ⌘V paste
        1-8: colors (red, blue, green, yellow, lt grey, dk grey, orange, purple)
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
        guard let tv = activeTextView else { return }
        resizeTextView(tv, fontSize: tv.font?.pointSize ?? state.fontSize)
    }

    private func resizeTextView(_ tv: NSTextView, fontSize: CGFloat) {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let newHeight = max(fontSize * 1.8, used.height + 8)
        if abs(tv.frame.height - newHeight) > 1 {
            let top = tv.frame.maxY
            tv.frame.size.height = newHeight
            tv.frame.origin.y = top - newHeight
        }
    }
}
