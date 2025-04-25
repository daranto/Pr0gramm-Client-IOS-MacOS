// Pr0gramm/Pr0gramm/Features/Views/MainView.swift
// --- START OF MODIFIED FILE ---

// MainView.swift

import SwiftUI
#if !os(macOS)
import UIKit
#endif

// Enum zur Definition der Tabs (unverändert)
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0
    case favorites = 1
    case search = 2
    case profile = 3
    case settings = 4

    var id: Int { self.rawValue }
}

struct MainView: View {
    @State private var selectedTab: Tab = .feed
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    @State private var feedPopToRootTrigger = UUID()

    // Cache safe area inset value - wird nicht mehr benötigt
    // @State private var cachedBottomSafeArea: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {

            // --- Content Area ---
            Group {
                switch selectedTab {
                case .feed:
                    FeedView(popToRootTrigger: feedPopToRootTrigger)
                 case .favorites:
                     FavoritesView()
                case .search:
                    SearchView()
                case .profile:
                    ProfileView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Content fills available space

            // --- Divider ---
             Divider() // Trennlinie bleibt

            // --- Custom TabBar Area ---
             tabBarHStack
                // --- Entfernt: .padding(.bottom, cachedBottomSafeArea) ---
                // --- GEÄNDERT: Hintergrund erweitert, Inhalt bleibt im Safe Area ---
                .background {
                    // Erstelle ein Rechteck, das den Hintergrund darstellt
                    // und ignoriere *nur dafür* die Safe Area unten
                    Rectangle()
                        .fill(.bar) // Fülle mit dem Hintergrundmaterial
                        .ignoresSafeArea(edges: .bottom) // Lass das Rechteck nach unten ausdehnen
                }
                // ---------------------------------------------------------------------

        } // Ende Haupt-VStack
        // --- Entfernt: .ignoresSafeArea(.container, edges: .bottom) ---
        // Die VStack respektiert jetzt standardmäßig die Safe Area
        // .onAppear wird nicht mehr benötigt, um Inset zu cachen
    }

    // --- Extracted TabBar HStack ---
    private var tabBarHStack: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                 if tab == .favorites && !authService.isLoggedIn {
                     // Skip favorites tab if not logged in
                 } else {
                     Button {
                         handleTap(on: tab)
                     } label: {
                         TabBarButtonLabel(
                             iconName: iconName(for: tab),
                             label: label(for: tab),
                             isSelected: selectedTab == tab
                         )
                     }
                     .buttonStyle(.plain)
                     .frame(minWidth: 40, maxWidth: .infinity) // Keep frame for distribution
                 }
            }
        }
        .padding(.horizontal) // Horizontal spacing between items
        // --- Angepasst: Etwas Padding oben/unten für die Button-Inhalte ---
        .padding(.top, 5)
        .padding(.bottom, 4) // Standard-Padding unten (innerhalb Safe Area)
    }


    // --- Hilfsfunktionen (unverändert) ---
    private func handleTap(on tab: Tab) {
        if tab == .feed && selectedTab == .feed {
            print("Feed tab tapped again. Triggering pop to root.")
            feedPopToRootTrigger = UUID()
        } else {
            selectedTab = tab
        }
    }

    private func iconName(for tab: Tab) -> String {
        switch tab {
        case .feed: return "square.grid.2x2.fill"
        case .favorites: return "heart.fill"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .feed: return settings.feedType.displayName
        case .favorites: return "Favoriten"
        case .search: return "Suche"
        case .profile: return "Profil"
        case .settings: return "Einstellungen"
        }
    }

    // Safe Area Inset Logik wird nicht mehr direkt benötigt
    /*
    #if os(iOS)
    private var bottomSafeAreaInset: CGFloat { ... }
    #else
    private var bottomSafeAreaInset: CGFloat { 0 }
    #endif
    */
}

// --- TabBarButtonLabel (unverändert zur letzten Version) ---
struct TabBarButtonLabel: View {
    let iconName: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.body)
                .symbolVariant(isSelected ? .fill : .none)
            Text(label)
                .font(.caption2) // Smaller font for the label
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}
// -------------------------------------


// MARK: - Preview (unverändert)
#Preview {
    MainView()
        .environmentObject(AppSettings())
        .environmentObject(AuthService())
}
// --- END OF MODIFIED FILE ---
