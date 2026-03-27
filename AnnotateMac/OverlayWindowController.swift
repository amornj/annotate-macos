import AppKit

final class OverlayWindowController: NSWindowController {
    private let overlayView: AnnotationOverlayView
    private var capturedBackground: NSImage?
    var onClosed: (() -> Void)?

    init(state: AnnotationState) {
        self.overlayView = AnnotationOverlayView(frame: .zero, state: state)
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        super.init(window: window)
        window.contentView = overlayView
        overlayView.frame = screenFrame
        overlayView.autoresizingMask = [.width, .height]
        overlayView.onExitRequested = { [weak self] in self?.closeOverlay() }
        overlayView.onSaveRequested = { [weak self] in self?.saveComposite() }
        overlayView.onToggleRequested = { [weak self] in self?.closeOverlay() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func begin() {
        Task { @MainActor in
            self.capturedBackground = try? await ScreenCapture.captureMainDisplay()
            self.showWindow(self)
            self.window?.makeKeyAndOrderFront(self)
            self.window?.makeFirstResponder(self.overlayView)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    override func close() {
        super.close()
        onClosed?()
    }

    private func saveComposite() {
        guard let image = overlayView.compositeImage(with: capturedBackground) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "annotate-overlay.png"
        panel.allowedContentTypes = [.png]
        panel.beginSheetModal(for: window!) { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }

    private func closeOverlay() {
        close()
    }
}
