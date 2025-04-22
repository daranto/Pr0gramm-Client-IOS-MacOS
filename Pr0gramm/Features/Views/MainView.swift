// MainView.swift

import SwiftUI
#if !os(macOS)
import UIKit
#endif

// Enum zur Definition der Tabs (unverändert)
enum Tab: Int, CaseIterable, Identifiable {
    case feed = 0
    case search = 1
    case profile = 2
    case settings = 3

    var id: Int { self.rawValue }
}

struct MainView: View {
    @State private var selectedTab: Tab = .feed
    @EnvironmentObject var settings: AppSettings
    @State private var feedPopToRootTrigger = UUID()

    var body: some View {
        VStack(spacing: 0) {

            // --- Inhaltsbereich (unverändert) ---
            Group {
                switch selectedTab {
                case .feed:
                    FeedView(popToRootTrigger: feedPopToRootTrigger)
                case .search:
                    SearchView()
                case .profile:
                    ProfileView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // --- Benutzerdefinierte TabBar (unverändert) ---
            HStack {
                ForEach(Tab.allCases) { tab in
                    Button {
                        handleTap(on: tab)
                    } label: {
                        // TabBarButtonLabel wird hier verwendet (OHNE Spacer jetzt)
                        TabBarButtonLabel(
                            iconName: iconName(for: tab),
                            label: label(for: tab),
                            isSelected: selectedTab == tab
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            #if os(iOS)
            // Behalte das angepasste Padding, das ist wahrscheinlich okay
            .padding(.bottom, max(bottomSafeAreaInset, 4))
            #else
            .padding(.bottom, 8)
            #endif
            .background(.bar)

        } // Ende Haupt-VStack
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // --- Unveränderte Hilfsfunktionen ---
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
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape.fill"
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .feed: return settings.feedType.displayName
        case .search: return "Suche"
        case .profile: return "Profil"
        case .settings: return "Einstellungen"
        }
    }


    #if os(iOS)
    private var bottomSafeAreaInset: CGFloat {
        let keyWindow = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .map({$0 as? UIWindowScene})
            .compactMap({$0})
            .first?.windows
            .filter({$0.isKeyWindow}).first
        return keyWindow?.safeAreaInsets.bottom ?? 0
    }
    #endif
}

// --- Geändert: TabBarButtonLabel OHNE Spacer ---
struct TabBarButtonLabel: View {
    let iconName: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            // --- Spacer wurde hier entfernt ---

            // Icon und Text (wie vorher)
            Image(systemName: iconName)
                .font(.title3)
                .symbolVariant(isSelected ? .fill : .none)
            Text(label)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}


// MARK: - Preview (unverändert)
#Preview {
    MainView()
        .environmentObject(AppSettings())
}
