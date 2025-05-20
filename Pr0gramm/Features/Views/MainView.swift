// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents the main tabs of the application.
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, inbox = 3, profile = 4, settings = 5
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
                case .inbox: InboxView()
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
                 if (tab == .favorites || tab == .inbox) && !authService.isLoggedIn { /* Skip */ }
                 else {
                     Button { handleTap(on: tab) } label: {
                         // --- MODIFIED: Pass badgeCount for inbox tab ---
                         TabBarButtonLabel(
                             iconName: iconName(for: tab),
                             isSelected: selectedTab == tab,
                             tab: tab,
                             badgeCount: tab == .inbox ? authService.unreadInboxTotal : 0 // Pass count for inbox
                         )
                         // --- END MODIFICATION ---
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


    private func handleTap(on tab: Tab) {
        if tab == .feed && selectedTab == .feed { print("Feed tab tapped again. Triggering pop to root."); feedPopToRootTrigger = UUID() }
        else { navigationService.selectedTab = tab; if navigationService.pendingSearchTag != nil && tab != .search { print("Clearing pending search tag due to manual tab navigation."); navigationService.pendingSearchTag = nil } }
    }

    private func iconName(for tab: Tab) -> String {
        switch tab {
        case .feed: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .inbox: return "envelope.fill"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .feed: return settings.feedType.displayName
        case .favorites: return "Favoriten"
        case .search: return "Suche"
        case .inbox: return "Nachrichten"
        case .profile: return "Profil"
        case .settings: return "Einstellungen"
        }
    }
}

/// A reusable view for the content of a tab bar button (icon only).
// --- MODIFIED: Add badgeCount parameter and display logic ---
struct TabBarButtonLabel: View {
    let iconName: String
    let isSelected: Bool
    let tab: Tab
    let badgeCount: Int // New parameter

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .font(UIConstants.titleFont)
                .symbolVariant(isSelected ? .fill : .none)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, badgeCount > 9 ? 4 : 0) // Less horizontal padding for single digit
                    .frame(minWidth: 16, idealHeight: 16) // Ensure minimum size for circle
                    .background(Circle().fill(Color.red))
                    .offset(x: 10, y: -4) // Adjust offset as needed
            }
        }
    }
}
// --- END MODIFICATION ---

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()

    authService.isLoggedIn = true
    authService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    // --- NEW: Simulate unread count for preview ---
    // authService.unreadInboxTotal = 3 // Set directly for preview, though this won't work as it's private(set)
    // To test this in preview, you'd need to make unreadInboxTotal public(set) or call a method.
    // For now, we assume it works if the logic in AuthService is correct.
    // If you want to see it in preview, temporarily change unreadInboxTotal to public set for testing.
    // Task { await authService.fetchUnreadCounts() } // This would be better if API could be mocked.
    // --- END NEW ---


    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
