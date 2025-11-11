// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents the main tabs of the application.
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, inbox = 3, profile = 4, settings = 5
    var id: Int { self.rawValue }
}

// Extension to get safe area insets
extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }
    }
    
    var safeAreaInsets: UIEdgeInsets {
        keyWindow?.safeAreaInsets ?? .zero
    }
}

// MARK: - Tab Bar Padding Helper
extension View {
    /// Adds appropriate bottom padding to account for the floating tab bar
    func tabBarPadding() -> some View {
        // Calculate total tab bar height: vertical padding (32) + content height (40) + bottom margin
        let tabBarTotalHeight: CGFloat = 32 + 40 + (UIApplication.shared.safeAreaInsets.bottom > 0 ? 4 : 8)
        return self.padding(.bottom, tabBarTotalHeight + 16) // Extra 16pt for comfortable scrolling
    }
}

/// The root view of the application, containing the main content area and the modern Liquid Glass tab bar.
/// It observes `NavigationService` to switch between different content views (Feed, Favorites, etc.).
struct MainView: View {
    @ObservedObject var navigationService: NavigationService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    // AppOrientationManager wird nicht mehr direkt hier benötigt, aber dieAppDelegate-Logik greift global.

    @State private var feedPopToRootTrigger = UUID()
    @State private var selectedTab: Tab = .feed
    // --- MODIFIED: Bestimmen, ob Pr0Tok angezeigt werden soll ---
    private var shouldShowPr0Tok: Bool {
        // Pr0Tok anzeigen, wenn:
        // 1. Feature in den Settings aktiviert ist
        // 2. Das aktuelle Gerät ein iPhone ist
        return settings.enableUnlimitedStyleFeed && UIConstants.isCurrentDeviceiPhone
    }
    // --- END MODIFICATION ---

    var body: some View {
        TabView(selection: $selectedTab) {
            if shouldShowPr0Tok {
                UnlimitedStyleFeedView()
                    .forceRotation(orientation: .portrait)
                    .tabItem { Label("Feed", systemImage: "square.grid.2x2.fill") }
                    .tag(Tab.feed)
            } else {
                FeedView(popToRootTrigger: feedPopToRootTrigger)
                    .forceRotation(orientation: .all)
                    .tabItem { Label(settings.feedType.displayName, systemImage: "square.grid.2x2.fill") }
                    .tag(Tab.feed)
            }
            
            if authService.isLoggedIn {
                FavoritesView()
                    .forceRotation(orientation: .all)
                    .tabItem { Label("Favoriten", systemImage: "heart.fill") }
                    .tag(Tab.favorites)
                    .badge(0)
            }
            
            SearchView()
                .forceRotation(orientation: .all)
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            
            ProfileView()
                .forceRotation(orientation: .all)
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
                .badge(authService.isLoggedIn && authService.unreadInboxTotal > 0 ? authService.unreadInboxTotal : 0)
            
            SettingsView()
                .forceRotation(orientation: .all)
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .accentColor(settings.accentColorChoice.swiftUIColor)
        .onAppear {
            // Customize tab bar appearance for compact display of all tabs
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            
            // Font for tab items
            let itemAppearance = UITabBarItemAppearance()
            itemAppearance.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 10, weight: .medium)]
            itemAppearance.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
            
            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance
            
            // Force all tabs to be visible
            UITabBar.appearance().itemSpacing = 0
            UITabBar.appearance().itemPositioning = .fill
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
        }
        .onReceive(navigationService.$selectedTab) { newTab in
            if selectedTab != newTab {
                selectedTab = newTab
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if navigationService.selectedTab != newValue {
                navigationService.selectedTab = newValue
            }
            if navigationService.pendingSearchTag != nil && newValue != .search {
                navigationService.pendingSearchTag = nil
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

    return MainView(navigationService: navigationService)
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(appOrientationManager)
}
// --- END OF COMPLETE FILE ---
