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
    @Environment(\.scenePhase) private var scenePhase
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
        // --- NEW: Trigger count update when app becomes active ---
        .onChange(of: scenePhase) { oldPhase, newPhase in
             if newPhase == .active && authService.isLoggedIn {
                 Task {
                     await authService.updateUnreadCount()
                 }
             }
        }
        // --- END NEW ---
    }

    /// The horizontal stack representing the custom tab bar.
    private var tabBarHStack: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                 if (tab == .favorites || tab == .inbox) && !authService.isLoggedIn { /* Skip */ }
                 else {
                     Button { handleTap(on: tab) } label: {
                         // --- MODIFIED: Pass tab and badge count ---
                         TabBarButtonLabel(
                             iconName: iconName(for: tab),
                             isSelected: selectedTab == tab,
                             tab: tab, // Pass the current tab
                             badgeCount: authService.unreadMessageCount // Pass the count
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


    private func handleTap(on tab: Tab) { // Unverändert
        if tab == .feed && selectedTab == .feed { print("Feed tab tapped again. Triggering pop to root."); feedPopToRootTrigger = UUID() }
        else { navigationService.selectedTab = tab; if navigationService.pendingSearchTag != nil && tab != .search { print("Clearing pending search tag due to manual tab navigation."); navigationService.pendingSearchTag = nil } }
    }

    private func iconName(for tab: Tab) -> String { // Unverändert
        switch tab {
        case .feed: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .inbox: return "envelope.fill"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }

    private func label(for tab: Tab) -> String { // Unverändert
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
// --- MODIFIED: Accept tab and badgeCount ---
struct TabBarButtonLabel: View {
    let iconName: String
    let isSelected: Bool
    let tab: Tab // The specific tab this button represents
    let badgeCount: Int // The unread count from AuthService

    var body: some View {
        Image(systemName: iconName)
            .font(UIConstants.titleFont)
            .symbolVariant(isSelected ? .fill : .none)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            // --- NEW: Badge Overlay ---
            .overlay(alignment: .topTrailing) {
                // Show badge only for Inbox tab and if count > 0
                if tab == .inbox && badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.bold()) // Small bold font
                        .foregroundColor(.white)
                        .padding(.horizontal, badgeCount < 10 ? 4 : 3) // Adjust padding for digit count
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 10, y: -5) // Adjust offset for placement
                        .transition(.scale.combined(with: .opacity)) // Add animation
                }
            }
            // --- END NEW ---
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: badgeCount) // Animate badge changes
    }
}
// --- END MODIFICATION ---

// MARK: - Preview - Unverändert

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()

    // Optional: Simulate logged in state and unread count for preview
     authService.isLoggedIn = true
     authService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
     authService.unreadMessageCount = 100 // Example count

    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
