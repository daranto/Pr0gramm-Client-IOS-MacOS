// Pr0gramm/Pr0gramm/Features/Views/Profile/FavoritesView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os
import Kingfisher

struct FavoritesView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var showNoFilterMessage = false

    @State private var navigationPath = NavigationPath()
    @State private var showingFilterSheet = false

    private let apiService = APIService()
    let columns: [GridItem] = [ GridItem(.adaptive(minimum: 100), spacing: 3) ]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FavoritesView")

    private var favoritesCacheKey: String? {
        guard let username = authService.currentUser?.name.lowercased() else { return nil }
        return "favorites_\(username)"
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if authService.isLoggedIn {
                    if showNoFilterMessage {
                        noFilterContentView
                    } else if isLoading && items.isEmpty { // Zeigt Ladeindikator nur, wenn Liste leer ist
                        ProgressView("Lade Favoriten...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if items.isEmpty && !isLoading && errorMessage == nil && !showNoFilterMessage {
                         Text("Du hast noch keine Favoriten markiert (oder sie passen nicht zum Filter).")
                             .foregroundColor(.secondary)
                             .multilineTextAlignment(.center)
                             .padding()
                             .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        scrollViewContent
                    }
                } else {
                    loggedOutContentView
                }
            }
            .toolbar {
                 ToolbarItem(placement: .navigationBarLeading) {
                     Text("Favoriten")
                         .font(.title3)
                         .fontWeight(.bold)
                 }
                 ToolbarItem(placement: .primaryAction) {
                      Button { showingFilterSheet = true } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                 }
            }
            .alert("Fehler", isPresented: .constant(errorMessage != nil && !isLoading)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
            .sheet(isPresented: $showingFilterSheet) {
                 FilterView().environmentObject(settings)
            }
            .navigationDestination(for: Item.self) { destinationItem in
                 if let index = items.firstIndex(where: { $0.id == destinationItem.id }) {
                     PagedDetailView(items: items, selectedIndex: index)
                 } else {
                     Text("Fehler: Item nicht in Favoriten gefunden.")
                 }
            }
            .task(id: authService.isLoggedIn) { await handleLoginOrFilterChange() }
            .onChange(of: settings.showSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFW) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFL) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showNSFP) { _, _ in Task { await handleLoginOrFilterChange() } }
            .onChange(of: settings.showPOL) { _, _ in Task { await handleLoginOrFilterChange() } }
        }
    }

    // Hilfsfunktion für Refresh-Logik
    private func handleLoginOrFilterChange() async {
         if authService.isLoggedIn {
              await refreshFavorites()
          } else {
              await MainActor.run {
                  items = []
                  errorMessage = nil
                  isLoading = false // Sicherstellen, dass isLoading false ist
                  canLoadMore = true
                  isLoadingMore = false
                  showNoFilterMessage = false
              }
              Self.logger.info("User logged out, cleared favorites list.")
          }
     }

    // Extrahierter ScrollView-Inhalt
    private var scrollViewContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        FeedItemThumbnail(item: item)
                    }
                    .buttonStyle(.plain)
                }
                if canLoadMore && !isLoading && !isLoadingMore && !items.isEmpty {
                     Color.clear.frame(height: 1)
                        .onAppear {
                            Self.logger.info("Favorites: End trigger appeared.")
                            Task { await loadMoreFavorites() }
                        }
                 }
                if isLoadingMore { ProgressView("Lade mehr...").padding() }
            }
            .padding(.horizontal, 5).padding(.bottom)
        }
        .refreshable { await refreshFavorites() } // Hier wird refreshFavorites aufgerufen
    }

    // View für "Kein Filter"-Meldung
    private var noFilterContentView: some View {
         VStack {
             Spacer()
             Image(systemName: "line.3.horizontal.decrease.circle")
                 .font(.largeTitle)
                 .foregroundColor(.secondary)
                 .padding(.bottom, 5)
             Text("Keine Inhalte ausgewählt")
                 .font(.headline)
             Text("Bitte passe deine Filter an, um Inhalte zu sehen.")
                 .font(.subheadline)
                 .foregroundColor(.secondary)
                 .multilineTextAlignment(.center)
                 .padding(.horizontal)
             Button("Filter anpassen") {
                 showingFilterSheet = true
             }
             .buttonStyle(.bordered)
             .padding(.top)
             Spacer()
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .refreshable { await refreshFavorites() } // Auch hier refreshable
     }

    // Logged Out Content
    private var loggedOutContentView: some View {
        VStack {
            Spacer()
            Text("Melde dich an, um deine Favoriten zu sehen.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    // MARK: - Data Loading Functions

    // refreshFavorites Funktion (Korrigiert für Pull-to-Refresh)
    func refreshFavorites() async {
        // guard !isLoading else { return } // Entfernt!

        Self.logger.info("Pull-to-Refresh triggered or refreshFavorites called.")

        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
            Self.logger.warning("Cannot refresh favorites: User not logged in or username unavailable.")
            await MainActor.run {
                self.errorMessage = "Bitte anmelden."
                self.items = []
                self.showNoFilterMessage = false
            }
            return
        }

        guard settings.hasActiveContentFilter else {
            Self.logger.warning("Refresh favorites blocked: No active content filter selected.")
            await MainActor.run {
                self.items = []
                self.showNoFilterMessage = true
                self.canLoadMore = false
                self.isLoadingMore = false
                self.errorMessage = nil
            }
            return
        }

        // Setze isLoading erst hier
        await MainActor.run {
            self.showNoFilterMessage = false
            self.isLoading = true
            self.errorMessage = nil
        }

        // Defer zum sicheren Zurücksetzen
        defer {
            Task { @MainActor in
                self.isLoading = false
                Self.logger.info("Finishing favorites refresh process (isLoading set to false via defer).")
            }
        }

        guard let cacheKey = favoritesCacheKey else {
             Self.logger.error("Cannot refresh favorites: Could not generate cache key.")
             await MainActor.run { self.errorMessage = "Interner Fehler (Cache Key)." }
             return // `defer` setzt isLoading zurück
        }

        Self.logger.info("Starting refresh data fetch for favorites (User: \(username), Flags: \(settings.apiFlags))...")
        canLoadMore = true; isLoadingMore = false
        var initialItemsFromCache: [Item]? = nil

        if items.isEmpty {
             if let cachedItems = await settings.loadItemsFromCache(forKey: cacheKey), !cachedItems.isEmpty {
                 initialItemsFromCache = cachedItems
                 Self.logger.info("Found \(cachedItems.count) favorite items in cache initially.")
             } else {
                  Self.logger.info("No usable data cache found for favorites.")
             }
         }

        Self.logger.info("Performing API fetch for favorites refresh with flags: \(settings.apiFlags)...")
        do {
            let fetchedItemsFromAPI = try await apiService.fetchFavorites(username: username, flags: settings.apiFlags)
            Self.logger.info("API fetch for favorites completed: \(fetchedItemsFromAPI.count) fresh items.")

            await MainActor.run {
                 self.items = fetchedItemsFromAPI
                 self.canLoadMore = !fetchedItemsFromAPI.isEmpty
                 Self.logger.info("FavoritesView updated with \(fetchedItemsFromAPI.count) items directly from API.")
                 if !navigationPath.isEmpty && initialItemsFromCache != nil {
                    navigationPath = NavigationPath()
                    Self.logger.info("Popped navigation due to refresh overwriting cache.")
                 }
             }
            await settings.saveItemsToCache(fetchedItemsFromAPI, forKey: cacheKey)
            await settings.updateCacheSizes()

        } catch let error as URLError where error.code == .userAuthenticationRequired {
             Self.logger.error("API fetch for favorites failed: Authentication required.")
             await MainActor.run {
                 self.items = []
                 self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."
                 self.canLoadMore = false
             }
             await settings.saveItemsToCache([], forKey: cacheKey)
             await authService.logout()
        } catch {
             Self.logger.error("API fetch for favorites failed: \(error.localizedDescription)")
             await MainActor.run {
                 if self.items.isEmpty {
                     self.errorMessage = "Fehler beim Laden der Favoriten: \(error.localizedDescription)"
                 } else {
                     Self.logger.warning("Showing potentially stale cached favorites data because API refresh failed.")
                 }
                 self.canLoadMore = false
             }
        }
        // `defer` setzt isLoading zurück
    }


    // loadMoreFavorites Funktion
    func loadMoreFavorites() async {
        guard settings.hasActiveContentFilter else {
            Self.logger.warning("Skipping loadMoreFavorites: No active content filter selected.")
            await MainActor.run { canLoadMore = false }
            return
        }

        guard authService.isLoggedIn, let username = authService.currentUser?.name else {
             Self.logger.warning("Cannot load more favorites: User not logged in.")
             return
        }

        // Wichtig: isLoadingMore UND isLoading prüfen
        guard !isLoadingMore && canLoadMore && !isLoading else {
             Self.logger.debug("Skipping loadMoreFavorites: isLoadingMore=\(isLoadingMore), canLoadMore=\(canLoadMore), isLoading=\(isLoading)")
             return
        }
        guard let lastItemId = items.last?.id else {
             Self.logger.warning("Skipping loadMoreFavorites: No last item found.")
             return
        }
         guard let cacheKey = favoritesCacheKey else {
             Self.logger.error("Cannot load more favorites: Could not generate cache key.")
             return
         }

        Self.logger.info("--- Starting loadMoreFavorites older than \(lastItemId) ---")
        await MainActor.run { isLoadingMore = true }

        // Defer zum sicheren Zurücksetzen
        defer {
             Task { @MainActor in
                 if self.isLoadingMore {
                     self.isLoadingMore = false
                     Self.logger.info("--- Finished loadMoreFavorites older than \(lastItemId) (isLoadingMore set to false via defer) ---")
                 }
            }
        }

        do {
            let newItems = try await apiService.fetchFavorites(
                 username: username,
                 flags: settings.apiFlags,
                 olderThanId: lastItemId
             )
            Self.logger.info("Loaded \(newItems.count) more favorite items from API (requesting older than \(lastItemId)).")

            var appendedItemCount = 0
            await MainActor.run {
                 guard self.isLoadingMore else { Self.logger.info("Load more cancelled before UI update."); return }
                 if newItems.isEmpty {
                     Self.logger.info("Reached end of favorites feed (API returned empty list for older than \(lastItemId)).")
                     canLoadMore = false
                 } else {
                     let currentIDs = Set(self.items.map { $0.id })
                     let uniqueNewItems = newItems.filter { !currentIDs.contains($0.id) }

                     if uniqueNewItems.isEmpty {
                         Self.logger.warning("All loaded favorite items (older than \(lastItemId)) were duplicates.")
                     } else {
                         self.items.append(contentsOf: uniqueNewItems)
                         appendedItemCount = uniqueNewItems.count
                         Self.logger.info("Appended \(uniqueNewItems.count) unique favorite items. Total items: \(self.items.count)")
                         self.canLoadMore = true
                     }
                 }
             }

            if appendedItemCount > 0 {
                 let itemsToSave = await MainActor.run { self.items }
                 await settings.saveItemsToCache(itemsToSave, forKey: cacheKey)
                 await settings.updateCacheSizes()
             }

        } catch let error as URLError where error.code == .userAuthenticationRequired {
             Self.logger.error("API fetch for more favorites failed: Authentication required.")
             await MainActor.run {
                 self.errorMessage = "Sitzung abgelaufen. Bitte erneut anmelden."
                 self.canLoadMore = false
                 Task { await authService.logout() } // Auch hier ausloggen
             }
        } catch {
             Self.logger.error("API fetch failed during loadMoreFavorites: \(error.localizedDescription)")
             await MainActor.run {
                 guard self.isLoadingMore else { return }
                 if items.isEmpty { errorMessage = "Fehler beim Nachladen: \(error.localizedDescription)" }
                 canLoadMore = false
             }
        }
         // `defer` setzt isLoadingMore zurück
    }
}

// MARK: - Preview
#Preview("Logged In") {
    let settings = AppSettings()
    let auth = AuthService()
    auth.isLoggedIn = true
    auth.currentUser = UserInfo(id: 123, name: "TestUser", registered: 1, score: 100, mark: 2)
    return FavoritesView()
        .environmentObject(settings)
        .environmentObject(auth)
}
#Preview("Logged Out") {
    let settings = AppSettings()
    let auth = AuthService()
    return FavoritesView()
        .environmentObject(settings)
        .environmentObject(auth)
}
// --- END OF COMPLETE FILE ---
