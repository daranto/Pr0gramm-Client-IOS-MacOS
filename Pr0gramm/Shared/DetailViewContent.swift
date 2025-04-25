// Pr0gramm/Pr0gramm/Shared/DetailViewContent.swift
// --- START OF COMPLETE FILE ---

// DetailViewContent.swift

import SwiftUI
import AVKit
import Combine
import os

// DetailImageView (unverändert)
struct DetailImageView: View {
    let item: Item
    let logger: Logger
    let cleanupAction: () -> Void
    var body: some View {
        AsyncImage(url: item.imageUrl) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure(let error): let _ = logger.error("Failed to load image for item \(item.id): \(error.localizedDescription)"); Rectangle().fill(.secondary.opacity(0.2)).overlay(Image(systemName: "exclamationmark.triangle"))
            default: Rectangle().fill(.secondary.opacity(0.1)).overlay(ProgressView())
            }
        }.onAppear { logger.trace("Displaying image for item \(item.id).") }
    }
}

// InfoLoadingStatus (unverändert)
enum InfoLoadingStatus: Equatable { case idle; case loading; case loaded; case error(String) }


struct DetailViewContent: View {
    let item: Item
    @ObservedObject var keyboardActionHandler: KeyboardActionHandler
    let player: AVPlayer?
    let onWillBeginFullScreen: () -> Void
    let onWillEndFullScreen: () -> Void
    let tags: [ItemTag]
    let comments: [ItemComment]
    let infoLoadingStatus: InfoLoadingStatus
    @Binding var previewLinkTarget: PreviewLinkTarget? // For comment link previews

    // --- NEU: Favoriten-Status und Aktion ---
    let isFavorited: Bool
    let toggleFavoriteAction: () async -> Void
    // --- ENDE NEU ---

    // Inject Services
    @EnvironmentObject var navigationService: NavigationService
    @EnvironmentObject var authService: AuthService // Für Login-Check

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DetailViewContent")
    // --- NEU: State für Favoriten-Button-Deaktivierung ---
    @State private var isProcessingFavorite = false

    // MARK: - Computed View Properties

    @ViewBuilder private var mediaContentInternal: some View { /* ... unverändert ... */
        Group {
            if item.isVideo {
                if let player = player {
                    CustomVideoPlayerRepresentable(player: player, handler: keyboardActionHandler, onWillBeginFullScreen: onWillBeginFullScreen, onWillEndFullScreen: onWillEndFullScreen).id(item.id)
                } else {
                     Rectangle().fill(.black).overlay(ProgressView().tint(.white))
                         .aspectRatio(guessAspectRatio(), contentMode: .fit)
                }
            } else {
                DetailImageView(item: item, logger: Self.logger, cleanupAction: { })
            }
        }
    }
    @ViewBuilder private var voteCounterView: some View { /* ... unverändert ... */
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) { Image(systemName: "arrow.up.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .green).imageScale(.medium); Text("\(item.up)").font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: true, vertical: false) }
            HStack(spacing: 5) { Image(systemName: "arrow.down.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .red).imageScale(.medium); Text("\(item.down)").font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: true, vertical: false) }
        }
    }

    // --- NEU: Favoriten Button ---
    @ViewBuilder private var favoriteButton: some View {
        Button {
            Task {
                isProcessingFavorite = true // Deaktivieren
                await toggleFavoriteAction()
                // Kurze Verzögerung, um Flackern bei schnellen Fehlern zu vermeiden
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                isProcessingFavorite = false // Wieder aktivieren
            }
        } label: {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .imageScale(.large) // Etwas größer machen
                .foregroundColor(isFavorited ? .pink : .secondary)
                .frame(width: 44, height: 44) // Größere Tappable Area
                .contentShape(Rectangle()) // Tappable Area definieren
        }
        .buttonStyle(.plain)
        .disabled(isProcessingFavorite || !authService.isLoggedIn) // Deaktivieren während Verarbeitung oder wenn nicht eingeloggt
    }
    // --- ENDE NEU ---


    @ViewBuilder
    private var infoAndTagsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
             HStack(alignment: .top, spacing: 15) {
                 // --- HStack für Votes UND Favoriten ---
                 HStack(alignment: .center, spacing: 15) { // Zentriert und mit Abstand
                     voteCounterView
                     if authService.isLoggedIn { // Zeige Button nur wenn eingeloggt
                         favoriteButton
                     }
                 }
                 // ---------------------------------------
                 Group { // Tags bleiben wie sie sind
                     if infoLoadingStatus == .loaded {
                         if !tags.isEmpty {
                             FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                 ForEach(tags) { tag in
                                     Button {
                                         navigationService.requestSearch(tag: tag.tag)
                                     } label: {
                                         Text(tag.tag)
                                             .font(.caption)
                                             .padding(.horizontal, 8)
                                             .padding(.vertical, 4)
                                             .background(Color.gray.opacity(0.2))
                                             .foregroundColor(.primary)
                                             .clipShape(Capsule())
                                             .lineLimit(1)
                                             .contentShape(Capsule())
                                     }
                                     .buttonStyle(.plain)
                                 }
                             }
                         } else {
                              Text("Keine Tags vorhanden").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                         }
                    } else if infoLoadingStatus == .loading {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    } else if case .error = infoLoadingStatus {
                        Text("Fehler beim Laden der Tags").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    }
                 }
                 .layoutPriority(1) // Ensure tags take available space
             }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var commentsContent: some View { // Unverändert
        CommentsSection(
            comments: comments,
            status: infoLoadingStatus,
            previewLinkTarget: $previewLinkTarget
        )
    }

    // Body (unverändert)
     var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 0) {
                    GeometryReader { geometry in mediaContentInternal.scaledToFit().frame(width: geometry.size.width, height: geometry.size.height).clipped() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    ScrollView { VStack(alignment: .leading, spacing: 15) { infoAndTagsContent.padding([.horizontal, .top]); commentsContent.padding([.horizontal, .bottom]) } }
                    .frame(minWidth: 300, idealWidth: 450, maxWidth: 600).background(Color(.secondarySystemBackground))
                }
            } else {
                ScrollView { VStack(spacing: 0) { mediaContentInternal.scaledToFit(); infoAndTagsContent.padding(.horizontal).padding(.vertical, 10); commentsContent.padding(.horizontal).padding(.bottom, 10) } }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
         .onAppear { Self.logger.debug("DetailViewContent for item \(item.id) appearing.") }
         .onDisappear { Self.logger.debug("DetailViewContent for item \(item.id) disappearing.") }
    }

    private func guessAspectRatio() -> CGFloat? { /* ... unverändert ... */
        if item.width > 0 && item.height > 0 { return CGFloat(item.width) / CGFloat(item.height) }
        return 16.0 / 9.0
    }
}

// Previews (angepasst, um Favoriten zu demonstrieren)
#Preview("Compact Favorited") {
     // ... setup sample data ...
     let sampleVideoItem = Item(id: 2, promoted: 1002, userId: 1, down: 2, up: 20, created: Int(Date().timeIntervalSince1970) - 100, image: "vid1.mp4", thumb: "t2.jpg", fullsize: nil, preview: nil, width: 1920, height: 1080, audio: true, source: nil, flags: 1, user: "UserA", mark: 1, repost: false, variants: nil, favorited: true); // Favorited = true
     let previewHandler = KeyboardActionHandler(); let previewTags: [ItemTag] = [ItemTag(id: 1, confidence: 0.9, tag: "Cool"), ItemTag(id: 2, confidence: 0.7, tag: "Video"), ItemTag(id: 3, confidence: 0.8, tag: "Längerer Tag")]; let previewComments: [ItemComment] = [ItemComment(id: 1, parent: 0, content: "Kommentar", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1)]; let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = {
         let auth = AuthService(appSettings: settings)
         auth.isLoggedIn = true // Wichtig für Preview
         return auth
     }()

     return NavigationStack {
        DetailViewContent(item: sampleVideoItem, keyboardActionHandler: previewHandler, player: previewPlayer, onWillBeginFullScreen: {}, onWillEndFullScreen: {}, tags: previewTags, comments: previewComments, infoLoadingStatus: .loaded, previewLinkTarget: $previewLinkTarget, isFavorited: true, toggleFavoriteAction: {}) // Pass state + dummy action
        .environmentObject(navService)
        .environmentObject(settings) // Inject settings
        .environmentObject(authService) // Inject auth
        .environment(\.horizontalSizeClass, .compact)
    }
}
#Preview("Regular Not Favorited") {
    // ... setup sample data ...
    let sampleImageItem = Item(id: 1, promoted: 1001, userId: 1, down: 15, up: 150, created: Int(Date().timeIntervalSince1970) - 200, image: "img1.jpg", thumb: "t1.jpg", fullsize: "f1.jpg", preview: nil, width: 800, height: 600, audio: false, source: "http://example.com", flags: 1, user: "UserA", mark: 1, repost: nil, variants: nil, favorited: false); // Favorited = false
    let previewHandler = KeyboardActionHandler(); let previewTags: [ItemTag] = [ItemTag(id: 1, confidence: 0.9, tag: "Bester Tag"), ItemTag(id: 2, confidence: 0.7, tag: "Zweiter Tag"), ItemTag(id:4, confidence: 0.6, tag:"tag3"), ItemTag(id:5, confidence: 0.5, tag:"tag4")]; let previewComments: [ItemComment] = [ItemComment(id: 1, parent: 0, content: "Kommentar https://pr0gramm.com/top/123", created: Int(Date().timeIntervalSince1970)-100, up: 5, down: 0, confidence: 0.9, name: "User", mark: 1)]; let previewPlayer: AVPlayer? = nil
     @State var previewLinkTarget: PreviewLinkTarget? = nil
     let navService = NavigationService()
     let settings = AppSettings()
     let authService = {
         let auth = AuthService(appSettings: settings)
         auth.isLoggedIn = true // Wichtig für Preview
         return auth
     }()

     return NavigationStack {
        DetailViewContent(item: sampleImageItem, keyboardActionHandler: previewHandler, player: previewPlayer, onWillBeginFullScreen: {}, onWillEndFullScreen: {}, tags: previewTags, comments: previewComments, infoLoadingStatus: .loaded, previewLinkTarget: $previewLinkTarget, isFavorited: false, toggleFavoriteAction: {}) // Pass state + dummy action
        .environmentObject(navService)
        .environmentObject(settings) // Inject settings
        .environmentObject(authService) // Inject auth
        .environment(\.horizontalSizeClass, .regular)
    }
    .previewDevice("iPad (10th generation)")
}
// --- END OF COMPLETE FILE ---
