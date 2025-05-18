// Pr0gramm/Pr0grammRedirectoriOS/Resources/background.js
// --- START OF COMPLETE FILE ---
try {
  console.log("Pr0grammRedirector: Background service worker started (content script handles redirect).");

  // Optional: Listener für Nachrichten vom Popup oder Content Script, falls später benötigt.
  browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("Pr0grammRedirector: Message received in (minimal) background.js", request);
    // Hier keine Aktionen für den Redirect, da content.js das macht.
    if (request.action === "ping") {
        sendResponse({ status: "pong" });
    }
    return true;
  });

} catch (e) {
  console.error("Pr0grammRedirector: Error in background.js", e);
}
// --- END OF COMPLETE FILE ---
