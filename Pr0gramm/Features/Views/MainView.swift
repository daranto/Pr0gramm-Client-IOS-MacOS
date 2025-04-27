import SwiftUI

/// Represents the main tabs of the application.
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, profile = 3, settings = 4
    var id: Int { self.rawValue }
}

/// The root view of the application, containing the main content area and the tab bar.
/// It observes `NavigationService` to switch between different content views (Feed, Favorites, etc.).
struct MainView: View {
    /// Service managing the currently selected tab and navigation requests.
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    /// State variable used to trigger popping the FeedView's navigation stack to root.
    @State private var feedPopToRootTrigger = UUID()

    /// The currently selected tab, derived from the `NavigationService`.
    private var selectedTab: Tab {
        navigationService.selectedTab
    }

    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 to have Divider touch content and bar
            // Main content area that changes based on the selected tab
            Group {
                switch selectedTab {
                case .feed: FeedView(popToRootTrigger: feedPopToRootTrigger)
                case .favorites: FavoritesView()
                case .search: SearchView() // SearchView reacts to pendingSearchTag from NavigationService
                case .profile: ProfileView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure content fills space

            Divider() // Visual separator above the tab bar

            // Custom tab bar implementation
            tabBarHStack
                .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) } // Use standard bar background material

        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // Prevent keyboard from overlapping tab bar
    }

    /// The horizontal stack representing the custom tab bar.
    private var tabBarHStack: some View {
        HStack(spacing: 0) { // Use spacing 0 for tightly packed buttons
            ForEach(Tab.allCases) { tab in
                 // Conditionally hide Favorites tab if user is not logged in
                 if tab == .favorites && !authService.isLoggedIn {
                     // Skip rendering the button
                 } else {
                     Button { handleTap(on: tab) } label: {
                         TabBarButtonLabel(
                             iconName: iconName(for: tab),
                             label: label(for: tab),
                             isSelected: selectedTab == tab // Highlight if selected
                         )
                     }
                     .buttonStyle(.plain) // Use plain style for custom appearance
                     .frame(minWidth: 40, maxWidth: .infinity) // Distribute space evenly
                 }
            }
        }
        .padding(.horizontal) // Add padding to the sides of the bar
        .padding(.top, 5) // Padding above icons/text
        .padding(.bottom, 4) // Padding below icons/text (adjust for safe area)
    }

    /// Handles taps on tab bar buttons.
    /// Updates the `NavigationService` or triggers pop-to-root for the feed tab.
    /// - Parameter tab: The tab that was tapped.
    private func handleTap(on tab: Tab) {
        // Special case: If Feed tab is tapped again, pop its navigation stack
        if tab == .feed && selectedTab == .feed {
            print("Feed tab tapped again. Triggering pop to root.")
            feedPopToRootTrigger = UUID() // Change UUID to trigger onChange in FeedView
        } else {
            // Otherwise, update the selected tab in the central navigation service
            navigationService.selectedTab = tab
            // Clear any pending search tag if the user manually navigates away from Search
            // or taps Search again without an active pending tag.
            if navigationService.pendingSearchTag != nil && tab != .search {
                 print("Clearing pending search tag due to manual tab navigation.")
                 navigationService.pendingSearchTag = nil
            }
        }
    }

    /// Returns the system icon name for a given tab.
    private func iconName(for tab: Tab) -> String {
        switch tab {
        case .feed: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }

    /// Returns the display label for a given tab.
    private func label(for tab: Tab) -> String {
        switch tab {
        case .feed: return settings.feedType.displayName // Dynamic label based on feed type
        case .favorites: return "Favoriten"
        case .search: return "Suche"
        case .profile: return "Profil"
        case .settings: return "Einstellungen"
        }
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
                 .font(.body)
                 .symbolVariant(isSelected ? .fill : .none) // Use filled variant when selected
             Text(label)
                 .font(.caption2)
                 .lineLimit(1)
        }
        .padding(.vertical, 3)
        // Use accent color for selected, secondary for others
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
