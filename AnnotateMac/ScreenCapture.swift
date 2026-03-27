import AppKit

enum ScreenCapture {
    static func captureMainDisplay() async throws -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let rect = screen.frame
        guard let cgImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution, .boundsIgnoreFraming]) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: rect.size)
    }
}
