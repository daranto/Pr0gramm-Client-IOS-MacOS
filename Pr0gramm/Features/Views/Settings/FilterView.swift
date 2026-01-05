// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// A view, typically presented as a sheet, allowing the user to configure
/// feed type (New/Promoted) and content filters (SFW, NSFW, etc.).
/// Can optionally hide the feed-specific options and the "hide seen items" toggle.
struct FilterView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    let relevantFeedTypeForFilterBehavior: FeedType?
    let hideFeedOptions: Bool
    let showHideSeenItemsToggle: Bool
    
    @State private var newExcludedTag: String = ""


    init(relevantFeedTypeForFilterBehavior: FeedType?, hideFeedOptions: Bool = false, showHideSeenItemsToggle: Bool = true) {
        self.relevantFeedTypeForFilterBehavior = relevantFeedTypeForFilterBehavior
        self.hideFeedOptions = hideFeedOptions
        self.showHideSeenItemsToggle = showHideSeenItemsToggle
    }

    var body: some View {
        NavigationStack {
            Form {
                if !hideFeedOptions || showHideSeenItemsToggle {
                    Section {
                        if !hideFeedOptions {
                            Picker("Feed Typ", selection: $settings.feedType) {
                                ForEach(FeedType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                        .font(UIConstants.bodyFont)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if showHideSeenItemsToggle {
                            Toggle("Nur Frisches anzeigen", isOn: $settings.hideSeenItems)
                                .font(UIConstants.bodyFont)
                        }

                    } header: {
                        Text("Anzeige")
                    } footer: {
                        if showHideSeenItemsToggle {
                             Text("Blendet Posts aus, die du bereits in der Detailansicht geöffnet hast.")
                                .font(UIConstants.footnoteFont)
                        }
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }


                Section {
                    Toggle("SFW", isOn: $settings.showSFW)
                        .font(UIConstants.bodyFont)
                        // SFW kann immer umgeschaltet werden, auch im Junk-Feed.
                        // Die Logik in AppSettings.showSFW.didSet und apiFlags kümmert sich um die korrekte Interpretation.
                    
                    // --- MODIFIED: NSFP Toggle entfernt ---
                    // Der NSFP-Toggle wird nicht mehr angezeigt. Die Logik für NSFP
                    // wird jetzt vollständig durch AppSettings.showSFW (für eingeloggte User außerhalb Junk)
                    // und AppSettings.showNSFP (für Junk-Feed oder ausgeloggte User, falls wir es später wieder brauchen) gesteuert.
                    // Für den Moment bedeutet dies, dass NSFP für eingeloggte User an SFW gekoppelt ist
                    // und für ausgeloggte User ist es sowieso Teil von SFW (Flag 1).
                    // Im Junk-Feed wird NSFP durch `settings.showNSFP` separat gesteuert, falls `settings.showSFW` aus ist.
                    // --- END MODIFICATION ---

                    if authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk {
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            .font(UIConstants.bodyFont)
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             .font(UIConstants.bodyFont)
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             .font(UIConstants.bodyFont)
                    } else if !authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk {
                        Text("Melde dich an, um NSFW/NSFL Filter anzupassen.")
                           .font(UIConstants.bodyFont)
                           .foregroundColor(.secondary)
                    } else if authService.isLoggedIn && relevantFeedTypeForFilterBehavior == .junk {
                        // Im Junk-Feed ist NSFP relevant, falls SFW aus ist.
                        // Da wir den direkten Toggle entfernt haben, kann der User NSFP nur indirekt
                        // über die Startfilter-Einstellung (falls vorhanden) oder den Standardwert beeinflussen.
                        // Für die `FilterView` bedeutet das, dass der User hier nur SFW für den Junk-Feed ein/ausschalten kann.
                        // Wenn SFW aus ist und showNSFP (intern) an, wird Junk-Feed NSFP zeigen.
                        // Wenn SFW an ist, wird Junk-Feed SFW zeigen.
                        // Dies ist eine Vereinfachung basierend auf der Anforderung, den NSFP-Toggle zu entfernen.
                        // Wenn SFW im Junk-Feed aus ist, wird `settings.showNSFP` entscheiden, ob NSFP-Content (Flag 8) geladen wird.
                        // Der User hat hier keinen direkten Einfluss mehr auf `settings.showNSFP` im Junk-Fall,
                        // außer `settings.showSFW` zu toggeln, was dann `settings.showNSFP` für Junk nicht beeinflusst.
                        // Diese Logik ist etwas implizit geworden.
                         Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                            .font(UIConstants.bodyFont)
                            .disabled(settings.showSFW) // NSFP nur wählbar, wenn SFW im Junk aus ist
                    }

                } header: {
                    Text("Inhaltsfilter")
                } footer: {
                    if authService.isLoggedIn && relevantFeedTypeForFilterBehavior == .junk {
                        Text("Im 'Müll'-Feed werden SFW oder NSFP Inhalte angezeigt. Wenn SFW aktiv ist, hat es Vorrang.")
                            .font(UIConstants.footnoteFont)
                    } else if authService.isLoggedIn {
                        Text("SFW beinhaltet bei eingeloggten Nutzern automatisch auch NSFP.")
                            .font(UIConstants.footnoteFont)
                    } else {
                        Text("Für ausgeloggte Nutzer wird nur SFW (inkl. NSFP) Inhalt angezeigt.")
                            .font(UIConstants.footnoteFont)
                    }
                }
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                
                // Neue Section für ausgeschlossene Tags
                Section {
                    ForEach($settings.excludedTags) { $tag in
                        HStack {
                            Toggle(isOn: $tag.isEnabled) {
                                Text(tag.name)
                                    .font(UIConstants.bodyFont)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                            
                            Button(action: {
                                settings.excludedTags.removeAll { $0.id == tag.id }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack {
                        TextField("Tag hinzufügen", text: $newExcludedTag)
                            .font(UIConstants.bodyFont)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                addExcludedTag()
                            }
                        
                        Button(action: addExcludedTag) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(settings.accentColorChoice.swiftUIColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newExcludedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Tags ausschließen")
                } footer: {
                    Text("Aktivierte Tags werden aus dem Feed gefiltert. Deaktiviere Tags, um sie temporär zu erlauben.")
                        .font(UIConstants.footnoteFont)
                }
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .font(UIConstants.bodyFont)
                }
            }
        }
    }
    
    private func addExcludedTag() {
        let trimmedTag = newExcludedTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }
        guard !settings.excludedTags.contains(where: { $0.name.lowercased() == trimmedTag.lowercased() }) else {
            newExcludedTag = ""
            return
        }
        settings.excludedTags.append(ExcludedTag(name: trimmedTag, isEnabled: true))
        newExcludedTag = ""
    }
}

// MARK: - Previews

#Preview("Feed Context (Logged In, Feed=Promoted)") {
    let previewSettings = AppSettings()
    previewSettings.feedType = .promoted
    previewSettings.showSFW = true
    previewSettings.showNSFP = true
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: previewSettings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Feed Context (Logged In, Feed=Junk)") {
    let previewSettings = AppSettings()
    previewSettings.feedType = .junk
    previewSettings.showSFW = false // Teste den Fall, wo NSFP aktiv sein könnte
    previewSettings.showNSFP = true
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: previewSettings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Logged Out (relevantFeedType = .promoted)") {
    let previewSettings = AppSettings()
    previewSettings.showSFW = true // Standard für ausgeloggt
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = false
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: false)
    return FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
