# Pr0gramm iOS & macOS App

Eine in SwiftUI geschriebene App für iOS und Mac (Apple Silicon Macs) für den Zugriff auf pr0gramm.com mit Fokus auf Performance, Bedienbarkeit und moderne Technologien.

##  Installation

Testflight Link: https://testflight.apple.com/join/41yj2PYp

## 📱 Features

**Kernfunktionen & Browsing:**

*   **Feed-Ansicht:** Durchstöbere den "Neu"- oder "Beliebt"-Feed von pr0gramm.
*   **Grid-Layout:** Übersichtliche Darstellung der Posts in einem Raster.
*   **Endloses Scrollen:** Lade automatisch ältere Posts nach, wenn du das Ende des Feeds erreichst.
*   **Pull-to-Refresh:** Aktualisiere den Feed einfach durch Herunterziehen.

**Medienwiedergabe:**

*   **Bilder:** Betrachte Bilder im Detail, inklusive Vollbildmodus mit Zoom- und Schwenk-Funktion.
*   **Videos:** Integrierter Video-Player für MP4- und WebM-Dateien (soweit vom System unterstützt).
*   **Untertitel:** Automatische oder manuelle Anzeige von VTT-Untertiteln, falls verfügbar.
*   **Video-Steuerung:** Stummschaltung (auch optional beim Start), Tastatursteuerung zum Spulen (Pfeiltasten Hoch/Runter in der Detailansicht).

**Interaktion & Community:**

*   **Kommentare:** Lese und schreibe Kommentare, übersichtliche hierarchische Darstellung, Einklappen von Threads.
*   **Tags:** Zeige Tags zu Posts an und starte eine Suche durch Tippen auf einen Tag.
*   **Bewerten:** Bewerte Posts und Kommentare mit Up-/Downvotes (Benis).
*   **Favorisieren:** Markiere Posts und Kommentare als Favoriten.
*   **Antworten:** Antworte direkt auf Kommentare.
*   **Nutzer markieren:** Erwähnungen mit `@nutzername` öffnen in Kommentaren und Nachrichten das Profil direkt in der App.
*   **Highlighting:** Kommentare des Original-Posters (OP) werden hervorgehoben.
*   **Kontextmenüs:** Schneller Zugriff auf Aktionen wie Antworten, Bewerten, Favorisieren und Profil anzeigen für Kommentare.

**Benutzerkonto & Profil:**

*   **Login/Logout:** Sichere Anmeldung über Keychain-Speicherung der Sitzung.
*   **Eigenes Profil:** Zeige dein Profil mit Rang, Benis, Registrierungsdatum und Abzeichen (Badges) an.
*   **Eigene Uploads:** Betrachte deine hochgeladenen Posts.
*   **Favoriten:** Zeige deine favorisierten Posts an, inklusive Auswahl verschiedener Favoriten-Sammlungen (falls vorhanden).
*   **Sammlungen:** Verwalte und betrachte deine Post-Sammlungen.
*   **Gelikete Kommentare:** Finde alle Kommentare, die du favorisiert hast.
*   **Postfach (Inbox):** Lese private Nachrichten, Kommentarantworten und Follower-Benachrichtigungen.
*   **Nutzerprofile:** Betrachte die Profile anderer Nutzer (Basisinfos, Uploads, Kommentare) direkt aus der App heraus (z.B. über Kommentare).

**Performance & Synchronisation:**

*   **Bild-Caching:** Schnelles Laden von Bildern durch aggressives Caching mit [Kingfisher](https://github.com/onevcat/Kingfisher).
*   **Daten-Caching:** Zwischenspeicherung von Feed-Daten, Favoriten etc. zur Verbesserung der Ladezeiten und Offline-Verfügbarkeit (mit Größenlimit und LRU-Bereinigung).
*   **iCloud Sync:** Synchronisiert den Status angesehener Posts über deine Geräte via iCloud Key-Value Store.

## ⚙️ Verwendete Swift Packages

*   [Kingfisher](https://github.com/onevcat/Kingfisher) – Für performantes Laden und Caching von Bildern.

## 📄 Lizenz

Diese App steht unter der [MIT-Lizenz](LICENSE).

> **Hinweis**: Pr0gramm ist ein unabhängiges Angebot. Dieses Projekt ist **nicht offiziell** mit pr0gramm.com verbunden.
