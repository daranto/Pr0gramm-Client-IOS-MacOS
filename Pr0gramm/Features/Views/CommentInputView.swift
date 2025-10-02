// Pr0gramm/Pr0gramm/Features/Views/CommentInputView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// A view presented as a sheet for composing and submitting comments.
struct CommentInputView: View {
    let itemId: Int
    let parentId: Int // 0 for top-level comment
    let onSubmit: (String) async throws -> Void // Closure to handle submission

    @Environment(\.dismiss) var dismiss
    @State private var commentText: String = ""
    @State private var isSubmitting = false
    @State private var submissionError: String? = nil

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CommentInputView")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // TextEditor for input
                TextEditor(text: $commentText)
                    .frame(minHeight: 150, maxHeight: .infinity)
                    .border(Color.gray.opacity(0.3), width: 1) // Optional border
                    .padding()
                    .accessibilityLabel("Kommentar eingeben")

                // Error message display
                if let error = submissionError {
                    Text("Fehler: \(error)")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                }

                // Bottom bar with buttons
                HStack {
                    Button("Abbrechen", role: .cancel) {
                        dismiss()
                    }
                    .disabled(isSubmitting)

                    Spacer()

                    Button {
                        Task { await submitComment() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white).padding(.horizontal)
                        } else {
                            Text("Senden")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.thinMaterial) // Subtle background for the bar
            }
            .navigationTitle(parentId == 0 ? "Kommentar schreiben" : "Antworten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled(isSubmitting) // Prevent dismissal while submitting
            .onAppear {
                 Self.logger.debug("CommentInputView appeared for itemId: \(itemId), parentId: \(parentId)")
            }
        }
        .tint(.accentColor)
    }

    /// Handles the submission process.
    private func submitComment() async {
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        submissionError = nil
        Self.logger.info("Submitting comment for itemId: \(itemId), parentId: \(parentId)")

        do {
            try await onSubmit(trimmedText)
            Self.logger.info("Comment submission successful via callback.")
            dismiss() // Close the sheet on success
        } catch {
            Self.logger.error("Comment submission failed: \(error.localizedDescription)")
            // Map common API errors to user-friendly messages
            if let nsError = error as NSError?, nsError.domain == "APIService.postComment" {
                 submissionError = mapApiError(nsError.localizedDescription)
            } else {
                 submissionError = "Ein unbekannter Fehler ist aufgetreten."
            }
            isSubmitting = false
        }
    }

    /// Maps known API error strings to more user-friendly messages.
    private func mapApiError(_ apiError: String) -> String {
        switch apiError {
        case "commentTooSoon": return "Du kommentierst zu schnell."
        case "commentEmpty": return "Kommentar darf nicht leer sein."
        case "commentForbidden", "userIsBanned": return "Aktion nicht erlaubt." // General forbidden
        case "parentNotFound": return "Der Kommentar, auf den du antworten wolltest, existiert nicht mehr."
        case "maxLevels": return "Maximale Antworttiefe erreicht."
        case "commentNotFound": return "Kommentar nicht gefunden." // Should not happen if replying
        default: return apiError // Return original error if unknown
        }
    }
}

// MARK: - Preview
#Preview {
    // Dummy action for preview
    func dummySubmit(text: String) async throws {
        print("Preview Submit: \(text)")
        try await Task.sleep(for: .seconds(1))
        // Simulate an error for testing
        // throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "commentTooSoon"])
    }

    // Present the view in a way that simulates a sheet
    return VStack {
        Text("Parent View Content")
    }
    .sheet(isPresented: .constant(true)) {
        CommentInputView(itemId: 123, parentId: 456, onSubmit: dummySubmit)
    }
}
// --- END OF COMPLETE FILE ---

