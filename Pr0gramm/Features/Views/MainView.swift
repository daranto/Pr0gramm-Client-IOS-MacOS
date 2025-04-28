// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents the main tabs of the application.
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, profile = 3, settings = 4
    var id: Int { self.rawValue }
}

/// The root view of the application, containing the main content area and the tab bar.
/// It observes `NavigationService` to switch between different content views (Feed, Favorites, etc.).
struct MainView: View {
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var feedPopToRootTrigger = UUID()

    private var selectedTab: Tab { navigationService.selectedTab }

    var body: some View {
        VStack(spacing: 0) {
            Group { // Main Content Area
                switch selectedTab {
                case .feed: FeedView(popToRootTrigger: feedPopToRootTrigger)
                case .favorites: FavoritesView()
                case .search: SearchView()
                case .profile: ProfileView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider() // Visual separator above the tab bar

            tabBarHStack // Custom tab bar
                .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }

        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// The horizontal stack representing the custom tab bar.
    private var tabBarHStack: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                 if tab == .favorites && !authService.isLoggedIn { /* Skip */ }
                 else {
                     Button { handleTap(on: tab) } label: {
                         TabBarButtonLabel( // Use the updated label
                             iconName: iconName(for: tab),
                             isSelected: selectedTab == tab
                         )
                         // Add accessibility label for screen readers
                         .accessibilityLabel(label(for: tab))
                     }
                     .buttonStyle(.plain)
                     .frame(minWidth: 40, maxWidth: .infinity)
                 }
            }
        }
        .padding(.horizontal)
        .padding(.top, 5)
        .padding(.bottom, 4)
    }


    private func handleTap(on tab: Tab) { /* Unverändert */
        if tab == .feed && selectedTab == .feed { print("Feed tab tapped again. Triggering pop to root."); feedPopToRootTrigger = UUID() }
        else { navigationService.selectedTab = tab; if navigationService.pendingSearchTag != nil && tab != .search { print("Clearing pending search tag due to manual tab navigation."); navigationService.pendingSearchTag = nil } }
    }
    private func iconName(for tab: Tab) -> String { /* Unverändert */
        switch tab { case .feed: return "square.grid.2x2.fill"; case .favorites: return "heart.fill"; case .search: return "magnifyingglass"; case .profile: return "person.crop.circle"; case .settings: return "gearshape.fill" }
    }
    // Label function is kept for accessibility, but not displayed visually anymore
    private func label(for tab: Tab) -> String {
        switch tab { case .feed: return settings.feedType.displayName; case .favorites: return "Favoriten"; case .search: return "Suche"; case .profile: return "Profil"; case .settings: return "Einstellungen" }
    }
}

/// A reusable view for the content of a tab bar button (icon only).
struct TabBarButtonLabel: View {
    let iconName: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: iconName)
             // --- MODIFIED: Use .titleFont (Mac: .title, iOS: .title3) ---
            .font(UIConstants.titleFont) // Changed from .largeTitleFont
             // --- END MODIFICATION ---
            .symbolVariant(isSelected ? .fill : .none)
            .padding(.vertical, 6) // Adjusted padding since text is gone
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}

// MARK: - Preview

#Preview {
    // Setup necessary services for the preview
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()

    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
