// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
#if !os(macOS)
import UIKit
#endif

enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0, favorites = 1, search = 2, profile = 3, settings = 4
    var id: Int { self.rawValue }
}

struct MainView: View {
    // Observe NavigationService for tab changes
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var feedPopToRootTrigger = UUID()

    // Selected tab is now derived from NavigationService
    private var selectedTab: Tab {
        navigationService.selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                // Content view depends on the selectedTab from NavigationService
                switch selectedTab {
                case .feed: FeedView(popToRootTrigger: feedPopToRootTrigger)
                case .favorites: FavoritesView()
                case .search: SearchView() // SearchView will react to pendingSearchTag
                case .profile: ProfileView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            tabBarHStack
                .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }

        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // Keep ignoring keyboard
    }

    private var tabBarHStack: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                 if tab == .favorites && !authService.isLoggedIn { /* Skip */ }
                 else {
                     Button { handleTap(on: tab) } label: {
                         TabBarButtonLabel(iconName: iconName(for: tab), label: label(for: tab), isSelected: selectedTab == tab)
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

    // Tapping a tab updates the NavigationService
    private func handleTap(on tab: Tab) {
        if tab == .feed && selectedTab == .feed {
            print("Feed tab tapped again. Triggering pop to root.")
            feedPopToRootTrigger = UUID()
        } else {
            // Update the central navigation service
            navigationService.selectedTab = tab
            // Clear any pending search tag if user manually navigates *away* from search
            // or taps search again without a pending tag.
            if navigationService.pendingSearchTag != nil && tab != .search {
                 print("Clearing pending search tag due to manual tab navigation.")
                 navigationService.pendingSearchTag = nil
            }
        }
    }

    private func iconName(for tab: Tab) -> String {
        switch tab {
            case .feed: "square.grid.2x2.fill"; case .favorites: "heart.fill"; case .search: "magnifyingglass"; case .profile: "person.crop.circle"; case .settings: "gearshape.fill"
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
            case .feed: settings.feedType.displayName; case .favorites: "Favoriten"; case .search: "Suche"; case .profile: "Profil"; case .settings: "Einstellungen"
        }
    }
}

// TabBarButtonLabel (unverändert)
struct TabBarButtonLabel: View {
    let iconName: String, label: String, isSelected: Bool
    var body: some View {
        VStack(spacing: 2) {
             Image(systemName: iconName).font(.body).symbolVariant(isSelected ? .fill : .none)
             Text(label).font(.caption2).lineLimit(1)
        }.padding(.vertical, 3).foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}

// Preview (aktualisiert)
#Preview {
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    let navigationService = NavigationService()
    return MainView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(navigationService)
}
// --- END OF COMPLETE FILE ---
