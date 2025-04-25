// Pr0gramm/Pr0gramm/Features/Views/Settings/FilterView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

struct FilterView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Feed-Typ (unverändert)
                Section {
                    Picker("Feed Typ", selection: $settings.feedType) {
                        ForEach(FeedType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Anzeige")
                }

                // Section 2: Content Flags (Angepasst)
                Section {
                    Toggle("SFW (Safe for Work)", isOn: $settings.showSFW)
                    Toggle("NSFW (Not Safe for Work)", isOn: $settings.showNSFW)
                    Toggle("NSFL (Not Safe for Life)", isOn: $settings.showNSFL)
                    // --- UM BENANNT ---
                    Toggle("NSFP (Not Safe for Public)", isOn: $settings.showNSFP) // Bindet an showNSFP (Flag 8)
                    // --- NEU ---
                    Toggle("POL (Politik)", isOn: $settings.showPOL) // Bindet an showPOL (Flag 16)
                    // ---------------
                } header: {
                    Text("Inhaltsfilter")
                } footer: {
                     Text("Achtung: Die Anzeige von NSFW/NSFL/NSFP Inhalten unterliegt den App Store Richtlinien.") // Text angepasst
                }
            }
            .navigationTitle("Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    FilterView()
        .environmentObject(AppSettings())
}
// --- END OF COMPLETE FILE ---
