// Pr0gramm/Pr0gramm/Features/Views/Profile/UserProfileSheetView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Kingfisher
import os

struct UserProfileSheetView: View {
    let username: String

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var profileInfo: ProfileInfoResponse?
    @State private var isLoadingProfileInfo = false
    @State private var profileInfoError: String?

    @State private var userUploads: [Item] = []
    @State private var isLoadingUploads = false
    @State private var uploadsError: String?
    private let uploadsPageLimit = 6

    @State private var userComments: [ItemComment] = []
    @State private var isLoadingComments = false
    @State private var commentsError: String?
    private let commentsPageLimit = 5

    @State private var showPostDetailSheet = false
    @State private var itemForDetailSheet: Item? = nil
    @State private var targetCommentIDForDetailSheet: Int? = nil
    
    @State private var showAllUploadsSheet = false
    @State private var showAllCommentsSheet = false
    
    @State private var showConversationSheet = false

    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetItemId: Int? = nil

    @State private var previewLinkTargetFromComment: PreviewLinkTarget? = nil
    @State private var didLoad: Bool = false

    @StateObject private var playerManager = VideoPlayerManager()

    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserProfileSheetView")

    private let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                profileInfoSection()
                userUploadsSection()
                userCommentsSection()
            }
            .navigationTitle(username)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                Task {
                    playerManager.configure(settings: settings)
                    await loadAllData()
                }
            }
            .refreshable {
                await loadAllData(forceRefresh: true)
            }
            .onChange(of: settings.apiFlags) { _, _ in
                UserProfileSheetView.logger.info("Global filters (apiFlags) changed. Reloading data for \(username) sheet.")
                Task { await loadAllData(forceRefresh: true) }
            }
            .environment(\.openURL, OpenURLAction { url in
                if let itemID = parsePr0grammLink(url: url) {
                    UserProfileSheetView.logger.info("Pr0gramm link tapped in UserProfileSheet comment, setting previewLinkTargetFromComment.")
                    self.previewLinkTargetFromComment = PreviewLinkTarget(id: itemID)
                    return .handled
                } else {
                    UserProfileSheetView.logger.info("Non-pr0gramm link tapped in UserProfileSheet: \(url). Opening in system browser.")
                    return .systemAction
                }
            })
            .overlay {
                if isLoadingNavigationTarget {
                    ProgressView("Lade Post \(navigationTargetItemId ?? 0)...")
                        .padding().background(Material.regular).cornerRadius(10).shadow(radius: 5)
                }
            }
            .sheet(isPresented: $showPostDetailSheet, onDismiss: {
                itemForDetailSheet = nil
                targetCommentIDForDetailSheet = nil
            }) {
                if let item = itemForDetailSheet {
                    NavigationStack{
                        PagedDetailViewWrapperForItem(
                            item: item,
                            playerManager: playerManager,
                            targetCommentID: targetCommentIDForDetailSheet
                        )
                        .environmentObject(settings)
                        .environmentObject(authService)
                        .toolbar{ ToolbarItem(placement: .confirmationAction){ Button("Schließen"){ showPostDetailSheet = false } } }
                        .navigationTitle(item.user)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                    }
                }
            }
            .sheet(isPresented: $showAllUploadsSheet) {
                NavigationStack {
                    UserUploadsView(username: username)
                        .environmentObject(settings)
                        .environmentObject(authService)
                        .toolbar{ ToolbarItem(placement: .confirmationAction){ Button("Schließen"){ showAllUploadsSheet = false } } }
                }
            }
            .sheet(isPresented: $showAllCommentsSheet) {
                NavigationStack {
                    UserProfileCommentsView(username: username)
                        .environmentObject(settings)
                        .environmentObject(authService)
                        .toolbar{ ToolbarItem(placement: .confirmationAction){ Button("Schließen"){ showAllCommentsSheet = false } } }
                }
            }
            .sheet(isPresented: $showConversationSheet) {
                NavigationStack {
                    ConversationDetailView(partnerUsername: username)
                        .environmentObject(settings)
                        .environmentObject(authService)
                        .environmentObject(playerManager)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Schließen") { showConversationSheet = false }
                            }
                        }
                }
            }
            .sheet(item: $previewLinkTargetFromComment) { target in
                 LinkedItemPreviewView(itemID: target.id)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
        }
    }

    private func loadAllData(forceRefresh: Bool = false) async {
        UserProfileSheetView.logger.info("Loading all data for user \(username). Force refresh: \(forceRefresh)")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadProfileInfo(forceRefresh: forceRefresh) }
            group.addTask { await loadUserUploads(isRefresh: forceRefresh, initialLoad: true) }
            group.addTask { await loadUserComments(isRefresh: forceRefresh, initialLoad: true) }
        }
    }

    @ViewBuilder
    private func profileInfoSection() -> some View {
        Section("Benutzerinformationen") {
            if isLoadingProfileInfo && profileInfo == nil {
                HStack { Spacer(); ProgressView(); Text("Lade Profil...").font(.footnote); Spacer() }
            } else if let error = profileInfoError {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else if let info = profileInfo {
                userInfoRow(label: "Rang", valueView: {
                    HStack { UserMarkView(markValue: info.user.mark) }
                })
                if let score = info.user.score { userInfoRow(label: "Benis", value: "\(score)") }
                else { userInfoRow(label: "Benis", value: "N/A") }

                if let registeredTimestamp = info.user.registered {
                    userInfoRow(label: "Registriert seit", value: formatDateGerman(date: Date(timeIntervalSince1970: TimeInterval(registeredTimestamp))))
                } else { userInfoRow(label: "Registriert seit", value: "N/A") }

                if let badges = info.badges, !badges.isEmpty {
                    badgeScrollView(badges: badges)
                        // .listRowInsets(EdgeInsets()) // Entfernt, da das Padding jetzt in badgeScrollView gehandhabt wird
                        .padding(.vertical, 4)
                }

                if authService.isLoggedIn && authService.currentUser?.name.lowercased() != username.lowercased() {
                    Button {
                        UserProfileSheetView.logger.info("Send private message button tapped for user: \(username)")
                        showConversationSheet = true
                    } label: {
                        Label("Private Nachricht senden", systemImage: "paperplane.fill")
                    }
                    .disabled(info.user.banned != nil && info.user.banned == 1)
                }

            } else {
                Text("Keine Profilinformationen verfügbar.").foregroundColor(.secondary)
            }
        }
        .headerProminence(.increased)
    }

    private func loadProfileInfo(forceRefresh: Bool = false) async {
        if !forceRefresh && profileInfo != nil { return }
        UserProfileSheetView.logger.info("Loading profile info for \(username)...")
        await MainActor.run { isLoadingProfileInfo = true; profileInfoError = nil }
        do {
            let infoResponse = try await apiService.getProfileInfo(username: username, flags: 31)
            await MainActor.run { profileInfo = infoResponse }
        } catch {
            UserProfileSheetView.logger.error("Failed to load profile info for \(username): \(error.localizedDescription)")
            await MainActor.run { profileInfoError = error.localizedDescription }
        }
        await MainActor.run { isLoadingProfileInfo = false }
    }

    @ViewBuilder
    private func userUploadsSection() -> some View {
        Section {
            if isLoadingUploads && userUploads.isEmpty {
                HStack { Spacer(); ProgressView(); Text("Lade Uploads...").font(.footnote); Spacer() }
            } else if let error = uploadsError {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else if userUploads.isEmpty && profileInfo?.uploadCount ?? 0 > 0 {
                 Text("\(username) hat keine Uploads, die deinen aktuellen Filtern entsprechen.")
                    .foregroundColor(.secondary)
                    .font(UIConstants.footnoteFont)
            } else if userUploads.isEmpty {
                Text("\(username) hat (noch) keine Uploads.").foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(userUploads) { item in
                            Button {
                                Task { await prepareAndShowItemDetailSheet(item.id, targetCommentID: nil) }
                            } label: {
                                FeedItemThumbnail(item: item, isSeen: settings.seenItemIDs.contains(item.id))
                                    .frame(width: 100, height: 100)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingNavigationTarget)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 100)
            }
        } header: {
            Button {
                showAllUploadsSheet = true
            } label: {
                HStack {
                    Text("Neueste Uploads")
                    Spacer()
                    if let totalUploads = profileInfo?.uploadCount, totalUploads > 0 {
                        Text("Alle \(totalUploads) anzeigen")
                            .font(.caption)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled((profileInfo?.uploadCount ?? 0) == 0)
        }
        .headerProminence(.increased)
    }

    private func loadUserUploads(isRefresh: Bool = false, initialLoad: Bool = false) async {
        if !initialLoad && !isRefresh && !userUploads.isEmpty { return }
        UserProfileSheetView.logger.info("Loading uploads for \(username) (Profile Sheet - Using global filters: \(settings.apiFlags)). Refresh: \(isRefresh), Initial: \(initialLoad)")
        await MainActor.run {
            if isRefresh || initialLoad { userUploads = [] }
            isLoadingUploads = true; uploadsError = nil
        }
        do {
            let flagsToFetchWith = settings.apiFlags
            let apiResponse = try await apiService.fetchItems(flags: flagsToFetchWith, user: username, olderThanId: nil)
            let fetchedItems = apiResponse.items
            await MainActor.run { userUploads = Array(fetchedItems.prefix(uploadsPageLimit)) }
        } catch {
            UserProfileSheetView.logger.error("Failed to load uploads for \(username): \(error.localizedDescription)")
            await MainActor.run { uploadsError = error.localizedDescription }
        }
        await MainActor.run { isLoadingUploads = false }
    }

    @ViewBuilder
    private func userCommentsSection() -> some View {
        Section {
            if isLoadingComments && userComments.isEmpty {
                HStack { Spacer(); ProgressView(); Text("Lade Kommentare...").font(.footnote); Spacer() }
            } else if let error = commentsError {
                Text("Fehler: \(error)").foregroundColor(.red)
            } else if userComments.isEmpty && profileInfo?.commentCount ?? 0 > 0 {
                Text("\(username) hat keine Kommentare, die deinen aktuellen Filtern entsprechen.")
                    .foregroundColor(.secondary)
                    .font(UIConstants.footnoteFont)
            } else if userComments.isEmpty {
                Text("\(username) hat (noch) keine Kommentare geschrieben.").foregroundColor(.secondary)
            } else {
                ForEach(userComments) { comment in
                    Button {
                        Task { await prepareAndShowItemDetailSheet(comment.itemId, targetCommentID: comment.id) }
                    } label: {
                        FavoritedCommentRow(
                            comment: comment,
                            overrideUsername: username,
                            overrideUserMark: profileInfo?.user.mark
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(comment.itemId == nil || isLoadingNavigationTarget)
                }
            }
        } header: {
            Button {
                showAllCommentsSheet = true
            } label: {
                HStack {
                    Text("Neueste Kommentare")
                    Spacer()
                    if let totalComments = profileInfo?.commentCount, totalComments > 0 {
                        Text("Alle \(totalComments) anzeigen")
                            .font(.caption)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled((profileInfo?.commentCount ?? 0) == 0)
        }
        .headerProminence(.increased)
    }

    private func loadUserComments(isRefresh: Bool = false, initialLoad: Bool = false) async {
        if !initialLoad && !isRefresh && !userComments.isEmpty { return }
        UserProfileSheetView.logger.info("Loading comments for \(username) (Profile Sheet - Using global filters: \(settings.apiFlags)). Refresh: \(isRefresh), Initial: \(initialLoad)")
        await MainActor.run {
            if isRefresh || initialLoad { userComments = [] }
            isLoadingComments = true; commentsError = nil
        }
        do {
            let flagsToFetchWith = settings.apiFlags
            let response = try await apiService.fetchProfileComments(username: username, flags: flagsToFetchWith, before: nil)
            await MainActor.run {
                userComments = Array(response.comments.prefix(commentsPageLimit))
            }
        } catch {
            UserProfileSheetView.logger.error("Failed to load comments for \(username): \(error.localizedDescription)")
            await MainActor.run { commentsError = error.localizedDescription }
        }
        await MainActor.run { isLoadingComments = false }
    }

    @MainActor
    private func prepareAndShowItemDetailSheet(_ itemId: Int?, targetCommentID: Int?) async {
        guard let id = itemId else {
            UserProfileSheetView.logger.warning("Attempted to show item detail sheet, but itemId was nil.")
            return
        }
        guard !isLoadingNavigationTarget else {
            UserProfileSheetView.logger.debug("Skipping item detail sheet prep for \(id): Already loading another target.")
            return
        }

        UserProfileSheetView.logger.info("Preparing to show item detail sheet for item ID: \(id), targetCommentID: \(targetCommentID ?? -1)")
        isLoadingNavigationTarget = true
        navigationTargetItemId = id
        
        itemForDetailSheet = nil
        targetCommentIDForDetailSheet = nil

        do {
            let flagsToFetchWith = settings.apiFlags
            UserProfileSheetView.logger.debug("Fetching item \(id) for sheet display using global flags: \(flagsToFetchWith)")
            let fetchedItem = try await apiService.fetchItem(id: id, flags: flagsToFetchWith)

            guard navigationTargetItemId == id else {
                 UserProfileSheetView.logger.info("Sheet target changed while item \(id) was loading. Discarding result.")
                 isLoadingNavigationTarget = false; navigationTargetItemId = nil; return
            }
            if let item = fetchedItem {
                UserProfileSheetView.logger.info("Successfully fetched item \(id) for sheet display.")
                itemForDetailSheet = item
                targetCommentIDForDetailSheet = targetCommentID
                showPostDetailSheet = true
            } else {
                UserProfileSheetView.logger.warning("Could not fetch item \(id) for sheet display (API returned nil or item does not match filters).")
            }
        } catch is CancellationError {
            UserProfileSheetView.logger.info("Item fetch for sheet display cancelled (ID: \(id)).")
        } catch {
            UserProfileSheetView.logger.error("Failed to fetch item \(id) for sheet display: \(error.localizedDescription)")
        }
        if navigationTargetItemId == id {
             isLoadingNavigationTarget = false
             navigationTargetItemId = nil
        }
    }

    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() { if let itemID = Int(component) { return itemID } }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems { if item.name == "id", let value = item.value, let itemID = Int(value) { return itemID } }
        }
        UserProfileSheetView.logger.warning("Could not parse item ID from pr0gramm link: \(url.absoluteString)")
        return nil
    }

    @ViewBuilder
    private func userInfoRow(label: String, value: String) -> some View {
        HStack { Text(label).font(UIConstants.bodyFont); Spacer(); Text(value).font(UIConstants.bodyFont).foregroundColor(.secondary) }
    }

    @ViewBuilder
    private func userInfoRow<ValueView: View>(label: String, @ViewBuilder valueView: () -> ValueView) -> some View {
        HStack { Text(label).font(UIConstants.bodyFont); Spacer(); valueView() }
    }

    @ViewBuilder
    private func badgeScrollView(badges: [ApiBadge]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(badges, id: \.id) { badge in
                    KFImage(badge.fullImageUrl)
                        .placeholder { Circle().fill(.gray.opacity(0.2)).frame(width: 32, height: 32) }
                        .resizable().scaledToFit().frame(width: 32, height: 32)
                        .clipShape(Circle()).overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                        .help(badge.description ?? "")
                }
            }
            // --- MODIFIED: Adjust padding to align with List content ---
            // Using .padding(.leading) on the HStack to simulate the List's default content inset.
            // The exact value might need minor adjustments based on testing on different devices/OS versions.
            // Common values are around 15-20.
            .padding(.leading, 1) // Default List row content leading padding
            // --- END MODIFICATION ---
        }
    }

    private func formatDateGerman(date: Date) -> String { germanDateFormatter.string(from: date) }
}

#Preview("UserProfileSheetView Preview") {
    struct PreviewWrapper: View {
        @StateObject private var authService: AuthService
        @StateObject private var settings = AppSettings()

        init() {
            let tempSettings = AppSettings()
            let tempAuth = AuthService(appSettings: tempSettings)
            tempAuth.isLoggedIn = true
            tempAuth.currentUser = UserInfo(id: 1, name: "Rockabilly", registered: 1609459200, score: 12345, mark: 2, badges: [
                ApiBadge(image: "pr0-coin.png", description: "Test Badge 1", created: 0, link: nil, category: nil),
                ApiBadge(image: "pr0mium-s.png", description: "Test Badge 2", created: 0, link: nil, category: nil),
                ApiBadge(image: "comment-gold.png", description: "Test Badge 3", created: 0, link: nil, category: nil),
                ApiBadge(image: "secret-santa-2015.png", description: "Test Badge 4", created: 0, link: nil, category: nil)
            ], collections: [])

            _settings = StateObject(wrappedValue: tempSettings)
            _authService = StateObject(wrappedValue: tempAuth)
        }

        var body: some View {
            Text("Parent View")
                .sheet(isPresented: .constant(true)) {
                    UserProfileSheetView(username: "AnotherUser")
                        .environmentObject(authService)
                        .environmentObject(settings)
                }
        }
    }
    return PreviewWrapper()
}
// --- END OF COMPLETE FILE ---
