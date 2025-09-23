// Pr0gramm/Pr0gramm/Features/Views/Settings/SettingsView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os


/// View for displaying and modifying application settings, including cache management.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var showingClearAllCacheAlert = false
    @State private var showingClearSeenItemsAlert = false

    let cacheSizeOptions = [50, 100, 250, 500, 1000] // In MB
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SettingsView")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Farbschema", selection: $settings.colorSchemeSetting) {
                        ForEach(ColorSchemeSetting.allCases) { scheme in
                            Text(scheme.displayName).tag(scheme)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)

                    Picker("Rastergröße (Posts pro Zeile)", selection: $settings.gridSize) {
                        ForEach(GridSizeSetting.allCases) { size in
                            Text(size.displayName).tag(size)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)
                    
                    Picker("Akzentfarbe", selection: $settings.accentColorChoice) {
                        ForEach(AccentColorChoice.allCases) { colorChoice in
                            HStack {
                                Text( colorChoice.displayName)
                                Spacer()
                                Circle()
                                    .fill(colorChoice.swiftUIColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle().stroke(Color.secondary, lineWidth: colorChoice == .blue ? 0 : 0.5)
                                    )
                            }
                            .tag(colorChoice)
                            .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)
                    if UIConstants.isCurrentDeviceiPhone {
                        Toggle("pr0Tok aktivieren", isOn: $settings.enableUnlimitedStyleFeed)
                            .font(UIConstants.bodyFont)
                    }
                    
                    if UIConstants.isPadOrMac {
                        Toggle("iPhone-Layout auf iPad/Mac erzwingen", isOn: $settings.forcePhoneLayoutOnPadAndMac)
                            .font(UIConstants.bodyFont)
                    }
                } header: {
                    Text("Darstellung")
                } footer: {
                    if UIConstants.isPadOrMac {
                        Text("Zeigt in der Detailansicht eine zentrierte Einzelspalten-Ansicht anstelle der optimierten Mehrspalten-Ansicht.")
                            .font(UIConstants.footnoteFont)
                    }
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

                if authService.isLoggedIn {
                    Section {
                        Toggle("Eigene Filter beim App-Start", isOn: $settings.enableStartupFilters)
                            .font(UIConstants.bodyFont)
                        
                        if settings.enableStartupFilters {
                            Group {
                                Toggle("SFW anzeigen", isOn: $settings.startupFilterSFW)
                                Toggle("NSFW anzeigen", isOn: $settings.startupFilterNSFW)
                                Toggle("NSFL anzeigen", isOn: $settings.startupFilterNSFL)
                                Toggle("POL anzeigen", isOn: $settings.startupFilterPOL)
                            }
                            .font(UIConstants.bodyFont)
                            .padding(.leading)
                        }
                    } header: {
                        Text("Filter beim App-Start")
                    } footer: {
                        Text("Legt fest, welche Inhaltsfilter beim Öffnen der App automatisch aktiv sein sollen. SFW beinhaltet bei eingeloggten Nutzern automatisch auch NSFP (Not Safe For Public).")
                            .font(UIConstants.footnoteFont)
                    }
                    .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }


                Section {
                    Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                        .font(UIConstants.bodyFont)

                    Picker("Untertitel", selection: $settings.subtitleActivationMode) {
                        ForEach(SubtitleActivationMode.allCases) { mode in
                             Text(mode.displayName).tag(mode)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)

                } header: {
                     Text("Video & Ton")
                } footer: {
                     Text("Legt fest, ob für Videos standardmäßig Untertitel angezeigt werden sollen, falls verfügbar.")
                        .font(UIConstants.footnoteFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                
                Section {
                    Toggle("Hintergrundaktualisierung für Nachrichten", isOn: $settings.enableBackgroundFetchForNotifications)
                        .font(UIConstants.bodyFont)
                    
                    if settings.enableBackgroundFetchForNotifications {
                        Picker("Abrufintervall (ca.)", selection: $settings.backgroundFetchInterval) {
                            ForEach(BackgroundFetchInterval.allCases) { interval in
                                Text(interval.displayName).tag(interval)
                                    .font(UIConstants.bodyFont)
                            }
                        }
                        .font(UIConstants.bodyFont)
                    }
                } header: {
                    Text("Benachrichtigungen")
                } footer: {
                    Text("Erlaubt der App, im Hintergrund nach neuen Nachrichten zu suchen und dich per Push-Benachrichtigung zu informieren. iOS entscheidet letztendlich, wann und wie oft die App tatsächlich im Hintergrund ausgeführt wird, um Akku zu sparen. Das gewählte Intervall ist eine Empfehlung an das System.\nDie Berechtigung für Mitteilungen wird angefragt, sobald du die Hintergrundaktualisierung aktivierst.")
                       .font(UIConstants.footnoteFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)


                Section("Kommentare") {
                    Picker("Sortierung", selection: $settings.commentSortOrder) {
                        ForEach(CommentSortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

                if authService.isLoggedIn && !authService.userCollections.isEmpty {
                    Section("Favoriten-Standardordner") {
                        Picker("Als Favoriten verwenden", selection: $settings.selectedCollectionIdForFavorites) {
                            ForEach(authService.userCollections) { collection in
                                Text(collection.name).tag(collection.id as Int?)
                                    .font(UIConstants.bodyFont)
                            }
                        }
                        .font(UIConstants.bodyFont)
                        .onChange(of: settings.selectedCollectionIdForFavorites) { _, newId in
                            SettingsView.logger.info("User selected collection ID \(newId != nil ? String(newId!) : "nil") as favorite default.")
                            if newId == nil && !authService.userCollections.isEmpty {
                                SettingsView.logger.warning("selectedCollectionIdForFavorites became nil unexpectedly. Attempting to re-select default.")
                                if let defaultColl = authService.userCollections.first(where: { $0.isActuallyDefault }) ?? authService.userCollections.first {
                                    settings.selectedCollectionIdForFavorites = defaultColl.id
                                }
                            }
                        }
                    }
                    .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }

            
                Section {
                    Button("Gesehene Posts zurücksetzen", role: .destructive) {
                        showingClearSeenItemsAlert = true
                    }
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                     Text("Anzeige-Verlauf")
                } footer: {
                     Text("Entfernt die Markierungen für bereits angesehene Bilder und Videos. Die Posts erscheinen wieder als 'neu', wenn 'Nur Frisches anzeigen' deaktiviert ist, oder werden wieder im Feed berücksichtigt, wenn es aktiv ist.")
                        .font(UIConstants.footnoteFont)
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)


                Section {
                    HStack {
                        Text("Bild-Cache Größe")
                            .font(UIConstants.bodyFont)
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentImageDataCacheSizeMB))
                            .font(UIConstants.bodyFont)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Daten-Cache Größe")
                            .font(UIConstants.bodyFont)
                        Spacer()
                        Text(String(format: "%.1f MB", settings.currentDataCacheSizeMB))
                            .font(UIConstants.bodyFont)
                            .foregroundColor(.secondary)
                    }
                    Picker("Max. Bild-Cache Größe", selection: $settings.maxImageCacheSizeMB) {
                        ForEach(cacheSizeOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                                .font(UIConstants.bodyFont)
                        }
                    }
                    .font(UIConstants.bodyFont)
                    .onChange(of: settings.maxImageCacheSizeMB) { _, _ in
                        Self.logger.info("Max image cache size setting changed.")
                    }
                    Button("Gesamten App-Cache leeren", role: .destructive) {
                        showingClearAllCacheAlert = true
                    }
                    .font(UIConstants.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("Cache")
                } footer: {
                    Text("Der Bild-Cache (Kingfisher) wird automatisch auf die gewählte Maximalgröße begrenzt. Der Daten-Cache (Feeds etc.) hat ein festes Limit von 50 MB und löscht die ältesten Einträge bei Überschreitung (LRU). 'Gesamten App-Cache leeren' löscht Bilder, Daten und auch die Gesehen-Markierungen.")
                        .font(UIConstants.footnoteFont)
                }
                 .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)

                Section {
                    NavigationLink(destination: LicenseAndDependenciesView()) {
                        Text("Lizenzen & Abhängigkeiten")
                            .font(UIConstants.bodyFont)
                    }
                    if let coffeeURL = URL(string: "https://buymeacoffee.com/daranto") {
                        Link(destination: coffeeURL) {
                            Label("Buy Me a Coffee", systemImage: "cup.and.saucer")
                                .font(UIConstants.bodyFont)
                        }
                        .tint(.accentColor)
                    }
                    if let url = URL(string: "https://github.com/daranto/Pr0gramm-Client-IOS-MacOS") {
                        Link(destination: url) {
                            Label("Projekt auf GitHub", systemImage: "link")
                                .font(UIConstants.bodyFont)
                        }
                        .tint(.accentColor)
                    }
                } header: {
                    Text("Info & Projekt")
                }
                .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
            }
            .navigationTitle("Einstellungen")
            .alert("Gesehene Posts zurücksetzen?", isPresented: $showingClearSeenItemsAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Zurücksetzen", role: .destructive) { Task { await settings.clearSeenItemsCache() } }
            } message: {
                Text("Dadurch werden alle Markierungen für gesehene Bilder und Videos entfernt. Die Posts erscheinen wieder als 'neu'.")
            }
            .alert("Gesamten App-Cache leeren?", isPresented: $showingClearAllCacheAlert) {
                Button("Abbrechen", role: .cancel) { }
                Button("Leeren", role: .destructive) { Task { await settings.clearAllAppCache() } }
            } message: {
                Text("Möchtest du wirklich alle zwischengespeicherten Daten (Feeds, Favoriten, Bilder, Gesehen-Markierungen etc.) löschen? Dies kann nicht rückgängig gemacht werden.")
            }
            .onAppear { Task { await settings.updateCacheSizes() } }
        }
    }
}


// MARK: - Preview

#Preview {
    struct SettingsPreviewWrapper: View {
        @StateObject private var settings: AppSettings
        @StateObject private var authService: AuthService

        init() {
            let appSettings = AppSettings()
            let authSvc = AuthService(appSettings: appSettings)
            
            authSvc.isLoggedIn = true
            let sampleCollections = [
                ApiCollection(id: 101, name: "Meine Favoriten", keyword: "favoriten", isPublic: 0, isDefault: 1, itemCount: 123),
                ApiCollection(id: 102, name: "Lustige Katzen", keyword: "katzen", isPublic: 0, isDefault: 0, itemCount: 45)
            ]
            authSvc.currentUser = UserInfo(id: 1, name: "PreviewUser", registered: 1, score: 1000, mark: 2, badges: [], collections: sampleCollections)
            #if DEBUG
            authSvc.setUserCollectionsForPreview(sampleCollections)
            #endif
            
            if let firstCollectionId = sampleCollections.first?.id {
                appSettings.selectedCollectionIdForFavorites = firstCollectionId
            }
            
            appSettings.enableStartupFilters = true


            _settings = StateObject(wrappedValue: appSettings)
            _authService = StateObject(wrappedValue: authSvc)
        }

        var body: some View {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(authService)
        }
    }
    return SettingsPreviewWrapper()
}

#Preview("Logged Out") {
    let appSettings = AppSettings()
    let authSvc = AuthService(appSettings: appSettings)
    authSvc.isLoggedIn = false

    return SettingsView()
        .environmentObject(appSettings)
        .environmentObject(authSvc)
}

struct LicenseAndDependenciesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                MIT License

                Copyright (c) 2025 Pr0gramm App Team

                Permission is hereby granted, free of charge, to any person obtaining a copy
                of this software and associated documentation files (the "Software"), to deal
                in the Software without restriction, including without limitation the rights
                to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
                copies of the Software, and to permit persons to whom the Software is
                furnished to do so, subject to the following conditions:

                The above copyright notice and this permission notice shall be included in
                all copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
                THE SOFTWARE.
                """)
                .font(.footnote)
                .textSelection(.enabled)
                Divider()
                Text("Verwendete Swift Packages")
                    .font(.title2).bold()
                VStack(alignment: .leading, spacing: 8) {
                    Link("Kingfisher", destination: URL(string: "https://github.com/onevcat/Kingfisher")!)
                        .font(UIConstants.bodyFont)
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Lizenzen")
         #if os(iOS)
         .navigationBarTitleDisplayMode(.inline)
         #endif
    }
}
// --- END OF COMPLETE FILE ---

