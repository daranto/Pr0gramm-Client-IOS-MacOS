// SettingsView.swift
import SwiftUI

struct SettingsView: View {
     @EnvironmentObject var settings: AppSettings // Könnte Einstellungen anzeigen/ändern

    var body: some View {
        NavigationStack {
             Form { // Form für konsistentes Aussehen
                 Section("Video") {
                     Toggle("Videos stumm starten", isOn: $settings.isVideoMuted)
                 }
                 // Hier könnten weitere App-Einstellungen hin
             }
            .navigationTitle("Einstellungen")
        }
    }
}
#Preview { SettingsView().environmentObject(AppSettings()) }
