// Pr0gramm/Pr0gramm/Features/Views/Calendar/CalendarEventDetailView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct CalendarEventDetailView: View {
    let event: CalendarEvent

    @EnvironmentObject var navigationService: NavigationService
    @State private var fullEvent: CalendarEvent?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CalendarEventDetailView")

    private var displayEvent: CalendarEvent {
        fullEvent ?? event
    }

    var body: some View {
        List {
            if isLoading && fullEvent == nil {
                ProgressView("Lade Details...")
            } else if let error = errorMessage {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else {
                Section {
                    Text(displayEvent.description.htmlToAttributedString())
                        .font(.body)
                        .padding(.vertical, 4)
                }
                
                Section("Details") {
                    InfoRow(label: "Kategorie", value: displayEvent.categoryName)
                    InfoRow(label: "Veranstalter", value: displayEvent.userName)
                    InfoRow(label: "Beginn", value: formatTimestamp(displayEvent.startTimeTs))
                    InfoRow(label: "Ende", value: formatTimestamp(displayEvent.endTimeTs))
                    InfoRow(label: "Ort", value: displayEvent.location)
                }

                if let conditions = displayEvent.conditions, !conditions.isEmpty {
                    Section("Bedingungen") {
                        Text(conditions.htmlToAttributedString())
                            .font(.body)
                    }
                }

                if let rewards = displayEvent.rewardsDescription, !rewards.isEmpty {
                    Section("Belohnungen") {
                        Text(rewards.htmlToAttributedString())
                            .font(.body)
                    }
                }

                if let tag = displayEvent.imageTagRequired, !tag.isEmpty {
                    Section("Benötigter Tag") {
                        Button(action: {
                            Self.logger.info("Required tag '\(tag)' tapped. Requesting search.")
                            navigationService.requestSearch(tag: tag)
                        }) {
                            Text(tag)
                                .font(.body.monospaced())
                                .foregroundColor(.accentColor)
                                .contentShape(Rectangle()) // Macht nur den Text klickbar
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(displayEvent.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFullEventDetails()
        }
    }
    
    @ViewBuilder
    private func InfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.headline)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadFullEventDetails() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await apiService.fetchCalendarEvent(byId: event.id)
            if response.success {
                self.fullEvent = response.event
            } else {
                self.errorMessage = "Event-Details konnten nicht geladen werden."
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formatTimestamp(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}

// --- MODIFIED & NEW: Erweiterung für HTML-Parsing zu AttributedString ---
extension String {
    func htmlStripped() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
    
    func htmlToAttributedString() -> AttributedString {
        // Ersetze <p> durch Zeilenumbrüche für die Absatzlogik
        let stringWithLineBreaks = self.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression, range: nil)
                                       .replacingOccurrences(of: "<br>", with: "\n", options: .regularExpression, range: nil)
                                       .replacingOccurrences(of: "<br/>", with: "\n", options: .regularExpression, range: nil)
                                       .htmlStripped() // Entferne alle verbleibenden Tags
                                       .trimmingCharacters(in: .whitespacesAndNewlines)

        return AttributedString(stringWithLineBreaks)
    }
}
// --- END MODIFICATION ---

#Preview {
    let sampleEvent = CalendarEvent(
        id: 5,
        userId: 4574,
        title: "Haustier-OC-Woche",
        description: "<p>Hallo Fettsäcke, es ist soweit:</p><p>Die Haustier-OC-Woche steht an! Holt die Kameras raus, lasst eure Zottelwesen, Schnurrinatoren oder Keksvernichter posieren, jetzt zählt nur noch: OC von euren Haustieren!</p>",
        location: "pr0gramm",
        startTime: "2025-08-11 00:01:00",
        endTime: "2025-08-17 23:59:00",
        conditions: "<p>OC only: Nur echte Original Content-Uploads („OC“) von euren eigenen Haustieren sind erlaubt.</p><p>Keine Reposts, kein Stock! Wer schummelt, bekommt Minus und Husch.</p>",
        imageTagRequired: "Never Haustierwoche",
        rewardsDescription: "<p>Ein tolles brandneues Badge</p>",
        created: "2025-08-03 21:57:52",
        modified: "2025-08-11 01:55:36",
        categoryId: 1,
        startTimeTs: 1754863260,
        endTimeTs: 1755467940,
        userName: "froschler",
        userMark: 5,
        categoryName: "Offizielles Event auf pr0gramm",
        categoryColor: "#ee4d2e"
    )
    
    return NavigationStack {
        CalendarEventDetailView(event: sampleEvent)
    }
    .environmentObject(NavigationService())
}
// --- END OF COMPLETE FILE ---
