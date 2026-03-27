# Annotate macOS

Keyboard-driven macOS screen annotation app.

This project is the standalone macOS evolution of the original Annotate Chrome extension, but the goal here is different:
- annotate over **other macOS apps**, not just webpages
- show a fullscreen transparent overlay
- draw arrows, lines, boxes, circles, highlights, text, blackboards, and numbered callouts
- save a composited screenshot of the captured screen + annotations

## Current status

Working prototype:
- native Swift/AppKit app
- fullscreen overlay window
- keyboard-driven annotation tools
- screenshot save flow
- first-pass screen capture integration

## Run

```bash
cd /Users/home/projects/annotate-macos
swift run
```

## Shortcuts

### Global
- `Option+1` toggle overlay on/off

### Drawing
- `D` draw
- `A` arrow
- `L` line
- `S` square
- `C` circle
- `F` text
- `H` highlight
- `B` blackboard
- `N` numbered callout
- `1-6` colors
- `R` / `E` size up/down
- `Cmd+Z` undo
- `Cmd+Y` redo
- `Cmd+A` select all
- `Esc` exit panel

## Notes

This app is being adapted for true system-wide macOS annotation. Some polish is still needed for:
- multi-display handling
- accessibility / event routing edge cases
- packaging/signing/notarization
- perfect screenshot fidelity on every display setup
