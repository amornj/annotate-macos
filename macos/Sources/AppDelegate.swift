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

    /// Called when the user clicks the Dock icon.
    /// Shows the annotation UI (overlay + floating tile) without needing Option+1.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let controller = overlayController, controller.window?.isVisible == true {
            // Already visible — just bring to front
            controller.window?.orderFront(nil)
        } else {
            // Show overlay + floating tile
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
            controller.panelController = panelController  // wire up for panel ordering
            panelController?.overlayWindowController = controller  // forward keyboard events to overlay
            controller.onClosed = { [weak self] in
                self?.overlayController = nil
            }
            controller.begin()
            overlayController = controller
        }
    }
}
