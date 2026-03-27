import AppKit

/// Compares two NSColors by their RGB components with tolerance.
func colorsMatch(_ a: NSColor, _ b: NSColor, tolerance: CGFloat = 0.01) -> Bool {
    let toRGB: (NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? = { c in
        guard let rgb = c.usingColorSpace(.deviceRGB) else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    }
    guard let ca = toRGB(a), let cb = toRGB(b) else { return false }
    return abs(ca.r - cb.r) < tolerance
        && abs(ca.g - cb.g) < tolerance
        && abs(ca.b - cb.b) < tolerance
        && abs(ca.a - cb.a) < tolerance
}

final class ControlPanelWindowController: NSWindowController {
    private let state: AnnotationState
    private let stack = NSStackView()
    private let toolPopup = NSPopUpButton()
    private let widthSlider = NSSlider(value: 3, minValue: 1, maxValue: 20, target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "3")

    // Shared color references so equality checks work reliably
    private let colorRed    = NSColor.systemRed
    private let colorBlue   = NSColor.systemBlue
    private let colorGreen  = NSColor.systemGreen
    private let colorYellow = NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.05, alpha: 1)
    private let colorLightGray  = NSColor(calibratedWhite: 0.82, alpha: 1)
    private let colorDarkGray   = NSColor(calibratedWhite: 0.43, alpha: 1)
    private var colorButtons: [NSButton] = []

    init(state: AnnotationState) {
        self.state = state
        let window = NSPanel(
            contentRect: NSRect(x: 120, y: 120, width: 310, height: 210),
            styleMask: [.titled, .utilityWindow, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate Controls"
        // Keep the panel above the overlay (which uses .screenSaver level).
        // .popUpMenu is the highest normal level, ensuring the dashboard stays on top.
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.styleMask.insert(.nonactivatingPanel)
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        super.init(window: window)
        setupUI()
        bindState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        // --- Tool row ---
        let toolRow = labeledRow(label: "Tool")
        AnnotationState.Tool.allCases.forEach { toolPopup.addItem(withTitle: $0.displayName) }
        toolPopup.target = self
        toolPopup.action = #selector(toolChanged)
        toolRow.addArrangedSubview(toolPopup)
        stack.addArrangedSubview(toolRow)

        // --- Color row ---
        let colorRow = labeledRow(label: "Color")
        let colorStack = NSStackView()
        colorStack.orientation = .horizontal
        colorStack.spacing = 6

        let colors: [NSColor] = [colorRed, colorBlue, colorGreen, colorYellow, colorLightGray, colorDarkGray]
        for color in colors {
            let button = NSButton(frame: .zero)
            button.wantsLayer = true
            button.isBordered = false
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 10
            button.layer?.borderWidth = 0
            button.layer?.borderColor = NSColor.white.cgColor
            button.target = self
            button.action = #selector(colorClicked(_:))
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 20),
                button.heightAnchor.constraint(equalToConstant: 20)
            ])
            colorStack.addArrangedSubview(button)
            colorButtons.append(button)
        }
        colorRow.addArrangedSubview(colorStack)
        stack.addArrangedSubview(colorRow)

        // --- Width row ---
        let widthRow = labeledRow(label: "Width")
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthRow.addArrangedSubview(widthSlider)
        widthRow.addArrangedSubview(widthLabel)
        stack.addArrangedSubview(widthRow)

        // --- Hint (two lines, use preferredMaxLayoutWidth for proper wrapping) ---
        let hint = NSTextField(wrappingLabelWithString: "Shortcuts: Option+1 toggle · D/A/L/S/C/F/H/B/N tools · 1-6 colors · R/E size · ⌘Z/⌘Y undo/redo · Esc exit")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        // Allow the label to expand vertically with proper wrapping
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hint.preferredMaxLayoutWidth = 286  // window width minus insets (12 + 12 + 2 for safety)
        stack.addArrangedSubview(hint)
    }

    private func bindState() {
        toolPopup.selectItem(at: AnnotationState.Tool.allCases.firstIndex(of: state.tool) ?? 0)
        widthSlider.doubleValue = state.lineWidth
        widthLabel.stringValue = String(Int(state.lineWidth))
        highlightSelectedColor()

        state.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.syncFromState()
            }
        }
    }

    private func syncFromState() {
        toolPopup.selectItem(at: AnnotationState.Tool.allCases.firstIndex(of: state.tool) ?? 0)
        widthSlider.doubleValue = state.lineWidth
        widthLabel.stringValue = String(Int(state.lineWidth))
        highlightSelectedColor()
    }

    private func highlightSelectedColor() {
        for (button, color) in zip(colorButtons, [colorRed, colorBlue, colorGreen, colorYellow, colorLightGray, colorDarkGray]) {
            let isSelected = colorsMatch(color, state.color)
            button.layer?.borderWidth = isSelected ? 2 : 0
        }
    }

    private func labeledRow(label: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.alignment = .right
        text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([text.widthAnchor.constraint(equalToConstant: 40)])
        row.addArrangedSubview(text)
        return row
    }

    @objc private func toolChanged() {
        let idx = toolPopup.indexOfSelectedItem
        guard AnnotationState.Tool.allCases.indices.contains(idx) else { return }
        state.tool = AnnotationState.Tool.allCases[idx]
    }

    @objc private func colorClicked(_ sender: NSButton) {
        guard let idx = colorButtons.firstIndex(of: sender) else { return }
        let colors: [NSColor] = [colorRed, colorBlue, colorGreen, colorYellow, colorLightGray, colorDarkGray]
        state.color = colors[idx]
    }

    @objc private func widthChanged() {
        state.lineWidth = CGFloat(widthSlider.doubleValue.rounded())
    }
}
