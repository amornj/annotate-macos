const activeTabs = new Set();

chrome.action.onClicked.addListener(async (tab) => {
  if (activeTabs.has(tab.id)) {
    // Toggle off — send remove message
    try {
      await chrome.tabs.sendMessage(tab.id, { type: "toggle-off" });
    } catch (_) {
      // Content script already gone
    }
    activeTabs.delete(tab.id);
    return;
  }

  // Skip restricted pages
  if (tab.url && (tab.url.startsWith("chrome://") || tab.url.startsWith("chrome-extension://") || tab.url.startsWith("https://chromewebstore.google.com"))) {
    return;
  }

  // Inject CSS then JS
  try {
    await chrome.scripting.insertCSS({
      target: { tabId: tab.id },
      files: ["content.css"],
    });
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content.js"],
    });
    activeTabs.add(tab.id);
  } catch (_) {
    // Injection not allowed on this page
  }
});

// Relay captureVisibleTab requests from content script
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === "captureVisibleTab" && sender.tab) {
    chrome.tabs
      .captureVisibleTab(sender.tab.windowId, { format: "png" })
      .then((dataUrl) => sendResponse({ dataUrl }))
      .catch((err) => sendResponse({ error: err.message }));
    return true; // async response
  }

  if (msg.type === "annotate-closed" && sender.tab) {
    activeTabs.delete(sender.tab.id);
  }
});

// Clean up when tab closes
chrome.tabs.onRemoved.addListener((tabId) => {
  activeTabs.delete(tabId);
});
