# AnnotateMac

A lightweight, keyboard-driven screen annotation app for macOS. Press a hotkey to overlay an invisible canvas on top of anything on your screen — draw, write, highlight, and annotate without leaving your workflow.

## Features

- Fullscreen transparent overlay over any app
- Draw, arrow, line, square, circle, text, callout tools
- Whiteboard and blackboard background modes
- Multi-line text input with auto-expanding text box
- Undo / redo
- 6 colors, adjustable line width and font size
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
| `S` | Square |
| `C` | Circle |
| `F` | Text |
| `N` | Numbered callout |
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
| `R` | Increase size |
| `E` | Decrease size |

### History & Selection
| Shortcut | Action |
|----------|--------|
| `Cmd+Z` | Undo |
| `Cmd+Y` / `Cmd+Shift+Z` | Redo |
| `Cmd+A` | Select all |
| `Delete` | Clear all (when select-all active) |

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
