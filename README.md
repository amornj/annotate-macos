# Annotate macOS

Keyboard-driven macOS screen annotation app.

## What this is now

This repo is now a real macOS app project for annotating on top of other apps.

Current architecture:
- AppKit-based fullscreen overlay window
- global hotkey: `Option+1` toggles overlay on/off
- floating control panel for tool/color/width
- Xcode project included: `AnnotateMac.xcodeproj`

## Current status

Working in-progress prototype:
- draw
- arrow
- line
- square
- circle
- text
- highlight
- blackboard
- numbered callout
- color switching
- width adjustment
- screenshot save flow

Still needs polish:
- lag/performance optimization
- multi-display support
- better screenshot fidelity
- signing/notarization for smooth distribution
- more polished UI/UX

## Build in Xcode

Open:
- `AnnotateMac.xcodeproj`

Then build/run the `AnnotateMac` target.

## Build from terminal

Build release app:

```bash
./scripts/build_app.sh
```

Output:
- `dist/AnnotateMac.app`

Build DMG:

```bash
./scripts/make_dmg.sh
```

Output:
- `dist/AnnotateMac.dmg`

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
