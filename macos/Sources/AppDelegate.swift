import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.onToggle = { [weak self] in
            self?.toggleOverlay()
        }
        HotkeyManager.shared.registerOption1Hotkey()
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
            let controller = OverlayWindowController()
            controller.onClosed = { [weak self] in
                self?.overlayController = nil
            }
            controller.begin()
            overlayController = controller
        }
    }
}
