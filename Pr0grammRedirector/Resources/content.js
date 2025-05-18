// Pr0gramm/Pr0grammRedirectoriOS/Resources/content.js
// --- START OF COMPLETE FILE ---
const APP_URL_SCHEME = "pr0grammapp";

function parsePr0grammLink(url) {
    try {
        const parsedUrl = new URL(url);
        const path = parsedUrl.pathname; // z.B. /new/12345 oder /top/12345 oder /12345
        const searchParams = parsedUrl.searchParams;

        // Regex für URLs wie:
        // /new/12345
        // /top/12345
        // /12345
        // /new/12345:comment67890
        // /top/12345:comment67890
        // /12345:comment67890
        // Wichtig: Der optionale Teil nach :comment muss auch das Ende des Pfades sein oder von Query-Parametern gefolgt werden.
        const itemCommentRegex = /^\/(?:new\/|top\/)?(\d+)(?:[:]\w*?(\d+))?(?:[/?#]|$)/i;
        // Die Regex oben wurde angepasst: `[:]\w*?(\d+)` fängt jetzt :commentXXXX, :benishyYYYY etc.
        // Wir interessieren uns nur für :commentXXXX, daher prüfen wir das später.

        // Alternative, spezifischere Regex, die nur auf ":comment" achtet:
        // const itemCommentRegex = /^\/(?:new\/|top\/)?(\d+)(?::comment(\d+))?(?:[/?#]|$)/i;
        
        let match = path.match(itemCommentRegex);
        
        // Fallback für URLs, die nur /12345 (ohne /new oder /top) sind und einen Kommentar haben könnten
        // z.B. pr0gramm.com/12345:comment67890
        if (!match && /^\/(\d+):comment(\d+)/i.test(path)) {
            const simpleItemCommentRegex = /^\/(\d+):comment(\d+)/i;
            match = path.match(simpleItemCommentRegex);
            if (match) {
                // Neu zuordnen, da die Gruppen unterschiedlich sind
                const itemId = match[1];
                const commentId = match[2];
                console.log("Pr0grammRedirector: Matched simple item/comment path:", itemId, commentId);
                return { itemId, commentId };
            }
        }


        if (match) {
            const itemId = match[1];
            let commentId = null;

            // Überprüfen, ob der zweite gefangene Teil tatsächlich eine Kommentar-ID ist.
            // Die ursprüngliche Regex fängt jede Zahl nach einem Doppelpunkt.
            // Wir müssen sicherstellen, dass es sich um ":comment<ZAHL>" handelt.
            const potentialCommentPart = path.substring(match[0].indexOf(match[1]) + match[1].length);
            if (potentialCommentPart.toLowerCase().startsWith(":comment")) {
                const commentIdMatch = potentialCommentPart.match(/:comment(\d+)/i);
                if (commentIdMatch && commentIdMatch[1]) {
                    commentId = commentIdMatch[1];
                }
            } else if (match[2]) { // Wenn die allgemeinere Regex eine zweite Gruppe gefangen hat
                 // und es nicht :comment war, ignorieren wir es.
                 // Es sei denn, deine URL-Struktur für Kommentare ist anders (z.B. nur /item/:commentid)
            }
            
            console.log("Pr0grammRedirector: Matched standard path:", itemId, commentId);
            return { itemId, commentId };
        }

        // Fallback für URLs wie pr0gramm.com/?id=ITEM_ID (oft von externen Links)
        // Diese haben typischerweise keine Kommentar-ID im Pfad.
        if ((path === "/" || path === "") && searchParams.has("id")) {
            const itemId = searchParams.get("id");
            if (itemId && /^\d+$/.test(itemId)) { // Sicherstellen, dass es eine Zahl ist
                console.log("Pr0grammRedirector: Matched query param:", itemId);
                return { itemId, commentId: null };
            }
        }

        console.log("Pr0grammRedirector: No pr0gramm item/comment pattern matched for URL:", url);
        return null; // Keine Übereinstimmung
    } catch (e) {
        console.error("Pr0grammRedirector: Error parsing URL:", url, e);
        return null;
    }
}

function checkAndRedirect() {
  const currentUrl = window.location.href;
  console.log("Pr0grammRedirector: content.js checking URL:", currentUrl);

  // Verhindern von Redirect-Schleifen, falls die App nicht installiert ist
  // oder der Redirect fehlschlägt und Safari zur Original-URL zurückkehrt.
  if (sessionStorage.getItem(`pr0grammRedirectAttempted_${currentUrl}`) === "true") {
    console.log("Pr0grammRedirector: Redirect already attempted for this URL in this session. Aborting.");
    sessionStorage.removeItem(`pr0grammRedirectAttempted_${currentUrl}`); // Reset für nächsten manuellen Aufruf
    return;
  }

  const parts = parsePr0grammLink(currentUrl);

  if (parts && parts.itemId) {
    let appUrl = `${APP_URL_SCHEME}://item/${parts.itemId}`;
    if (parts.commentId) {
      appUrl += `?commentId=${parts.commentId}`;
    }

    console.log(`Pr0grammRedirector: Match found. Attempting redirect to: ${appUrl}`);
    sessionStorage.setItem(`pr0grammRedirectAttempted_${currentUrl}`, "true");
    window.location.replace(appUrl);
  } else {
    console.log("Pr0grammRedirector: No redirect needed for this URL.");
  }
}

// Führe die Prüfung aus, sobald das Skript geladen wird.
// `run_at: document_start` im Manifest sorgt dafür, dass es früh passiert.
checkAndRedirect();
// --- END OF COMPLETE FILE ---
