// Pr0gramm/Pr0gramm/Features/Views/Calendar/CalendarView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var authService: AuthService
    
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    
    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CalendarView")

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                if isLoading && events.isEmpty {
                    ProgressView("Lade Kalender-Events...")
                        .frame(maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if events.isEmpty {
                    ContentUnavailableView("Keine Events", systemImage: "calendar.badge.exclamationmark", description: Text("Aktuell sind keine Events aktiv oder für die Zukunft geplant."))
                } else {
                    eventList
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadEvents()
            }
            .refreshable {
                await loadEvents()
            }
            .navigationDestination(for: CalendarEvent.self) { event in
                CalendarEventDetailView(event: event)
            }
        }
    }
    
    @ViewBuilder
    private var eventList: some View {
        List {
            ForEach(events) { event in
                NavigationLink(value: event) {
                    eventRow(for: event)
                }
            }
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder
    private func eventRow(for event: CalendarEvent) -> some View {
        HStack {
            Rectangle()
                .fill(Color(hex: UInt32(event.categoryColor.dropFirst(), radix: 16) ?? 0xee4d2e))
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                Text(event.categoryName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                let start = Date(timeIntervalSince1970: TimeInterval(event.startTimeTs))
                let end = Date(timeIntervalSince1970: TimeInterval(event.endTimeTs))
                
                Text("\(start, formatter: itemFormatter) - \(end, formatter: itemFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadEvents() async {
        isLoading = true
        errorMessage = nil
        
        let now = Date()
        guard let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: now) else {
            errorMessage = "Konnte Zukunftsdatum nicht berechnen."
            isLoading = false
            return
        }

        let startTimestamp = Int(now.timeIntervalSince1970)
        let endTimestamp = Int(oneYearFromNow.timeIntervalSince1970)
        
        Self.logger.info("Loading events from now (\(startTimestamp)) to one year in the future (\(endTimestamp))")

        do {
            let response = try await apiService.fetchCalendarEvents(startTimestamp: startTimestamp, endTimestamp: endTimestamp)
            if response.success {
                self.events = response.events.sorted(by: { $0.startTimeTs < $1.startTimeTs })
                Self.logger.info("Successfully loaded \(self.events.count) upcoming/active events.")
            } else {
                self.errorMessage = "Fehler beim Laden der Events vom Server."
                Self.logger.warning("API returned success=false for calendar events.")
            }
        } catch {
            self.errorMessage = error.localizedDescription
            Self.logger.error("Failed to load calendar events: \(error.localizedDescription)")
        }
        
        isLoading = false
    }

    private let itemFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()
}

#Preview {
    struct PreviewWrapper: View {
        @StateObject var settings = AppSettings()
        @StateObject var authService: AuthService
        
        init() {
            let s = AppSettings()
            let a = AuthService(appSettings: s)
            a.isLoggedIn = true
            a.currentUser = UserInfo(id: 1, name: "Preview", registered: 1, score: 1, mark: 1, badges: [])
            _authService = StateObject(wrappedValue: a)
        }
        
        var body: some View {
            CalendarView()
                .environmentObject(settings)
                .environmentObject(authService)
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
