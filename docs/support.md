# Support — Annotate

## Getting Started

1. Install the extension from the Chrome Web Store or load it unpacked via `chrome://extensions`
2. Click the Annotate icon in your toolbar on any page
3. Start drawing — the overlay appears with a crosshair cursor

## Keyboard Shortcuts

### Tools
| Key | Tool |
|-----|------|
| `D` | Freehand draw |
| `A` | Arrow |
| `L` | Line |
| `S` | Square / Rectangle |
| `C` | Circle / Ellipse |
| `H` | Highlight (semi-transparent fill) |
| `B` | Blur / Redact (solid black box) |
| `F` | Text |
| `N` | Number callout (auto-incrementing ①②③…) |

### Colors
| Key | Color |
|-----|-------|
| `1` | Red |
| `2` | Blue |
| `3` | Green |
| `4` | Yellow |
| `5` | Light Grey |
| `6` | Dark Grey |

Your last-used color and line width are remembered between sessions.

### Other
| Key | Action |
|-----|--------|
| `R` / `E` | Increase / decrease line width (or font size in text mode) |
| `Cmd/Ctrl+Z` | Undo |
| `Cmd/Ctrl+Y` | Redo |
| `Cmd/Ctrl+A` | Select all annotations — then press Delete to clear |
| `Escape` | Exit — prompts to save screenshot |

Click the floating indicator icon to see all shortcuts at any time.

## Text Tool

- Press `F` to switch to text mode
- Press `R` / `E` to adjust font size **before** clicking
- Click anywhere to place a text box — the cursor appears at your click point
- Type your annotation — `E` and `R` type normally inside the box
- Press **Enter** to confirm, **Escape** to cancel
- Press **Shift+Enter** for a new line
- Click outside the text box to confirm

## Saving Your Work

1. Press **Escape** to open the exit dialog
2. Click **Yes** to save — the annotated screenshot is copied to your clipboard and downloaded as a PNG file
3. Click **No** to close without saving

## FAQ

**The overlay doesn't appear when I click the icon.**
Make sure you're not on a restricted page (`chrome://` pages, the Chrome Web Store, or other extension pages). Chrome extensions cannot inject scripts into these pages.

**Can I scroll the page while annotating?**
Yes — scroll wheel events are automatically passed through to the underlying page while the overlay is active.

**Does it work during screen sharing?**
Yes — the annotation overlay is rendered as part of the page, so it's visible to anyone watching your screen share or browser tab share.

**Where are my screenshots saved?**
Screenshots are saved to your default downloads folder with the filename `annotate-YYYYMMDD-HHmmss.png` and also copied to your clipboard.

## Contact

If you encounter a bug or have a feature request, please open an issue on the [GitHub repository](https://github.com/amornj/screen-annotator/issues).
