import AppKit

// MARK: - Tool Indicator View (floating tile)

final class ToolIndicatorView: NSView {
    var tool: AnnotationState.Tool = .draw { didSet { needsDisplay = true; updateBorderLayers() } }
    var color: NSColor = .systemRed { didSet { needsDisplay = true; updateBorderLayers() } }
    var weight: CGFloat = 3 { didSet { needsDisplay = true; updateBorderLayers() } }
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?

    private let darkLayer = CAShapeLayer()
    private let lightLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for sl in [lightLayer, darkLayer] {
            sl.fillColor = nil
            sl.lineWidth = 2.5
            sl.lineCap = .round
            layer?.addSublayer(sl)
        }
        updateBorderLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateBorderLayers() {
        guard let myLayer = layer else { return }

        // Map weight (1–20) to clock level 1–12
        let level = max(1, min(12, Int(weight.rounded())))
        let path = Self.clockPath(in: bounds.insetBy(dx: 4, dy: 4), radius: 9)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for sl in [lightLayer, darkLayer] {
            sl.frame = myLayer.bounds
            sl.path = path
        }
        // Dark segment: clock positions 1 → level (first fraction of path)
        darkLayer.strokeColor = color.cgColor
        darkLayer.strokeStart = 0
        darkLayer.strokeEnd = CGFloat(level) / 12.0

        // Light segment: clock positions (level+1) → 12 (remaining fraction)
        lightLayer.strokeColor = color.withAlphaComponent(0.22).cgColor
        lightLayer.strokeStart = CGFloat(level) / 12.0
        lightLayer.strokeEnd = 1.0

        CATransaction.commit()

        myLayer.shadowColor = color.cgColor
        myLayer.shadowRadius = 5
        myLayer.shadowOffset = .zero
        myLayer.shadowOpacity = 0.55
    }

    override func layout() {
        super.layout()
        updateBorderLayers()
    }

    /// Rounded-rect path starting at "1 o'clock" (right 1/3 of top straight edge),
    /// going clockwise. strokeStart=0 → position 1, strokeEnd=N/12 → position N.
    private static func clockPath(in rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = radius
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        // 1 o'clock: 2/3 along the top straight segment (right third)
        let topStraight = (maxX - r) - (minX + r)
        let startX = (minX + r) + topStraight * (2.0 / 3.0)

        path.move(to: CGPoint(x: startX, y: minY))
        // Remainder of top edge → top-right arc
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(center: CGPoint(x: maxX - r, y: minY + r),
                    radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        // Right edge → bottom-right arc
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(center: CGPoint(x: maxX - r, y: maxY - r),
                    radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        // Bottom edge (right→left) → bottom-left arc
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addArc(center: CGPoint(x: minX + r, y: maxY - r),
                    radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        // Left edge (bottom→top) → top-left arc
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(center: CGPoint(x: minX + r, y: minY + r),
                    radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        // Top edge back to "1 o'clock" start
        path.addLine(to: CGPoint(x: startX, y: minY))

        return path
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0, dy: 0)
        let bg = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
        bg.fill()
        drawGlyph(in: rect)
    }

    private func drawGlyph(in rect: NSRect) {
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()

        switch tool {
        case .draw:
            // Wavy line (bezier curve) — visually distinct from straight Line tool
            let p0 = CGPoint(x: rect.minX + 8, y: rect.midY)
            let p1 = CGPoint(x: rect.minX + 16, y: rect.midY + 8)
            let p3 = CGPoint(x: rect.maxX - 16, y: rect.midY + 8)
            let p4 = CGPoint(x: rect.maxX - 8, y: rect.midY)
            path.move(to: p0)
            path.curve(to: p4, controlPoint1: p1, controlPoint2: p3)
            color.setStroke()
            path.lineWidth = 2
            path.stroke()

        case .arrow:
            path.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.line(to: CGPoint(x: rect.maxX - 18, y: rect.minY + 10))
            path.move(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 18))
            path.stroke()

        case .line:
            path.lineWidth = 2
            path.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.stroke()

        case .square:
            path.lineWidth = 2
            path.appendRect(NSRect(x: rect.minX + 9, y: rect.minY + 9, width: rect.width - 18, height: rect.height - 18))
            path.stroke()

        case .circle:
            path.lineWidth = 2
            path.appendOval(in: NSRect(x: rect.minX + 8, y: rect.minY + 10, width: rect.width - 16, height: rect.height - 20))
            path.stroke()

        case .text:
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: color]
            NSString(string: "T").draw(at: CGPoint(x: rect.midX - 5, y: rect.midY - 10), withAttributes: attrs)

        case .callout:
            color.setStroke(); color.setFill()
            let circle = NSBezierPath(ovalIn: NSRect(x: rect.midX - 9, y: rect.midY - 9, width: 18, height: 18))
            circle.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: color]
            NSString(string: "1").draw(at: CGPoint(x: rect.midX - 3, y: rect.midY - 7), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }
}

// MARK: - Esc Confirmation Panel (bottom-right floating)

final class ExitPanelView: NSView {
    var onSave: (() -> Void)?
    var onExit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        layer?.cornerRadius = 12

        let label = NSTextField(labelWithString: "Exit annotate mode?")
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.frame = NSRect(x: 14, y: 58, width: 150, height: 18)
        addSubview(label)

        let save = NSButton(title: "Stay", target: self, action: #selector(saveTapped))
        save.frame = NSRect(x: 14, y: 18, width: 70, height: 28)
        save.bezelStyle = .rounded
        addSubview(save)

        let exit = NSButton(title: "Exit", target: self, action: #selector(exitTapped))
        exit.frame = NSRect(x: 96, y: 18, width: 70, height: 28)
        exit.bezelStyle = .rounded
        addSubview(exit)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func saveTapped() { onSave?() }
    @objc private func exitTapped() { onExit?() }
}
