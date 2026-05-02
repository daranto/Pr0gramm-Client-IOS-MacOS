// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

enum HideSeenItemsToggleContext {
    case feed
    case search
}

/// A view, typically presented as a sheet, allowing the user to configure
/// feed type (New/Promoted) and content filters (SFW, NSFW, etc.).
/// Can optionally hide the feed-specific options and the "hide seen items" toggle.
struct FilterView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(AuthService.self) var authService
    @Environment(\.dismiss) var dismiss

    let relevantFeedTypeForFilterBehavior: FeedType?
    let hideFeedOptions: Bool
    let hideSeenItemsToggleContext: HideSeenItemsToggleContext?
    let showExcludedTagsSection: Bool
    
    @State private var newExcludedTag: String = ""

    init(relevantFeedTypeForFilterBehavior: FeedType?, hideFeedOptions: Bool = false, hideSeenItemsToggleContext: HideSeenItemsToggleContext? = .feed, showExcludedTagsSection: Bool = true) {
        self.relevantFeedTypeForFilterBehavior = relevantFeedTypeForFilterBehavior
        self.hideFeedOptions = hideFeedOptions
        self.hideSeenItemsToggleContext = hideSeenItemsToggleContext
        self.showExcludedTagsSection = showExcludedTagsSection
    }

    var body: some View {
        @Bindable var settings = appSettings
        NavigationStack {
            Form {
                if !hideFeedOptions || hideSeenItemsToggleContext != nil {
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

                        if let hideSeenItemsToggleContext {
                            Toggle("Nur Frisches anzeigen", isOn: hideSeenItemsBinding(for: hideSeenItemsToggleContext))
                                .font(UIConstants.bodyFont)
                                .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                        }

                    } header: {
                        Text("Anzeige")
                    } footer: {
                        if let hideSeenItemsToggleContext {
                             Text(hideSeenItemsFooterText(for: hideSeenItemsToggleContext))
                                .font(UIConstants.footnoteFont)
                        }
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }


                Section {
                    Toggle("SFW", isOn: $settings.showSFW)
                        .font(UIConstants.bodyFont)
                        .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
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

                    if authService.isLoggedIn {
                        // Alle Filter für eingeloggte User anzeigen, unabhängig vom Feed-Typ
                        Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                            .font(UIConstants.bodyFont)
                            .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                        Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                             .font(UIConstants.bodyFont)
                             .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                        Toggle("POL (Politik)", isOn: $settings.showPOL)
                             .font(UIConstants.bodyFont)
                             .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                        
                        // NSFP Toggle nur im Junk-Feed anzeigen
                        if relevantFeedTypeForFilterBehavior == .junk {
                            Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                                .font(UIConstants.bodyFont)
                                .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                                .disabled(settings.showSFW) // NSFP nur wählbar, wenn SFW im Junk aus ist
                        }
                    } else {
                        // Nachricht für nicht eingeloggte User
                        Text("Melde dich an, um NSFW/NSFL Filter anzupassen.")
                           .font(UIConstants.bodyFont)
                           .foregroundColor(.secondary)
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
                if showExcludedTagsSection {
                    Section {
                        ForEach(Array(settings.excludedTags.enumerated()), id: \.element.id) { index, tag in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { 
                                        guard index < settings.excludedTags.count else { return false }
                                        return settings.excludedTags[index].isEnabled 
                                    },
                                    set: { newValue in
                                        guard index < settings.excludedTags.count else { return }
                                        settings.excludedTags[index].isEnabled = newValue
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "tag.fill")
                                            .foregroundColor(settings.accentColorChoice.swiftUIColor)
                                            .font(.caption)
                                        
                                        Text(tag.name)
                                            .font(UIConstants.bodyFont)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: settings.accentColorChoice.swiftUIColor))
                                
                                Button(action: {
                                    removeExcludedTag(withId: tag.id)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onDelete(perform: deleteExcludedTags)
                        
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
                        if relevantFeedTypeForFilterBehavior == .junk {
                            Text("Ausgeschlossene Tags gelten nur für 'Neu' und 'Beliebt', nicht für 'Müll'.")
                                .font(UIConstants.footnoteFont)
                        } else {
                            Text("Aktivierte Tags werden aus dem Feed gefiltert. Deaktiviere Tags, um sie temporär zu erlauben.")
                                .font(UIConstants.footnoteFont)
                        }
                    }
                     .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }
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
        guard !appSettings.excludedTags.contains(where: { $0.name.lowercased() == trimmedTag.lowercased() }) else {
            newExcludedTag = ""
            return
        }
        withAnimation {
            appSettings.excludedTags.append(ExcludedTag(name: trimmedTag, isEnabled: true))
        }
        newExcludedTag = ""
    }
    
    private func removeExcludedTag(withId id: UUID) {
        withAnimation {
            appSettings.excludedTags.removeAll { $0.id == id }
        }
    }
    
    private func deleteExcludedTags(at offsets: IndexSet) {
        withAnimation {
            appSettings.excludedTags.remove(atOffsets: offsets)
        }
    }

    private func hideSeenItemsBinding(for context: HideSeenItemsToggleContext) -> Binding<Bool> {
        Binding(
            get: {
                switch context {
                case .feed:
                    appSettings.hideSeenItems
                case .search:
                    appSettings.hideSeenItemsInSearch
                }
            },
            set: { newValue in
                switch context {
                case .feed:
                    appSettings.hideSeenItems = newValue
                case .search:
                    appSettings.hideSeenItemsInSearch = newValue
                }
            }
        )
    }

    private func hideSeenItemsFooterText(for context: HideSeenItemsToggleContext) -> String {
        switch context {
        case .feed:
            "Blendet Posts im Mainfeed aus, die du bereits in der Detailansicht geöffnet hast."
        case .search:
            "Blendet Posts in der Suche aus, die du bereits in der Detailansicht geöffnet hast."
        }
    }
}

// MARK: - Previews

#Preview("Feed Context (Logged In, Feed=Promoted)") {
    @Previewable @State var previewSettings = AppSettings()
    @Previewable @State var previewAuthService = AuthService(appSettings: AppSettings())
    
    FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: false, hideSeenItemsToggleContext: .feed)
        .environment(previewSettings)
        .environment(previewAuthService)
        .task {
            previewSettings.feedType = .promoted
            previewSettings.showSFW = true
            previewSettings.showNSFP = true
            previewAuthService.isLoggedIn = true
            previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
        }
}

#Preview("Feed Context (Logged In, Feed=Junk)") {
    @Previewable @State var previewSettings = AppSettings()
    @Previewable @State var previewAuthService = AuthService(appSettings: AppSettings())
    
    FilterView(relevantFeedTypeForFilterBehavior: .junk, hideFeedOptions: false, hideSeenItemsToggleContext: .feed)
        .environment(previewSettings)
        .environment(previewAuthService)
        .task {
            previewSettings.feedType = .junk
            previewSettings.showSFW = false
            previewSettings.showNSFP = true
            previewAuthService.isLoggedIn = true
            previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
        }
}

#Preview("Logged Out (relevantFeedType = .promoted)") {
    @Previewable @State var previewSettings = AppSettings()
    @Previewable @State var previewAuthService = AuthService(appSettings: AppSettings())
    
    FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: false, hideSeenItemsToggleContext: .feed)
        .environment(previewSettings)
        .environment(previewAuthService)
        .task {
            previewSettings.showSFW = true
            previewAuthService.isLoggedIn = false
            previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: false)
        }
}
// --- END OF COMPLETE FILE ---
