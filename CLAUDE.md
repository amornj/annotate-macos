# CLAUDE.md

## Project

Native macOS screen annotation app. AppKit, Swift 5.10+, macOS 13+. No dependencies.

## Build

```bash
# Release build → dist/AnnotateMac.app (signed)
./scripts/build_app.sh

# Quick debug build (universal: x86_64 + arm64)
xcodebuild -project AnnotateMac.xcodeproj -scheme AnnotateMac -configuration Debug \
  ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath /tmp/annotate-build build
open /tmp/annotate-build/Build/Products/Debug/AnnotateMac.app
```

## Code signing

The build script re-signs with the Apple Development certificate (fingerprint `9426B1D882541FEE12EEDCC7E4E4FB7753E7C3C8`, Team ID `47Y5Z32ZK3`) so macOS remembers screen recording permission across rebuilds. Always run the final app from `dist/` for persistent permissions.

## Key files

| File | Responsibility |
|------|---------------|
| `AnnotationOverlayView.swift` | All input handling (mouse, keyboard), drawing, text input, cache |
| `AnnotationState.swift` | Tool/color/size state, action list, undo/redo stack |
| `OverlayChrome.swift` | `ToolIndicatorView` (floating tile), `ExitPanelView` |
| `HotkeyManager.swift` | Global `Option+1` hotkey via Carbon |
| `OverlayWindowController.swift` | Fullscreen transparent `NSWindow` setup |

## Architecture notes

- `AnnotationState` is pure state — no UIKit/AppKit. Notifies view via two callbacks: `onChange` (tool/color/size changed) and `onActionListChange` (action committed/undone).
- `AnnotationOverlayView` keeps a cached `NSImage` of all committed actions (`committedCache`). Only the live drag preview is redrawn each frame on top of the cache.
- Text input uses a raw `NSTextView` subview (not a scroll view). It anchors its top at the click point and grows downward as lines are added. On Enter, text is committed and the view stays in F mode — pressing Enter and clicking elsewhere adds another text annotation.
- The local event monitor (`NSEvent.addLocalMonitorForEvents`) intercepts all keyDown events and routes them through `AnnotationOverlayView.keyDown`. When a text view is active, events are forwarded directly to it via `tv.keyDown(with: event)`.
- Tool-change shortcuts (D/A/L/S/C/N/W/B) are blocked while `state.tool == .text`. Colors (1–6) and size (R/E) still work in text mode.
- When the square or circle tool is active, holding `Shift` during drag constrains the bounding box to a square (yielding a perfect square or circle). Implemented via `constrainedEndpoint(from:to:event:)` applied in both `mouseDragged` (preview) and `mouseUp` (commit).
- `gridSpacing` (40 pt) is the single source of truth for both the rendered grid lines and the move-snap behavior. In select mode, dragging a selection while a whiteboard/blackboard background is active snaps the selection bbox's visual top-left to the nearest grid intersection. Hold `⌘` during the drag to bypass snap.

## Escape behavior

- Single `Esc` → clear all annotations
- Double `Esc` (within 0.5 s) → terminate app
- `Esc` inside active text view → cancel text input (handled by `NSTextViewDelegate.textView(_:doCommandBy:)`)

## Coordinate system

AppKit uses y-up coordinates for `NSView` frames. `NSTextView` itself is flipped (y-down internally). Text actions are stored as `(x: frame.minX, y: frame.minY)` and rendered with `NSAttributedString.draw(in:)` using `[.usesLineFragmentOrigin, .usesFontLeading]` into a rect sized by `boundingRect`. Width is fixed at 300 pt to match the text view width.
