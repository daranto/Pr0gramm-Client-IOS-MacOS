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


    init(relevantFeedTypeForFilterBehavior: FeedType?, hideFeedOptions: Bool = false, showHideSeenItemsToggle: Bool = true) {
        self.relevantFeedTypeForFilterBehavior = relevantFeedTypeForFilterBehavior
        self.hideFeedOptions = hideFeedOptions
        self.showHideSeenItemsToggle = showHideSeenItemsToggle
    }

    var body: some View {
        NavigationStack {
            Form {
                // --- MODIFIED: Section für Feed Typ und "Nur Frisches anzeigen" ---
                // Die Section wird angezeigt, wenn entweder Feed-Optionen gezeigt werden sollen ODER der "Nur Frisches anzeigen"-Toggle gezeigt werden soll
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

                        // "Nur Frisches anzeigen" wird jetzt immer angeboten, wenn showHideSeenItemsToggle true ist
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
                // --- END MODIFICATION ---


                Section {
                    Toggle("SFW", isOn: $settings.showSFW)
                        .font(UIConstants.bodyFont)
                        .disabled(relevantFeedTypeForFilterBehavior == .junk && authService.isLoggedIn)
                        .onChange(of: settings.showSFW) { _, newValue in
                            if authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk && newValue {
                                settings.showNSFP = true
                            }
                            else if authService.isLoggedIn && relevantFeedTypeForFilterBehavior != .junk && !newValue {
                                settings.showNSFP = false
                            }
                        }
                    
                    if !authService.isLoggedIn || (relevantFeedTypeForFilterBehavior == .junk && authService.isLoggedIn) {
                        Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP)
                             .font(UIConstants.bodyFont)
                             .disabled(relevantFeedTypeForFilterBehavior == .junk && authService.isLoggedIn)
                    }

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
                    }
                } header: {
                    Text("Inhaltsfilter")
                } footer: {
                    if authService.isLoggedIn && relevantFeedTypeForFilterBehavior == .junk {
                        Text("Im 'Müll'-Feed werden nur SFW und NSFP Inhalte angezeigt. Andere Filter sind hier nicht anwendbar.")
                            .font(UIConstants.footnoteFont)
                    } else if authService.isLoggedIn {
                        Text("SFW beinhaltet bei eingeloggten Nutzern automatisch auch NSFP.")
                            .font(UIConstants.footnoteFont)
                    } else {
                        Text("Für ausgeloggte Nutzer wird nur SFW Inhalt angezeigt. NSFP ist ein Teil von SFW. Melde dich an für mehr Optionen.")
                            .font(UIConstants.footnoteFont)
                    }
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
}

// MARK: - Previews

#Preview("Feed Context (Logged In, Feed=Promoted)") {
    let previewSettings = AppSettings()
    // enableExperimentalHideSeen wird nicht mehr gesetzt
    previewSettings.feedType = .promoted
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: previewSettings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Feed Context (Logged In, Feed=Junk)") {
    let previewSettings = AppSettings()
    // enableExperimentalHideSeen wird nicht mehr gesetzt
    previewSettings.feedType = .junk
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: previewSettings.feedType, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Favorites Context (Logged In)") {
    let previewSettings = AppSettings()
    // enableExperimentalHideSeen wird nicht mehr gesetzt
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: nil, hideFeedOptions: true, showHideSeenItemsToggle: false) // showHideSeenItemsToggle hier false, da es in Favorites nicht relevant ist
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Search Context (Logged In, SearchFeedType=Promoted)") {
    let previewSettings = AppSettings()
    // enableExperimentalHideSeen wird nicht mehr gesetzt
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = true
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: true)
    return FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: true, showHideSeenItemsToggle: false) // showHideSeenItemsToggle hier false
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}

#Preview("Logged Out (relevantFeedType = .promoted)") {
    let previewSettings = AppSettings()
    // enableExperimentalHideSeen wird nicht mehr gesetzt
    let previewAuthService = AuthService(appSettings: previewSettings)
    previewAuthService.isLoggedIn = false
    previewSettings.updateUserLoginStatusForApiFlags(isLoggedIn: false)
    return FilterView(relevantFeedTypeForFilterBehavior: .promoted, hideFeedOptions: false, showHideSeenItemsToggle: true)
        .environmentObject(previewSettings)
        .environmentObject(previewAuthService)
}
// --- END OF COMPLETE FILE ---
