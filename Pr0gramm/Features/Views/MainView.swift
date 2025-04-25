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
    @State private var selectedTab: Tab = .feed
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var feedPopToRootTrigger = UUID()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .feed: FeedView(popToRootTrigger: feedPopToRootTrigger)
                case .favorites: FavoritesView()
                case .search: SearchView()
                case .profile: ProfileView()
                case .settings: SettingsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            tabBarHStack.background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
        }
    }

    private var tabBarHStack: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                 if tab == .favorites && !authService.isLoggedIn { /* Skip */ }
                 else {
                     Button { handleTap(on: tab) } label: {
                         TabBarButtonLabel(iconName: iconName(for: tab), label: label(for: tab), isSelected: selectedTab == tab)
                     }.buttonStyle(.plain).frame(minWidth: 40, maxWidth: .infinity)
                 }
            }
        }.padding(.horizontal).padding(.top, 5).padding(.bottom, 4)
    }

    private func handleTap(on tab: Tab) {
        if tab == .feed && selectedTab == .feed { print("Feed tab tapped again. Triggering pop to root."); feedPopToRootTrigger = UUID() }
        else { selectedTab = tab }
    }
    private func iconName(for tab: Tab) -> String { switch tab { case .feed: "square.grid.2x2.fill"; case .favorites: "heart.fill"; case .search: "magnifyingglass"; case .profile: "person.crop.circle"; case .settings: "gearshape.fill" } }
    private func label(for tab: Tab) -> String { switch tab { case .feed: settings.feedType.displayName; case .favorites: "Favoriten"; case .search: "Suche"; case .profile: "Profil"; case .settings: "Einstellungen" } }
}

struct TabBarButtonLabel: View {
    let iconName: String, label: String, isSelected: Bool
    var body: some View { VStack(spacing: 2) { Image(systemName: iconName).font(.body).symbolVariant(isSelected ? .fill : .none); Text(label).font(.caption2).lineLimit(1) }.padding(.vertical, 3).foregroundStyle(isSelected ? Color.accentColor : .secondary) }
}

// --- Preview KORRIGIERT ---
#Preview {
    // Erstelle beide Services
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings) // Übergebe settings
    // Gib View zurück
    MainView()
        .environmentObject(settings)
        .environmentObject(authService)
}
// --- END OF COMPLETE FILE ---
