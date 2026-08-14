# Projektanweisungen

## App-Changelog („Neuigkeiten“)

- Der nutzerseitige Changelog befindet sich in `Pr0gramm/Pr0grammApp.swift` unter `WhatsNewView.features`.
- Neue Einträge werden oben ergänzt und kurz auf Deutsch formuliert. Jeder Eintrag enthält Datum, SF Symbol, Titel und Beschreibung.
- Nach neuen Changelog-Einträgen muss `AppRootView.whatsNewContentVersion` erhöht werden. Dadurch erscheint der Neuigkeiten-Dialog nach dem App-Start einmalig erneut.
- `MARKETING_VERSION` nur ändern, wenn ausdrücklich eine neue App-Version gewünscht ist.
- Keine separate `CHANGELOG.md` anlegen, außer sie wird ausdrücklich zusätzlich verlangt.
