// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents the main tabs of the application.
// --- MODIFIED: Add Inbox Tab ---
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, inbox = 3, profile = 4, settings = 5 // Indices verschoben
    var id: Int { self.rawValue }
}
// --- END MODIFICATION ---

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
                // --- NEW: Inbox Case ---
                case .inbox: InboxView() // Die neue View
                // --- END NEW ---
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
                 // --- MODIFIED: Check for Inbox visibility ---
                 if (tab == .favorites || tab == .inbox) && !authService.isLoggedIn { /* Skip */ }
                 // --- END MODIFICATION ---
                 else {
                     Button { handleTap(on: tab) } label: {
                         TabBarButtonLabel(
                             iconName: iconName(for: tab),
                             isSelected: selectedTab == tab
                         )
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


    private func handleTap(on tab: Tab) { // Unverändert
        if tab == .feed && selectedTab == .feed { print("Feed tab tapped again. Triggering pop to root."); feedPopToRootTrigger = UUID() }
        else { navigationService.selectedTab = tab; if navigationService.pendingSearchTag != nil && tab != .search { print("Clearing pending search tag due to manual tab navigation."); navigationService.pendingSearchTag = nil } }
    }

    // --- MODIFIED: Add Icon for Inbox ---
    private func iconName(for tab: Tab) -> String {
        switch tab {
        case .feed: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .inbox: return "envelope.fill" // Neues Icon
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }
    // --- END MODIFICATION ---

    // --- MODIFIED: Add Label for Inbox ---
    private func label(for tab: Tab) -> String {
        switch tab {
        case .feed: return settings.feedType.displayName
        case .favorites: return "Favoriten"
        case .search: return "Suche"
        case .inbox: return "Nachrichten" // Neues Label
        case .profile: return "Profil"
        case .settings: return "Einstellungen"
        }
    }
    // --- END MODIFICATION ---
}

/// A reusable view for the content of a tab bar button (icon only). - Unverändert
struct TabBarButtonLabel: View {
    let iconName: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: iconName)
            .font(UIConstants.titleFont)
            .symbolVariant(isSelected ? .fill : .none)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}

// MARK: - Preview - Unverändert

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()

    // Optional: Simulate logged in state for preview if needed
    // authService.isLoggedIn = true
    // authService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])

    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
