import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AnnotationState()
    var overlayController: OverlayWindowController?
    var panelController: ControlPanelWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = ControlPanelWindowController(state: state)
        HotkeyManager.shared.onToggle = { [weak self] in
            self?.toggleOverlay()
        }
        HotkeyManager.shared.registerOption1Hotkey()
        panelController?.showWindow(self)
        toggleOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func toggleOverlay() {
        if let controller = overlayController, controller.window?.isVisible == true {
            controller.close()
            overlayController = nil
        } else {
            let controller = OverlayWindowController(state: state)
            controller.onClosed = { [weak self] in
                self?.overlayController = nil
            }
            controller.begin()
            overlayController = controller
        }
    }
}
