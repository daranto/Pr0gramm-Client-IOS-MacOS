# Dismiss Button Style Guide

Dieses Dokument definiert die einheitliche Verwendung von Dismiss-Buttons in der App.

## Grundregeln

### 1. Sheet-Views mit einzelnem Dismiss-Button
**Verwenden Sie:** `"Fertig"` mit `placement: .confirmationAction`

```swift
.toolbar {
    ToolbarItem(placement: .confirmationAction) {
        Button("Fertig") {
            dismiss()
        }
    }
}
```

**Beispiele:**
- `PagedDetailView` (wenn `isPresentedInSheet: true`)
- `UserProfileSheetView`
- `AllTagsSheetView`
- `LinkedItemPreviewWrapperView` (entfernt, da `PagedDetailView` den Button übernimmt)
- User Uploads/Comments Sheet Views
- Conversation Detail Sheet (wenn als Sheet präsentiert)

### 2. Dialoge mit Abbrechen-Option
**Verwenden Sie:** `"Abbrechen"` mit `placement: .cancellationAction` + optional ein zweiter Button

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Abbrechen") {
            dismiss()
        }
    }
    ToolbarItem(placement: .confirmationAction) {
        Button("Senden") {
            // Aktion
        }
    }
}
```

**Beispiele:**
- `CollectionSelectionView` (hat "Abbrechen", da es eine Auswahl-Action ist)
- `CommentInputView` (hat "Abbrechen" + "Senden")

### 3. Vermeiden Sie
❌ Gemischte Begriffe wie "Schließen", "X", "Close"
❌ Mehrere "Fertig"-Buttons übereinander (z.B. durch verschachtelte NavigationStacks)
❌ Unterschiedliche Begriffe für die gleiche Funktionalität

## Checkliste für neue Views

Wenn Sie eine neue Sheet-View erstellen:

1. ☐ Ist es ein einfacher Dismiss? → Verwenden Sie "Fertig"
2. ☐ Gibt es eine Abbruch-Aktion (z.B. Input-Form)? → Verwenden Sie "Abbrechen"
3. ☐ Ist die View bereits in einem NavigationStack mit eigenem Button? → Prüfen Sie auf Duplikate
4. ☐ Verwenden Sie `.confirmationAction` für "Fertig" Buttons
5. ☐ Verwenden Sie `.cancellationAction` für "Abbrechen" Buttons

## Aktuelle Implementierungen

### Views mit "Fertig" Button
- ✅ `PagedDetailView` (Line 338)
- ✅ `UserProfileSheetView` (Line 79)
- ✅ `AllTagsSheetView` (Line 124)
- ✅ `InboxView` -> Preview Link Sheet (Line 158)
- ✅ User Uploads Sheet (UserProfileSheetView Line 174)
- ✅ User Comments Sheet (UserProfileSheetView Line 182)
- ✅ Conversation Detail Sheet (UserProfileSheetView Line 189)

### Views mit "Abbrechen" Button
- ✅ `CollectionSelectionView` (Line 70) - Hat "Abbrechen" weil es eine Auswahl ist
- ✅ `CommentInputView` (Line 50) - Hat "Abbrechen" + "Senden" als Input-Form

### Views ohne eigenen Button
- ✅ `LinkedItemPreviewWrapperView` - Button wurde entfernt, da `PagedDetailView` ihn bereitstellt
- ✅ `LinkedItemPreviewView` - Wird von Wrapper umschlossen, kein eigener Button nötig

## Behobene Probleme

### Problem: Doppelte "Fertig" Buttons
**Ursache:** `LinkedItemPreviewWrapperView` hatte einen eigenen "Fertig"-Button, obwohl die eingebettete `PagedDetailView` bereits einen hatte.

**Lösung:** Button aus `LinkedItemPreviewWrapperView` entfernt (Commit vom 11.11.2025)

**Betroffene Dateien:**
- `PagedDetailView.swift` (Line 1077-1095)
