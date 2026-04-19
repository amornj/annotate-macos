# AnnotateMac

A lightweight, keyboard-driven screen annotation app for macOS. Press a hotkey to overlay an invisible canvas on top of anything on your screen — draw, write, highlight, and annotate without leaving your workflow.

## Features

- Fullscreen transparent overlay over any app
- Universal binary — runs natively on Apple Silicon and Intel
- Draw, arrow, line, square, circle, text, callout tools
- Hold `Shift` while drawing a square or circle for a perfect square / circle
- Whiteboard and blackboard background modes with a 40 pt grid
- Snap-to-grid on move in select mode (hold `⌘` to bypass)
- Multi-line text input with auto-expanding text box
- Undo / redo, copy / paste, multi-select, move / resize / rotate
- 8 colors, adjustable line width and font size
- Consistent code signing — screen recording permission persists across rebuilds

## Requirements

- macOS 13+
- Xcode 15+ (to build from source)
- Screen Recording permission (prompted on first launch)

## Build

**Release build to `dist/`:**

```bash
./scripts/build_app.sh
```

Output: `dist/AnnotateMac.app`

**DMG:**

```bash
./scripts/make_dmg.sh
```

Output: `dist/AnnotateMac.dmg`

**Debug (Xcode):**

Open `AnnotateMac.xcodeproj` and run the `AnnotateMac` target.

## Keyboard Shortcuts

### Global
| Shortcut | Action |
|----------|--------|
| `Option+1` | Toggle overlay on/off |

### Tools
| Key | Tool |
|-----|------|
| `D` | Draw (freehand) |
| `A` | Arrow |
| `L` | Line |
| `S` | Square (hold `Shift` while dragging for a perfect square) |
| `C` | Circle (hold `Shift` while dragging for a perfect circle) |
| `T` | Triangle |
| `P` | Pentagon |
| `H` | Hexagon |
| `O` | Octagon |
| `F` | Text |
| `N` | Numbered callout |
| `V` | Select (move / resize / rotate, snaps to grid on whiteboard/blackboard — hold `⌘` to bypass) |
| `W` | Whiteboard background |
| `B` | Blackboard background |

### Text Mode (F)
| Key | Action |
|-----|--------|
| Click | Place text box at that position |
| Type | Enter text |
| `Enter` | Commit text, click elsewhere to add more |
| `Shift+Enter` | New line in same text box |
| `Esc` | Cancel without saving |
| `D`, `A`, `L`… | Ignored — stays in text mode |

### Colors & Size
| Key | Action |
|-----|--------|
| `1` | Red |
| `2` | Blue |
| `3` | Green |
| `4` | Yellow |
| `5` | Light grey |
| `6` | Dark grey |
| `7` | Orange |
| `8` | Purple |
| `R` | Increase size |
| `E` | Decrease size |

### History & Selection
| Shortcut | Action |
|----------|--------|
| `Cmd+Z` | Undo |
| `Cmd+Y` / `Cmd+Shift+Z` | Redo |
| `Cmd+A` | Select all |
| `Cmd+C` | Copy selected annotations (in select mode) |
| `Cmd+V` | Paste at marked target point (or nearby) |
| `Delete` | Delete selected, or clear all when select-all active |

### Exit
| Key | Action |
|-----|--------|
| `Esc` | Clear all annotations |
| `Esc Esc` | Exit app |

## Architecture

```
AnnotateMac/
├── main.swift                   # Entry point
├── AppDelegate.swift            # App lifecycle, hotkey wiring
├── HotkeyManager.swift          # Global Option+1 hotkey (Carbon)
├── OverlayWindowController.swift# Fullscreen transparent window
├── AnnotationOverlayView.swift  # Main canvas: drawing, input, keyboard
├── AnnotationState.swift        # Tool state, action history, undo/redo
└── OverlayChrome.swift          # ToolIndicatorView, ExitPanelView
```

State flows one way: `AnnotationState` holds all committed actions and notifies `AnnotationOverlayView` via callbacks to redraw. The view maintains a cached render of committed actions and only redraws the live preview on top during mouse drag, keeping performance fast.
