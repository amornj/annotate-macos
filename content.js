(() => {
  // Idempotent guard — if already active, do nothing (toggle handled by message)
  if (document.getElementById("annotate-root")) return;

  // ─── State ───────────────────────────────────────────────────────────
  let tool = "draw"; // draw | arrow | line | square | circle | highlight | blackboard | text | callout
  let color = "#ff0000";
  let lineWidth = 3;
  const actions = [];
  const redoStack = [];
  let drawing = false;
  let dragStart = null;
  let currentPath = [];
  let textEditing = false;
  let activeTextEl = null;
  let allSelected = false;
  let exitDialogTimer = null;

  // ─── SVG icons for indicator ─────────────────────────────────────────
  const ICONS = {
    draw: '<path d="M3 21l1.5-4.5L17.25 3.75a1.06 1.06 0 0 1 1.5 1.5L6 18z"/><path d="M15 6l3 3"/>',
    arrow:
      '<line x1="5" y1="19" x2="19" y2="5"/><polyline points="10 5 19 5 19 14"/>',
    square: '<rect x="4" y="6" width="16" height="12" fill="none"/>',
    circle: '<ellipse cx="12" cy="12" rx="9" ry="7"/>',
    text: '<text x="12" y="17" text-anchor="middle" fill="#fff" stroke="none" font-size="16" font-weight="bold" font-family="sans-serif">T</text>',
    highlight: '<rect x="3" y="7" width="18" height="10" rx="1" style="fill:#fff;fill-opacity:0.3"/>',
    blackboard: '<rect x="4" y="6" width="16" height="12" rx="1"/><line x1="4" y1="18" x2="20" y2="6"/><line x1="8" y1="18" x2="20" y2="10"/><line x1="4" y1="14" x2="16" y2="6"/>',
    line: '<line x1="5" y1="19" x2="19" y2="5"/>',
    callout: '<circle cx="12" cy="12" r="9"/><text x="12" y="16" text-anchor="middle" style="fill:#fff;stroke:none" font-size="12" font-weight="bold" font-family="sans-serif">1</text>',
  };

  // ─── DOM Setup ───────────────────────────────────────────────────────
  const root = document.createElement("div");
  root.id = "annotate-root";

  const canvas = document.createElement("canvas");
  canvas.id = "annotate-canvas";
  root.appendChild(canvas);

  const ctx = canvas.getContext("2d");

  function sizeCanvas() {
    const dpr = window.devicePixelRatio || 1;
    canvas.width = window.innerWidth * dpr;
    canvas.height = window.innerHeight * dpr;
    canvas.style.width = window.innerWidth + "px";
    canvas.style.height = window.innerHeight + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    replayAll();
  }

  // Indicator
  const indicator = document.createElement("div");
  indicator.id = "annotate-indicator";
  indicator.innerHTML = `<svg viewBox="0 0 24 24">${ICONS[tool]}</svg>`;
  root.appendChild(indicator);
  updateIndicatorColor();
  updateIndicatorWidth();

  document.documentElement.appendChild(root);
  sizeCanvas();

  // Restore last-used color and line width
  chrome.storage.local.get(["annotate_color", "annotate_lineWidth"], (d) => {
    if (d.annotate_color) { color = d.annotate_color; updateIndicatorColor(); }
    if (d.annotate_lineWidth) { lineWidth = parseInt(d.annotate_lineWidth, 10); updateIndicatorWidth(); }
  });

  // ─── Render helpers ──────────────────────────────────────────────────
  function renderAction(a) {
    ctx.save();
    ctx.strokeStyle = a.color;
    ctx.fillStyle = a.color;
    ctx.lineWidth = a.lineWidth;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    if (a.type === "draw") {
      if (a.points.length < 2) {
        // Single dot
        ctx.beginPath();
        ctx.arc(a.points[0].x, a.points[0].y, a.lineWidth / 2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.beginPath();
        ctx.moveTo(a.points[0].x, a.points[0].y);
        for (let i = 1; i < a.points.length; i++) {
          ctx.lineTo(a.points[i].x, a.points[i].y);
        }
        ctx.stroke();
      }
    } else if (a.type === "arrow") {
      drawArrow(ctx, a.x1, a.y1, a.x2, a.y2, a.lineWidth);
    } else if (a.type === "square") {
      const x = Math.min(a.x1, a.x2);
      const y = Math.min(a.y1, a.y2);
      const w = Math.abs(a.x2 - a.x1);
      const h = Math.abs(a.y2 - a.y1);
      if (w > 0 && h > 0) {
        ctx.beginPath();
        ctx.rect(x, y, w, h);
        ctx.stroke();
      }
    } else if (a.type === "circle") {
      const cx = (a.x1 + a.x2) / 2;
      const cy = (a.y1 + a.y2) / 2;
      const rx = Math.abs(a.x2 - a.x1) / 2;
      const ry = Math.abs(a.y2 - a.y1) / 2;
      if (rx > 0 && ry > 0) {
        ctx.beginPath();
        ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
        ctx.stroke();
      }
    } else if (a.type === "text") {
      ctx.font = `${a.fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
      ctx.fillStyle = a.color;
      ctx.textBaseline = "top"; // a.y is the em-box top, matching the div's visual text position
      const lines = a.text.split("\n");
      for (let i = 0; i < lines.length; i++) {
        ctx.fillText(lines[i], a.x, a.y + i * a.fontSize * 1.3);
      }
    } else if (a.type === "highlight") {
      const x = Math.min(a.x1, a.x2);
      const y = Math.min(a.y1, a.y2);
      const w = Math.abs(a.x2 - a.x1);
      const h = Math.abs(a.y2 - a.y1);
      if (w > 0 && h > 0) {
        ctx.globalAlpha = 0.4;
        ctx.fillStyle = a.color;
        ctx.fillRect(x, y, w, h);
      }
    } else if (a.type === "blackboard") {
      const x = Math.min(a.x1, a.x2);
      const y = Math.min(a.y1, a.y2);
      const w = Math.abs(a.x2 - a.x1);
      const h = Math.abs(a.y2 - a.y1);
      if (w > 0 && h > 0) {
        ctx.fillStyle = "#1a1a1a";
        ctx.fillRect(x, y, w, h);
      }
    } else if (a.type === "line") {
      ctx.beginPath();
      ctx.moveTo(a.x1, a.y1);
      ctx.lineTo(a.x2, a.y2);
      ctx.stroke();
    } else if (a.type === "callout") {
      ctx.beginPath();
      ctx.arc(a.x, a.y, a.radius, 0, Math.PI * 2);
      ctx.fillStyle = a.color;
      ctx.fill();
      ctx.fillStyle = "#fff";
      ctx.font = `bold ${Math.round(a.radius * 1.1)}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(a.n), a.x, a.y);
    }

    ctx.restore();
  }

  function drawArrow(c, x1, y1, x2, y2, lw) {
    const headLen = Math.max(lw * 4, 12);
    const angle = Math.atan2(y2 - y1, x2 - x1);
    // Shaft
    c.beginPath();
    c.moveTo(x1, y1);
    c.lineTo(x2, y2);
    c.stroke();
    // Head
    c.beginPath();
    c.moveTo(x2, y2);
    c.lineTo(
      x2 - headLen * Math.cos(angle - Math.PI / 6),
      y2 - headLen * Math.sin(angle - Math.PI / 6)
    );
    c.lineTo(
      x2 - headLen * Math.cos(angle + Math.PI / 6),
      y2 - headLen * Math.sin(angle + Math.PI / 6)
    );
    c.closePath();
    c.fill();
  }

  function replayAll() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const a of actions) renderAction(a);
    if (allSelected && actions.length > 0) {
      ctx.save();
      ctx.fillStyle = "rgba(59, 130, 246, 0.15)";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.restore();
    }
  }

  // ─── Scroll passthrough ─────────────────────────────────────────────
  // Forward wheel events to the scrollable element underneath the overlay
  root.addEventListener("wheel", (e) => {
    root.style.pointerEvents = "none";
    const target = document.elementFromPoint(e.clientX, e.clientY);
    root.style.pointerEvents = "";
    if (!target) return;
    // Walk up to find the nearest scrollable ancestor
    let el = target;
    while (el && el !== document.documentElement) {
      const style = window.getComputedStyle(el);
      const oy = style.overflowY;
      if ((oy === "auto" || oy === "scroll") && el.scrollHeight > el.clientHeight) break;
      el = el.parentElement;
    }
    if (el) el.scrollBy({ left: e.deltaX, top: e.deltaY });
  }, { passive: true });

  // ─── Mouse handlers ──────────────────────────────────────────────────
  canvas.addEventListener("mousedown", onMouseDown);
  canvas.addEventListener("mousemove", onMouseMove);
  canvas.addEventListener("mouseup", onMouseUp);

  function getPos(e) {
    return { x: e.clientX, y: e.clientY };
  }

  function onMouseDown(e) {
    if (e.button !== 0) return;

    if (allSelected) exitSelectAll();

    if (tool === "text") {
      startTextInput(e.clientX, e.clientY);
      return;
    }

    if (tool === "callout") {
      placeCallout(e.clientX, e.clientY);
      return;
    }

    drawing = true;
    dragStart = getPos(e);

    if (tool === "draw") {
      currentPath = [dragStart];
    }
  }

  function onMouseMove(e) {
    if (!drawing) return;
    const pos = getPos(e);

    if (tool === "draw") {
      currentPath.push(pos);
      // Draw incremental segment
      ctx.save();
      ctx.strokeStyle = color;
      ctx.lineWidth = lineWidth;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.beginPath();
      const prev = currentPath[currentPath.length - 2];
      ctx.moveTo(prev.x, prev.y);
      ctx.lineTo(pos.x, pos.y);
      ctx.stroke();
      ctx.restore();
    } else if (tool === "arrow" || tool === "square" || tool === "circle" ||
               tool === "line" || tool === "highlight" || tool === "blackboard") {
      // Live preview: replay + preview shape
      replayAll();
      ctx.save();
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = lineWidth;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      if (tool === "arrow") {
        drawArrow(ctx, dragStart.x, dragStart.y, pos.x, pos.y, lineWidth);
      } else if (tool === "line") {
        ctx.beginPath();
        ctx.moveTo(dragStart.x, dragStart.y);
        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();
      } else if (tool === "square") {
        const x = Math.min(dragStart.x, pos.x);
        const y = Math.min(dragStart.y, pos.y);
        const w = Math.abs(pos.x - dragStart.x);
        const h = Math.abs(pos.y - dragStart.y);
        if (w > 0 && h > 0) {
          ctx.beginPath();
          ctx.rect(x, y, w, h);
          ctx.stroke();
        }
      } else if (tool === "highlight") {
        const x = Math.min(dragStart.x, pos.x);
        const y = Math.min(dragStart.y, pos.y);
        const w = Math.abs(pos.x - dragStart.x);
        const h = Math.abs(pos.y - dragStart.y);
        if (w > 0 && h > 0) {
          ctx.globalAlpha = 0.4;
          ctx.fillRect(x, y, w, h);
        }
      } else if (tool === "blackboard") {
        const x = Math.min(dragStart.x, pos.x);
        const y = Math.min(dragStart.y, pos.y);
        const w = Math.abs(pos.x - dragStart.x);
        const h = Math.abs(pos.y - dragStart.y);
        if (w > 0 && h > 0) {
          ctx.fillStyle = "#1a1a1a";
          ctx.fillRect(x, y, w, h);
        }
      } else {
        // circle
        const cx = (dragStart.x + pos.x) / 2;
        const cy = (dragStart.y + pos.y) / 2;
        const rx = Math.abs(pos.x - dragStart.x) / 2;
        const ry = Math.abs(pos.y - dragStart.y) / 2;
        if (rx > 0 && ry > 0) {
          ctx.beginPath();
          ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
      ctx.restore();
    }
  }

  function onMouseUp(e) {
    if (!drawing) return;
    drawing = false;
    const pos = getPos(e);

    if (tool === "draw") {
      if (currentPath.length === 1) currentPath.push(currentPath[0]);
      actions.push({
        type: "draw",
        points: currentPath.slice(),
        color,
        lineWidth,
      });
      redoStack.length = 0;
      currentPath = [];
    } else if (tool === "arrow") {
      actions.push({
        type: "arrow",
        x1: dragStart.x,
        y1: dragStart.y,
        x2: pos.x,
        y2: pos.y,
        color,
        lineWidth,
      });
      redoStack.length = 0;
      replayAll();
    } else if (tool === "square") {
      const w = Math.abs(pos.x - dragStart.x);
      const h = Math.abs(pos.y - dragStart.y);
      if (w > 1 && h > 1) {
        actions.push({
          type: "square",
          x1: dragStart.x,
          y1: dragStart.y,
          x2: pos.x,
          y2: pos.y,
          color,
          lineWidth,
        });
        redoStack.length = 0;
      }
      replayAll();
    } else if (tool === "circle") {
      const rx = Math.abs(pos.x - dragStart.x) / 2;
      const ry = Math.abs(pos.y - dragStart.y) / 2;
      if (rx > 1 && ry > 1) {
        actions.push({
          type: "circle",
          x1: dragStart.x,
          y1: dragStart.y,
          x2: pos.x,
          y2: pos.y,
          color,
          lineWidth,
        });
        redoStack.length = 0;
      }
      replayAll();
    } else if (tool === "line") {
      const dx = Math.abs(pos.x - dragStart.x);
      const dy = Math.abs(pos.y - dragStart.y);
      if (dx > 1 || dy > 1) {
        actions.push({ type: "line", x1: dragStart.x, y1: dragStart.y, x2: pos.x, y2: pos.y, color, lineWidth });
        redoStack.length = 0;
      }
      replayAll();
    } else if (tool === "highlight") {
      const w = Math.abs(pos.x - dragStart.x);
      const h = Math.abs(pos.y - dragStart.y);
      if (w > 1 && h > 1) {
        actions.push({ type: "highlight", x1: dragStart.x, y1: dragStart.y, x2: pos.x, y2: pos.y, color });
        redoStack.length = 0;
      }
      replayAll();
    } else if (tool === "blackboard") {
      const w = Math.abs(pos.x - dragStart.x);
      const h = Math.abs(pos.y - dragStart.y);
      if (w > 1 && h > 1) {
        actions.push({ type: "blackboard", x1: dragStart.x, y1: dragStart.y, x2: pos.x, y2: pos.y });
        redoStack.length = 0;
      }
      replayAll();
    }

    dragStart = null;
  }

  // ─── Text tool ───────────────────────────────────────────────────────
  let fontSize = 18;

  function startTextInput(x, y) {
    if (textEditing) commitText();

    const el = document.createElement("div");
    el.className = "annotate-text-input";
    el.contentEditable = "true";
    el.style.left = (x - 5) + "px"; // offset by border(1)+padding-left(4) so cursor lands at click point
    el.style.top = (y - 3 - Math.round(fontSize * 0.65)) + "px"; // center cursor vertically at click point
    el.dataset.clickX = x;
    el.dataset.clickY = y;
    el.style.setProperty("--annotate-color", color);
    el.style.setProperty("--annotate-font-size", fontSize + "px");
    el.style.color = color;
    el.style.fontSize = fontSize + "px";
    root.appendChild(el);
    // Delay focus until element is laid out so the blinking caret appears
    requestAnimationFrame(() => {
      el.focus();
      const sel = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(el);
      range.collapse(true);
      sel.removeAllRanges();
      sel.addRange(range);
    });

    textEditing = true;
    activeTextEl = el;

    // Enter/Escape to confirm, Shift+Enter for newline
    el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        commitText();
      } else if (e.key === "Escape") {
        e.preventDefault();
        cancelText();
      }
      e.stopPropagation(); // suppress tool shortcuts while typing
    });

    // Click outside text to confirm (and swallow the event so canvas doesn't start a new text input)
    function onClickOutside(e) {
      if (!el.contains(e.target)) {
        e.stopPropagation();
        commitText();
        document.removeEventListener("mousedown", onClickOutside, true);
      }
    }
    // Delay to avoid the initial click that spawned this
    setTimeout(() => {
      document.addEventListener("mousedown", onClickOutside, true);
    }, 0);
  }

  function cancelText() {
    if (!activeTextEl) return;
    activeTextEl.remove();
    activeTextEl = null;
    textEditing = false;
  }

  function commitText() {
    if (!activeTextEl) return;
    const text = activeTextEl.innerText.trim();
    if (text) {
      const rect = activeTextEl.getBoundingClientRect();
      actions.push({
        type: "text",
        text,
        x: rect.left + 5, // border(1) + padding-left(4) = content left edge
        y: rect.top + 3 + Math.round(fontSize * 0.15), // border+padding top + half-leading = em-box top
        fontSize,
        color: activeTextEl.style.color,
        lineWidth,
      });
      redoStack.length = 0;
      replayAll();
    }
    activeTextEl.remove();
    activeTextEl = null;
    textEditing = false;
  }

  function placeCallout(x, y) {
    const n = actions.filter(a => a.type === "callout").length + 1;
    const radius = Math.max(12, lineWidth * 3);
    actions.push({ type: "callout", x, y, n, color, radius });
    redoStack.length = 0;
    replayAll();
  }

  function enterSelectAll() {
    allSelected = true;
    replayAll();
    if (!document.getElementById("annotate-select-hint")) {
      const hint = document.createElement("div");
      hint.id = "annotate-select-hint";
      hint.textContent = "All annotations selected — Delete to clear, Esc to cancel";
      hint.style.cssText = "all:initial;position:fixed;top:16px;left:50%;transform:translateX(-50%);background:rgba(30,30,30,0.92);color:#fff;font:13px/1 -apple-system,BlinkMacSystemFont,sans-serif;padding:8px 16px;border-radius:8px;z-index:2147483647;pointer-events:none;white-space:nowrap;box-shadow:0 2px 8px rgba(0,0,0,0.35)";
      root.appendChild(hint);
    }
  }

  function exitSelectAll() {
    allSelected = false;
    const hint = document.getElementById("annotate-select-hint");
    if (hint) hint.remove();
    replayAll();
  }

  // ─── Keyboard handler (capture phase) ────────────────────────────────
  document.addEventListener("keydown", onKeyDown, true);

  function onKeyDown(e) {
    // Don't intercept while typing text
    if (textEditing) return;

    const key = e.key.toLowerCase();
    const mod = e.metaKey || e.ctrlKey;

    // Select all
    if (mod && key === "a") {
      e.preventDefault();
      e.stopPropagation();
      if (actions.length > 0) enterSelectAll();
      return;
    }

    // Delete all when selected
    if (allSelected && (e.key === "Delete" || e.key === "Backspace")) {
      e.preventDefault();
      e.stopPropagation();
      actions.length = 0;
      redoStack.length = 0;
      exitSelectAll();
      return;
    }

    // Escape while selected: cancel selection only (don't show exit dialog)
    if (allSelected && e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      exitSelectAll();
      return;
    }

    // Any other key cancels selection before proceeding
    if (allSelected) exitSelectAll();

    // Undo
    if (mod && key === "z" && !e.shiftKey) {
      e.preventDefault();
      e.stopPropagation();
      if (actions.length) {
        redoStack.push(actions.pop());
        replayAll();
      }
      return;
    }

    // Redo (Cmd+Y or Cmd+Shift+Z)
    if (mod && (key === "y" || (key === "z" && e.shiftKey))) {
      e.preventDefault();
      e.stopPropagation();
      if (redoStack.length) {
        actions.push(redoStack.pop());
        replayAll();
      }
      return;
    }

    // Tool switching
    if (!mod) {
      let handled = true;
      switch (key) {
        case "d":
          setTool("draw");
          break;
        case "a":
          setTool("arrow");
          break;
        case "s":
          setTool("square");
          break;
        case "c":
          setTool("circle");
          break;
        case "f":
          setTool("text");
          break;
        case "h":
          setTool("highlight");
          break;
        case "b":
          setTool("blackboard");
          break;
        case "l":
          setTool("line");
          break;
        case "n":
          setTool("callout");
          break;
        // Colors
        case "1":
          setColor("#ff0000");
          break;
        case "2":
          setColor("#2563eb");
          break;
        case "3":
          setColor("#16a34a");
          break;
        case "4":
          setColor("#eab308");
          break;
        case "5":
          setColor("#d1d5db");
          break;
        case "6":
          setColor("#6b7280");
          break;
        // Line width (or font size when text tool is active but no box open)
        case "r":
          if (tool === "text") {
            fontSize = Math.min(fontSize + 2, 72);
          } else {
            lineWidth = Math.min(lineWidth + 1, 20);
            chrome.storage.local.set({ annotate_lineWidth: lineWidth });
          }
          updateIndicatorWidth();
          break;
        case "e":
          if (tool === "text") {
            fontSize = Math.max(fontSize - 2, 8);
          } else {
            lineWidth = Math.max(lineWidth - 1, 1);
            chrome.storage.local.set({ annotate_lineWidth: lineWidth });
          }
          updateIndicatorWidth();
          break;
        case "escape":
          if (document.getElementById("annotate-dialog")) {
            clearExitDialog();
            teardown(); // Escape while dialog = exit without saving
          } else {
            showExitDialog();
          }
          break;
        default:
          handled = false;
      }
      if (handled) {
        e.preventDefault();
        e.stopPropagation();
      }
    }
  }

  // ─── Tool / Color helpers ────────────────────────────────────────────
  function setTool(t) {
    if (textEditing) commitText();
    tool = t;
    indicator.innerHTML = `<svg viewBox="0 0 24 24">${ICONS[tool]}</svg>`;
    canvas.style.cursor = tool === "text" ? "text" : "crosshair";
    updateIndicatorWidth();
  }

  function setColor(c) {
    color = c;
    updateIndicatorColor();
    chrome.storage.local.set({ annotate_color: c });
  }

  function updateIndicatorColor() {
    indicator.style.setProperty("--annotate-color", color);
  }

  function updateIndicatorWidth() {
    const val = tool === "text" ? (fontSize - 8) / 64 * 19 + 1 : lineWidth;
    indicator.style.setProperty("--annotate-width", val);
  }

  // ─── Indicator drag + click ──────────────────────────────────────────
  let indDrag = false;
  let indMoved = false;
  let indOff = { x: 0, y: 0 };

  indicator.addEventListener("mousedown", (e) => {
    e.stopPropagation();
    indDrag = true;
    indMoved = false;
    indOff.x = e.clientX - indicator.getBoundingClientRect().left;
    indOff.y = e.clientY - indicator.getBoundingClientRect().top;
  });

  document.addEventListener("mousemove", (e) => {
    if (!indDrag) return;
    indMoved = true;
    indicator.style.left = e.clientX - indOff.x + "px";
    indicator.style.top = e.clientY - indOff.y + "px";
    indicator.style.right = "auto";
    indicator.style.bottom = "auto";
  });

  document.addEventListener("mouseup", () => {
    if (indDrag && !indMoved) showHelpPopup();
    indDrag = false;
  });

  // ─── Help popup ────────────────────────────────────────────────────
  const isMac = navigator.platform.indexOf("Mac") !== -1;
  const modKey = isMac ? "Cmd" : "Ctrl";

  function showHelpPopup() {
    if (document.getElementById("annotate-help")) return;

    const help = document.createElement("div");
    help.id = "annotate-help";
    help.innerHTML = `
      <div id="annotate-help-box">
        <div class="annotate-help-title">Annotate — Shortcuts</div>
        <table class="annotate-help-table">
          <tr><th colspan="2">Tools</th></tr>
          <tr><td><kbd>D</kbd></td><td>Draw</td></tr>
          <tr><td><kbd>A</kbd></td><td>Arrow</td></tr>
          <tr><td><kbd>L</kbd></td><td>Line</td></tr>
          <tr><td><kbd>S</kbd></td><td>Square</td></tr>
          <tr><td><kbd>C</kbd></td><td>Circle</td></tr>
          <tr><td><kbd>H</kbd></td><td>Highlight</td></tr>
          <tr><td><kbd>B</kbd></td><td>Blackboard</td></tr>
          <tr><td><kbd>F</kbd></td><td>Text</td></tr>
          <tr><td><kbd>N</kbd></td><td>Number callout</td></tr>
          <tr><th colspan="2">Colors</th></tr>
          <tr><td><kbd>1</kbd></td><td><span class="annotate-swatch" style="background:#ff0000"></span> Red</td></tr>
          <tr><td><kbd>2</kbd></td><td><span class="annotate-swatch" style="background:#2563eb"></span> Blue</td></tr>
          <tr><td><kbd>3</kbd></td><td><span class="annotate-swatch" style="background:#16a34a"></span> Green</td></tr>
          <tr><td><kbd>4</kbd></td><td><span class="annotate-swatch" style="background:#eab308"></span> Yellow</td></tr>
          <tr><td><kbd>5</kbd></td><td><span class="annotate-swatch" style="background:#d1d5db;border:1px solid #9ca3af"></span> Light Grey</td></tr>
          <tr><td><kbd>6</kbd></td><td><span class="annotate-swatch" style="background:#6b7280"></span> Dark Grey</td></tr>
          <tr><th colspan="2">Other</th></tr>
          <tr><td><kbd>R</kbd> <kbd>E</kbd></td><td>Line width / font size (text tool)</td></tr>
          <tr><td><kbd>${modKey}+Z</kbd></td><td>Undo</td></tr>
          <tr><td><kbd>${modKey}+Y</kbd></td><td>Redo</td></tr>
          <tr><td><kbd>${modKey}+A</kbd></td><td>Select all → Delete to clear</td></tr>
          <tr><td><kbd>Esc</kbd></td><td>Exit</td></tr>
        </table>
        <div class="annotate-help-hint">Click anywhere to dismiss</div>
      </div>
    `;
    root.appendChild(help);

    // Click anywhere to dismiss
    function dismiss(e) {
      e.stopPropagation();
      help.remove();
      document.removeEventListener("mousedown", dismiss, true);
    }
    setTimeout(() => {
      document.addEventListener("mousedown", dismiss, true);
    }, 0);
  }

  // ─── Exit dialog ─────────────────────────────────────────────────────
  function showExitDialog() {
    if (document.getElementById("annotate-dialog")) return;

    const dialog = document.createElement("div");
    dialog.id = "annotate-dialog";
    dialog.innerHTML = `
      <p>Save screenshot?</p>
      <div class="annotate-dialog-btns">
        <button class="annotate-btn-yes">Save</button>
        <button class="annotate-btn-no">Exit</button>
      </div>
      <div class="annotate-dialog-countdown">Staying in 4s</div>
    `;
    root.appendChild(dialog);

    let remaining = 4;
    const countdownEl = dialog.querySelector(".annotate-dialog-countdown");
    exitDialogTimer = setInterval(() => {
      remaining--;
      if (remaining <= 0) {
        clearExitDialog(); // dismiss, stay in extension
      } else {
        countdownEl.textContent = `Staying in ${remaining}s`;
      }
    }, 1000);

    dialog.querySelector(".annotate-btn-yes").addEventListener("click", () => {
      clearExitDialog();
      doScreenshotAndClose();
    });

    dialog.querySelector(".annotate-btn-no").addEventListener("click", () => {
      clearExitDialog();
      teardown();
    });
  }

  function clearExitDialog() {
    clearInterval(exitDialogTimer);
    exitDialogTimer = null;
    const d = document.getElementById("annotate-dialog");
    if (d) d.remove();
  }

  // ─── Screenshot + Composite ──────────────────────────────────────────
  async function doScreenshotAndClose() {
    // Hide overlay to capture clean page
    root.style.display = "none";

    // Small delay for repaint
    await new Promise((r) => setTimeout(r, 100));

    try {
      const resp = await chrome.runtime.sendMessage({
        type: "captureVisibleTab",
      });
      if (resp.error) throw new Error(resp.error);

      // Load captured page image
      const pageImg = await loadImage(resp.dataUrl);

      // Create offscreen canvas for compositing
      const offCanvas = document.createElement("canvas");
      offCanvas.width = pageImg.width;
      offCanvas.height = pageImg.height;
      const offCtx = offCanvas.getContext("2d");

      // Draw page
      offCtx.drawImage(pageImg, 0, 0);

      // Draw annotation canvas scaled to match
      offCtx.drawImage(
        canvas,
        0,
        0,
        canvas.width,
        canvas.height,
        0,
        0,
        pageImg.width,
        pageImg.height
      );

      // Convert to blob
      const blob = await new Promise((r) =>
        offCanvas.toBlob(r, "image/png")
      );

      // Copy to clipboard
      try {
        await navigator.clipboard.write([
          new ClipboardItem({ "image/png": blob }),
        ]);
      } catch (_) {
        // Clipboard may not be available in all contexts
      }

      // Download
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      const now = new Date();
      const ts = [
        now.getFullYear(),
        String(now.getMonth() + 1).padStart(2, "0"),
        String(now.getDate()).padStart(2, "0"),
        "-",
        String(now.getHours()).padStart(2, "0"),
        String(now.getMinutes()).padStart(2, "0"),
        String(now.getSeconds()).padStart(2, "0"),
      ].join("");
      a.download = `annotate-${ts}.png`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("Annotate: screenshot failed", err);
    }

    teardown();
  }

  function loadImage(src) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = src;
    });
  }

  // ─── Teardown ────────────────────────────────────────────────────────
  function teardown() {
    document.removeEventListener("keydown", onKeyDown, true);
    root.remove();
    chrome.runtime.sendMessage({ type: "annotate-closed" });
  }

  // ─── Toggle off message from background ──────────────────────────────
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "toggle-off") teardown();
  });

  // ─── Window resize ───────────────────────────────────────────────────
  window.addEventListener("resize", sizeCanvas);
})();
