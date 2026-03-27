import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AnnotationState()
    var overlayController: OverlayWindowController?
    var panelController: ControlPanelWindowController?
    private var isToggling = false  // prevents re-entrant toggle calls

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.onToggle = { [weak self] in
            self?.toggleOverlay()
        }
        HotkeyManager.shared.registerOption1Hotkey()

        // Show the floating control panel; it stays open for the session.
        let panel = ControlPanelWindowController(state: state)
        panel.showWindow(self)
        self.panelController = panel

        // Auto-open the overlay on launch.
        toggleOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
