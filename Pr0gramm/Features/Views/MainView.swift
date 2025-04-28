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
                             label: label(for: tab),
                             isSelected: selectedTab == tab
                         )
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
    private func label(for tab: Tab) -> String { /* Unverändert */
        switch tab { case .feed: return settings.feedType.displayName; case .favorites: return "Favoriten"; case .search: return "Suche"; case .profile: return "Profil"; case .settings: return "Einstellungen" }
    }
}

/// A reusable view for the content of a tab bar button (icon and label).
struct TabBarButtonLabel: View {
    let iconName: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
             Image(systemName: iconName)
                 // --- MODIFIED: Use even larger adaptive font size for icon ---
                 .font(UIConstants.headlineFont) // Mac: title2, iOS: headline
                 // --- END MODIFICATION ---
                 .symbolVariant(isSelected ? .fill : .none)
             Text(label)
                 // --- MODIFIED: Use larger adaptive font size for label ---
                 .font(UIConstants.subheadlineFont) // Mac: headline, iOS: subheadline
                 // --- END MODIFICATION ---
                 .lineLimit(1)
        }
        .padding(.vertical, 3)
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
