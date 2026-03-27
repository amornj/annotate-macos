import AppKit

final class ToolIndicatorView: NSView {
    var tool: AnnotationState.Tool = .draw { didSet { needsDisplay = true } }
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var weight: CGFloat = 3 { didSet { needsDisplay = true } }
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let bg = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
        bg.fill()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 12, yRadius: 12)
        color.setStroke()
        ring.lineWidth = max(1.5, 1.5 + weight * 0.15)
        ring.stroke()
        drawGlyph(in: rect)
    }

    private func drawGlyph(in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 2
        NSColor.white.setStroke()
        NSColor.white.setFill()
        switch tool {
        case .draw:
            path.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.stroke()
        case .arrow:
            path.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.line(to: CGPoint(x: rect.maxX - 18, y: rect.minY + 10))
            path.move(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 18))
            path.stroke()
        case .line:
            path.move(to: CGPoint(x: rect.minX + 10, y: rect.maxY - 10))
            path.line(to: CGPoint(x: rect.maxX - 10, y: rect.minY + 10))
            path.stroke()
        case .square:
            path.appendRect(NSRect(x: rect.minX + 9, y: rect.minY + 9, width: rect.width - 18, height: rect.height - 18))
            path.stroke()
        case .circle:
            path.appendOval(in: NSRect(x: rect.minX + 8, y: rect.minY + 10, width: rect.width - 16, height: rect.height - 20))
            path.stroke()
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: NSColor.white]
            NSString(string: "T").draw(at: CGPoint(x: rect.midX - 5, y: rect.midY - 10), withAttributes: attrs)
        case .highlight:
            NSColor.white.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 7, y: rect.midY - 5, width: rect.width - 14, height: 10), xRadius: 2, yRadius: 2).fill()
        case .blackboard:
            NSColor.white.setStroke()
            let r = NSRect(x: rect.minX + 8, y: rect.minY + 8, width: rect.width - 16, height: rect.height - 16)
            NSBezierPath(rect: r).stroke()
            let slash = NSBezierPath()
            slash.move(to: CGPoint(x: r.minX, y: r.maxY))
            slash.line(to: CGPoint(x: r.maxX, y: r.minY))
            slash.stroke()
        case .callout:
            NSColor.white.setStroke(); NSColor.white.setFill()
            let circle = NSBezierPath(ovalIn: NSRect(x: rect.midX - 9, y: rect.midY - 9, width: 18, height: 18))
            circle.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white]
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

final class ExitPanelView: NSView {
    var onSave: (() -> Void)?
    var onExit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        layer?.cornerRadius = 12

        let label = NSTextField(labelWithString: "Save screenshot?")
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.frame = NSRect(x: 14, y: 58, width: 140, height: 18)
        addSubview(label)

        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
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
