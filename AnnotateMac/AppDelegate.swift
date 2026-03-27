import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AnnotationState()
    var overlayController: OverlayWindowController?
    private var isToggling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.onToggle = { [weak self] in
            self?.toggleOverlay()
        }
        HotkeyManager.shared.registerOption1Hotkey()

        // Auto-open the overlay on launch — no floating control window.
        toggleOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Called when the user clicks the Dock icon.
    /// Shows the annotation UI without needing Option+1.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let controller = overlayController, controller.window?.isVisible == true {
            controller.window?.orderFront(nil)
        } else {
            toggleOverlay()
        }
        return true
    }

    private func toggleOverlay() {
        guard !isToggling else { return }
        isToggling = true
        defer { isToggling = false }

        if let controller = overlayController, controller.window?.isVisible == true {
            controller.close()
            overlayController = nil
        } else if overlayController == nil {
            let controller = OverlayWindowController(state: state)
            controller.onClosed = { [weak self] in
                self?.overlayController = nil
            }
            controller.begin()
            overlayController = controller
        }
    }
}
