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
                if authService.isLoggedIn {
                    Section("Spendenziel") {
                        DonationProgressView()
                    }
                    .headerProminence(UIConstants.isRunningOnMac ? .increased : .standard)
                }

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
            .safeAreaInset(edge: .bottom) {
                // Create invisible spacer that matches tab bar height
                Color.clear
                    .frame(height: 32 + 40 + (UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8))
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

struct DonationProgressView: View {
    @State private var amountUSD: Double? = nil
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())
    @State private var isDonationTextExpanded = false
    let goalUSD: Double = 100.0

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "DonationProgressView")

    private static var lastFetchDate: Date? = nil
    private static var cachedAmountUSD: Double? = nil
    private let minRefreshIntervalAuto: TimeInterval = 5 * 60
    private let minRefreshIntervalManual: TimeInterval = 10

    struct DonationTotalsResponse: Decodable {
        struct YearTotal: Decodable { let year: Int; let total_usd: Double }
        let currency: String
        let totals: [YearTotal]
        let current_year: Int?
        let current_year_total_usd: Double?
    }

    var percent: Double {
        guard let amount = amountUSD else { return 0 }
        return (amount / goalUSD) * 100.0
    }

    var displayPercent: Int {
        Int(round(percent))
    }

    var progressValue: Double {
        guard let amount = amountUSD else { return 0 }
        return min(max(amount / goalUSD, 0), 1)
    }
    
    private var lastUpdatedText: String? {
        guard let date = Self.lastFetchDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    var body: some View {
        let amount = amountUSD ?? 0
        let ratio = goalUSD > 0 ? amount / goalUSD : 0
        let progressValue = min(max(ratio, 0), 1)
        let displayPercent = Int(round(ratio * 100))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Jahr \(String(displayYear))")
                    .font(UIConstants.captionFont)
                    .foregroundColor(.secondary)
                Spacer()
                if let coffeeURL = URL(string: "https://buymeacoffee.com/daranto") {
                    Button(action: {
                        Self.logger.debug("Refresh button tapped. Forcing fetch.")
                        refreshIfNeeded(force: true)
                    }) {
                        Label("Buy Me a Coffee", systemImage: "cup.and.saucer")
                            .font(UIConstants.captionFont)
                    }
                    .buttonStyle(.borderless)
                    .tint(.accentColor)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                ProgressView(value: progressValue)
                    .tint(amount >= goalUSD ? .green : .accentColor)
                    .accessibilityLabel("Spendenfortschritt")
                    .accessibilityValue("\(displayPercent) Prozent")
                Button(action: {
                    Self.logger.debug("Refresh button tapped. Forcing fetch.")
                    refreshIfNeeded(force: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }

            HStack {
                Text("\(displayPercent)%")
                    .font(UIConstants.subheadlineFont)
                    .bold()
                Spacer()
                Text(String(format: "%.2f / %.0f USD", amount, goalUSD))
                    .font(UIConstants.subheadlineFont)
                    .foregroundColor(.secondary)
            }

            DisclosureGroup(isExpanded: $isDonationTextExpanded) {
                Text("Damit die App weiter angeboten werden kann, fallen jedes Jahr 100 USD fürs Apple Developer Program an. Ohne die Mitgliedschaft sind keine Updates mehr möglich – und die App verschwindet aus TestFlight. Mit deiner Spende deckst du diese Kosten und hältst die App am Leben.")
                    .font(UIConstants.captionFont)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .transition(.identity)
            } label: {
                Text("Danke für eure Unterstützung!")
                    .font(UIConstants.captionFont)
                    .foregroundColor(.secondary)
            }
        }
        .animation(nil, value: isDonationTextExpanded)
        .onAppear { refreshIfNeeded(force: false) }
    }

    private func refreshIfNeeded(force: Bool) {
        let now = Date()
        if force {
            let manualInterval = minRefreshIntervalManual
            if let lastDate = Self.lastFetchDate {
                let delta = now.timeIntervalSince(lastDate)
                Self.logger.debug("Manual refresh requested. Seconds since last fetch: \(delta, privacy: .public). Throttle: \(manualInterval, privacy: .public)")
                if delta < manualInterval {
                    if let cached = Self.cachedAmountUSD {
                        Self.logger.debug("Manual refresh throttled. Using cached amount: \(cached, privacy: .public)")
                        self.amountUSD = cached
                    } else {
                        Self.logger.debug("Manual refresh throttled but no cache available. Proceeding to fetch.")
                        fetchLatest()
                    }
                    return
                }
            } else {
                Self.logger.debug("Manual refresh requested with no last fetch date. Proceeding to fetch.")
            }
            Self.logger.debug("Manual refresh proceeding to fetch latest.")
            fetchLatest()
            return
        }
        let autoInterval = minRefreshIntervalAuto
        if let cached = Self.cachedAmountUSD, let lastDate = Self.lastFetchDate {
            let delta = now.timeIntervalSince(lastDate)
            Self.logger.debug("Auto refresh check. Seconds since last fetch: \(delta, privacy: .public). Interval: \(autoInterval, privacy: .public)")
            if delta < autoInterval {
                Self.logger.debug("Auto refresh within interval. Using cached amount: \(cached, privacy: .public)")
                self.amountUSD = cached
                return
            }
        }
        Self.logger.debug("Auto refresh proceeding to fetch latest.")
        fetchLatest()
    }

    private func fetchLatest() {
        isLoading = true
        error = nil
        Task {
            do {
                guard let url = URL(string: "https://bmac.xn--gnn-sna.eu/") else {
                    throw URLError(.badURL)
                }
                Self.logger.debug("Starting fetch from URL: \(url.absoluteString, privacy: .public)")

                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let tsQuery = URLQueryItem(name: "_ts", value: String(Int(Date().timeIntervalSince1970)))
                var existing = components?.queryItems ?? []
                existing.append(tsQuery)
                components?.queryItems = existing
                let finalURL = components?.url ?? url
                var request = URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue("no-cache", forHTTPHeaderField: "Pragma")
                Self.logger.debug("Final request URL: \(finalURL.absoluteString, privacy: .public)")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    Self.logger.debug("HTTP status: \(http.statusCode, privacy: .public)")
                    let cc = http.allHeaderFields["Cache-Control"] as? String ?? "<none>"
                    let age = http.allHeaderFields["Age"] as? String ?? "<none>"
                    Self.logger.debug("Response Cache-Control: \(cc, privacy: .public), Age: \(age, privacy: .public)")
                }
                let decoded = try JSONDecoder().decode(DonationTotalsResponse.self, from: data)

                Self.logger.debug("Decoded totals count: \(decoded.totals.count, privacy: .public), current_year: \(decoded.current_year ?? -1, privacy: .public), current_year_total_usd: \(decoded.current_year_total_usd ?? -1, privacy: .public)")
                let currentYear = Calendar.current.component(.year, from: Date())
                let yearAmount = decoded.totals.first(where: { $0.year == currentYear })?.total_usd ?? (decoded.current_year == currentYear ? (decoded.current_year_total_usd ?? 0) : 0)
                Self.logger.debug("Computed yearAmount for \(currentYear, privacy: .public): \(yearAmount, privacy: .public)")
                await MainActor.run {
                    self.amountUSD = yearAmount
                    Self.cachedAmountUSD = yearAmount
                    Self.lastFetchDate = Date()
                    self.isLoading = false
                    self.error = nil
                    self.displayYear = currentYear
                }
            } catch {
                Self.logger.error("Fetch failed: \(String(describing: error), privacy: .public)")
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
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


