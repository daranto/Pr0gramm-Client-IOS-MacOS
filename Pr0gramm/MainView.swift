// MainTabView.swift

import SwiftUI

struct MainTabView: View {
    // Zugriff auf die globalen Einstellungen
    @EnvironmentObject var settings: AppSettings
    // State für den aktuell ausgewählten Tab
    @State private var selectedTab: Int = 0 // Startet mit dem ersten Tab (Feed)

    var body: some View {
        TabView(selection: $selectedTab) {

            // --- Tab 1: Feed (Hauptseite) ---
            FeedView() // Unsere umbenannte ContentView
                .tabItem {
                    Label("Beliebt", systemImage: "square.grid.2x2.fill") // Beispiel-Icon & Text
                }
                .tag(0) // Eindeutiger Tag für diesen Tab

            // --- Tab 2: Suche ---
            SearchView() // Platzhalter-View
                .tabItem {
                    Label("Suche", systemImage: "magnifyingglass")
                }
                .tag(1)

            // --- Tab 3: Profil ---
            ProfileView() // Platzhalter-View
                .tabItem {
                    Label("Profil", systemImage: "person.crop.circle")
                }
                .tag(2)

            // --- Tab 4: Einstellungen ---
            SettingsView() // Platzhalter-View
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        // Wichtig: Übergib das EnvironmentObject an die erste Ebene der TabView,
        // damit alle Tabs darauf zugreifen können (wird automatisch weitergegeben).
        // Ist hier nicht *zwingend* nötig, da es schon im App-Struct passiert, aber schadet nicht.
        // .environmentObject(settings)
    }
}

#Preview {
    MainTabView()
        // Wichtig für Preview: Stelle ein EnvironmentObject bereit
        .environmentObject(AppSettings())
}
