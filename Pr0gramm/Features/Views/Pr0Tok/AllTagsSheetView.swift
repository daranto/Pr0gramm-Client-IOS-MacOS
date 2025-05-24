// Pr0gramm/Pr0gramm/Features/Views/Pr0Tok/AllTagsSheetView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

struct AllTagsSheetView: View {
    let item: Item
    @Binding var cachedDetails: [Int: ItemsInfoResponse]
    @Binding var infoLoadingStatus: [Int: InfoLoadingStatus]

    let onTagTapped: (String) -> Void
    let onUpvoteTag: (Int) -> Void
    let onDownvoteTag: (Int) -> Void
    let onRetryLoadDetails: () -> Void
    let onShowAddTagSheet: () -> Void


    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AllTagsSheetView")

    private var itemInfo: ItemsInfoResponse? {
        cachedDetails[item.id]
    }

    private var currentItemInfoStatus: InfoLoadingStatus {
        infoLoadingStatus[item.id] ?? .idle
    }

    private var sortedTags: [ItemTag] {
        itemInfo?.tags.sorted { $0.confidence > $1.confidence } ?? []
    }

    var body: some View {
        NavigationStack {
            VStack {
                switch currentItemInfoStatus {
                case .loading:
                    ProgressView("Lade Tags...")
                        .frame(maxHeight: .infinity)
                case .error(let msg):
                    VStack {
                        Text("Fehler beim Laden der Tags: \(msg)").foregroundColor(.red)
                        Button("Erneut versuchen") {
                            onRetryLoadDetails()
                        }
                    }
                    .frame(maxHeight: .infinity)
                case .loaded:
                    if sortedTags.isEmpty {
                        Text("Keine Tags für diesen Post vorhanden.")
                            .foregroundColor(.secondary)
                            .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                                ForEach(sortedTags) { tag in
                                    // Verwende die gleiche VotableTagView wie in DetailViewContent,
                                    // oder eine ähnliche Implementierung.
                                    // Hier eine angepasste Version für das Sheet.
                                    SheetVotableTagView(
                                        tag: tag,
                                        currentVote: authService.votedTagStates[tag.id] ?? 0,
                                        isVoting: authService.isVotingTag[tag.id] ?? false,
                                        onUpvote: { onUpvoteTag(tag.id) },
                                        onDownvote: { onDownvoteTag(tag.id) },
                                        onTapTag: { onTagTapped(tag.tag) }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                default: // .idle
                    Text("Tags werden geladen...")
                        .foregroundColor(.secondary)
                        .frame(maxHeight: .infinity)
                        .onAppear {
                            // Falls die Details noch nicht geladen wurden, hier anstoßen
                            if currentItemInfoStatus == .idle {
                                onRetryLoadDetails()
                            }
                        }
                }
            }
            .navigationTitle("Alle Tags (\(sortedTags.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if authService.isLoggedIn {
                        Button {
                            onShowAddTagSheet() // Ruft die Callback-Funktion auf
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

fileprivate struct SheetVotableTagView: View {
    let tag: ItemTag
    let currentVote: Int
    let isVoting: Bool
    let onUpvote: () -> Void
    let onDownvote: () -> Void
    let onTapTag: () -> Void

    @EnvironmentObject var authService: AuthService
    private let tagVoteButtonFont: Font = .callout // Etwas größer für bessere Tappability im Sheet

    var body: some View {
        HStack(spacing: 6) {
            if authService.isLoggedIn {
                Button(action: onDownvote) {
                    Image(systemName: currentVote == -1 ? "minus.circle.fill" : "minus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == -1 ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }

            Text(tag.tag) // Tags im Sheet nicht kürzen
                .font(.callout) // Etwas größer
                .padding(.horizontal, authService.isLoggedIn ? 4 : 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
                .onTapGesture(perform: onTapTag)

            if authService.isLoggedIn {
                Button(action: onUpvote) {
                    Image(systemName: currentVote == 1 ? "plus.circle.fill" : "plus.circle")
                        .font(tagVoteButtonFont)
                        .foregroundColor(currentVote == 1 ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isVoting)
            }
        }
        .padding(.horizontal, authService.isLoggedIn ? 8 : 0)
        .background(Color.gray.opacity(0.2))
        .foregroundColor(.primary)
        .clipShape(Capsule())
    }
}

// Preview für AllTagsSheetView
#Preview("AllTagsSheetView Preview") {
    // Erstelle Dummy-Daten für die Preview
    let sampleItem = Item(id: 1, promoted: nil, userId: 1, down: 0, up: 100, created: Int(Date().timeIntervalSince1970), image: "test.jpg", thumb: "thumb.jpg", fullsize: nil, preview: nil, width: 100, height: 100, audio: false, source: nil, flags: 1, user: "TestUser", mark: 1, repost: false, variants: nil, subtitles: nil)
    
    let sampleTags = [
        ItemTag(id: 1, confidence: 0.9, tag: "Lustig"),
        ItemTag(id: 2, confidence: 0.8, tag: "Katze"),
        ItemTag(id: 3, confidence: 0.7, tag: "Sehr langer Tag um Umbruch zu testen"),
        ItemTag(id: 4, confidence: 0.6, tag: "Programmieren"),
        ItemTag(id: 5, confidence: 0.5, tag: "SwiftUI"),
        ItemTag(id: 6, confidence: 0.4, tag: "Apple"),
        ItemTag(id: 7, confidence: 0.3, tag: "Mobile"),
        ItemTag(id: 8, confidence: 0.2, tag: "Entwicklung"),
    ]
    let sampleComments: [ItemComment] = []
    let sampleInfoResponse = ItemsInfoResponse(tags: sampleTags, comments: sampleComments)

    @State var previewCachedDetails: [Int: ItemsInfoResponse] = [sampleItem.id: sampleInfoResponse]
    @State var previewInfoLoadingStatus: [Int: InfoLoadingStatus] = [sampleItem.id: .loaded]
    
    let settings = AppSettings()
    let authService = AuthService(appSettings: settings)
    authService.isLoggedIn = true // Für Voting-Buttons etc.

    return AllTagsSheetView(
        item: sampleItem,
        cachedDetails: $previewCachedDetails,
        infoLoadingStatus: $previewInfoLoadingStatus,
        onTagTapped: { tag in print("Tag getippt: \(tag)") },
        onUpvoteTag: { id in print("Upvote Tag: \(id)") },
        onDownvoteTag: { id in print("Downvote Tag: \(id)") },
        onRetryLoadDetails: { print("Retry Load Details") },
        onShowAddTagSheet: { print("Show Add Tag Sheet triggered from AllTagsSheet") }
    )
    .environmentObject(authService)
    .environmentObject(settings)
}

// --- END OF COMPLETE FILE ---
