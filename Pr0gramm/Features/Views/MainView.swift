// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents the main tabs of the application.
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, inbox = 3, calendar = 4, profile = 5, settings = 6
    var id: Int { self.rawValue }
}

/// The root view of the application, containing the main content area and the tab bar.
/// It observes `NavigationService` to switch between different content views (Feed, Favorites, etc.).
struct MainView: View {
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    // AppOrientationManager wird nicht mehr direkt hier benötigt, aber dieAppDelegate-Logik greift global.

    @State private var feedPopToRootTrigger = UUID()

    private var selectedTab: Tab { navigationService.selectedTab }

    // --- MODIFIED: Bestimmen, ob Pr0Tok angezeigt werden soll ---
    private var shouldShowPr0Tok: Bool {
        // Pr0Tok anzeigen, wenn:
        // 1. Feature in den Settings aktiviert ist
        // 2. Das aktuelle Gerät ein iPhone ist
        return settings.enableUnlimitedStyleFeed && UIConstants.isCurrentDeviceiPhone
    }
    // --- END MODIFICATION ---

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Keep SearchView alive in the hierarchy so its state persists across tab switches
                SearchView()
                    .forceRotation(orientation: .all)
                    .opacity(selectedTab == .search ? 1 : 0)
                    .allowsHitTesting(selectedTab == .search)

                // Keep FavoritesView alive in the hierarchy so its state persists across tab switches
                FavoritesView()
                    .forceRotation(orientation: .all)
                    .opacity(selectedTab == .favorites ? 1 : 0)
                    .allowsHitTesting(selectedTab == .favorites)

                // Other tabs are instantiated on demand and hidden when Search or Favorites are active
                Group {
                    switch selectedTab {
                    case .feed:
                        if shouldShowPr0Tok {
                            UnlimitedStyleFeedView()
                                .forceRotation(orientation: .portrait)
                        } else {
                            FeedView(popToRootTrigger: feedPopToRootTrigger)
                                .forceRotation(orientation: .all)
                        }
                    case .inbox:
                        InboxView()
                            .forceRotation(orientation: .all)
                    case .profile:
                        ProfileView()
                            .forceRotation(orientation: .all)
                    case .settings:
                        SettingsView()
                            .forceRotation(orientation: .all)
                    case .calendar:
                        CalendarView()
                            .forceRotation(orientation: .all)
                    case .search:
                        // When Search is active, render an empty view here; real SearchView is above.
                        Color.clear
                    case .favorites:
                        // When Favorites is active, render an empty view here; real FavoritesView is above.
                        Color.clear
                    }
                }
                .opacity(selectedTab == .search || selectedTab == .favorites ? 0 : 1)
                .allowsHitTesting(selectedTab != .search && selectedTab != .favorites)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            tabBarHStack
                .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }

        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var tabBarHStack: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases.sorted(by: { $0.rawValue < $1.rawValue })) { tab in
                 if (tab == .favorites || tab == .inbox) && !authService.isLoggedIn { /* Skip */ }
                 else {
                     Button { handleTap(on: tab) } label: {
                         TabBarButtonLabel(
                             iconName: iconName(for: tab),
                             isSelected: selectedTab == tab,
                             tab: tab,
                             badgeCount: tab == .inbox ? authService.unreadInboxTotal : 0
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


    private func handleTap(on tab: Tab) {
        if tab == .feed && selectedTab == .feed && !shouldShowPr0Tok {
            print("Feed tab tapped again (Grid View or iPad/Mac). Triggering pop to root.");
            feedPopToRootTrigger = UUID()
        } else {
            navigationService.selectedTab = tab;
            if navigationService.pendingSearchTag != nil && tab != .search {
                print("Clearing pending search tag due to manual tab navigation.");
                navigationService.pendingSearchTag = nil
            }
        }
    }

    private func iconName(for tab: Tab) -> String {
        switch tab {
        case .feed: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .inbox: return "envelope.fill"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        case .calendar: return "calendar"
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
        case .calendar: return "Kalender"
        }
    }
}


struct TabBarButtonLabel: View {
    let iconName: String
    let isSelected: Bool
    let tab: Tab
    let badgeCount: Int

    private let badgeMinWidth: CGFloat = 18
    private let badgeHeight: CGFloat = 18
    private let badgeHorizontalPadding: CGFloat = 5


    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .font(UIConstants.titleFont)
                .symbolVariant(isSelected ? .fill : .none)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            if badgeCount > 0 {
                Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, badgeHorizontalPadding)
                    .frame(minWidth: badgeMinWidth, idealHeight: badgeHeight)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: 12, y: -5)
            }
        }
    }
}

#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()
    let appOrientationManager = AppOrientationManager()

    authService.isLoggedIn = true
    authService.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
    
    // settings.enableUnlimitedStyleFeed = true


    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
        .environmentObject(appOrientationManager)
}
// --- END OF COMPLETE FILE ---

