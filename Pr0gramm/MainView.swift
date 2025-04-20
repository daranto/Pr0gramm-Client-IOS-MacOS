// MainView.swift

import SwiftUI
// Importiert UIKit *nur*, wenn wir nicht für macOS kompilieren
#if !os(macOS)
import UIKit
#endif

// Enum zur Definition der Tabs
enum Tab: Int {
    case feed = 0
    case search = 1
    case profile = 2
    case settings = 3
}

struct MainView: View {
    // Behält den Zustand des aktuell ausgewählten Tabs
    @State private var selectedTab: Tab = .feed // Startet mit dem Feed-Tab

    // Greift auf die globalen Einstellungen zu (wird vom App-Struct übergeben)
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        // Der Hauptcontainer
        VStack(spacing: 0) { // Kein Abstand zwischen Inhalt und TabBar

            // --- Inhaltsbereich ---
            // Zeigt die passende View basierend auf dem ausgewählten Tab an
            ZStack {
                FeedView()
                    .opacity(selectedTab == .feed ? 1 : 0)
                SearchView()
                    .opacity(selectedTab == .search ? 1 : 0)
                ProfileView()
                    .opacity(selectedTab == .profile ? 1 : 0)
                SettingsView()
                    .opacity(selectedTab == .settings ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Nimmt den meisten Platz ein

            // --- Trennlinie (optional) ---
            Divider()

            // --- Benutzerdefinierte TabBar ---
            HStack {
                TabBarButton(
                    iconName: "square.grid.2x2.fill",
                    label: settings.feedType.displayName, // Dynamischer Label-Text
                    tab: .feed,
                    selectedTab: $selectedTab
                )
                TabBarButton(
                    iconName: "magnifyingglass",
                    label: "Suche",
                    tab: .search,
                    selectedTab: $selectedTab
                )
                TabBarButton(
                    iconName: "person.crop.circle",
                    label: "Profil",
                    tab: .profile,
                    selectedTab: $selectedTab
                )
                TabBarButton(
                    iconName: "gearshape.fill",
                    label: "Einstellungen",
                    tab: .settings,
                    selectedTab: $selectedTab
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            // Korrigiertes Padding unten für iOS Safe Area
            #if os(iOS)
            .padding(.bottom, bottomSafeAreaInset)
            #else
            .padding(.bottom, 8) // Fester Wert für macOS
            #endif
            .background(.bar) // Standard Bar-Hintergrundmaterial

        } // Ende Haupt-VStack
        // .environmentObject hier nicht unbedingt nötig, wenn im App-Struct gesetzt
        // .environmentObject(settings)
        .ignoresSafeArea(.keyboard, edges: .bottom) // Ignoriert Tastatur, erlaubt Bar bis unten
    }

    // --- Korrigierte Safe Area Berechnung (nur für iOS) ---
    #if os(iOS)
    private var bottomSafeAreaInset: CGFloat {
        // Versucht, das Key Window zu finden und dessen Safe Area zu verwenden
        let keyWindow = UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .map({$0 as? UIWindowScene})
            .compactMap({$0})
            .first?.windows
            .filter({$0.isKeyWindow}).first
        
        // Wenn kein Key Window gefunden wird oder keine Insets, nimm 0
        return keyWindow?.safeAreaInsets.bottom ?? 0
    }
    #endif // Ende iOS-spezifischer Code
}

// MARK: - TabBar Button Hilfs-View

struct TabBarButton: View {
    let iconName: String
    let label: String
    let tab: Tab
    @Binding var selectedTab: Tab

    var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.title3) // Etwas kleiner als .title2 vielleicht
                    .symbolVariant(isSelected ? .fill : .none) // Füllt das Icon bei Auswahl

                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
             // --- Korrigierte Farbe ---
            .foregroundStyle(isSelected ? Color.accentColor : .secondary) // Color.accentColor geht hier, oder .accent
            // Animation für Auswahl
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    MainView()
        .environmentObject(AppSettings())
}

// --- KEINE Dummy UIKit Strukturen mehr hier! ---
// Der #if os(macOS) Block mit den Dummy-Strukturen wird entfernt,
// da die Safe Area Berechnung jetzt korrekt in #if os(iOS) gekapselt ist.
