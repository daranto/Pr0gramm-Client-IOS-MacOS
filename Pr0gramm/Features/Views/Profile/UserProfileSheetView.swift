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
    @EnvironmentObject var playerManager: VideoPlayerManager


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
    @State private var showingFollowActions = false

    @State private var isLoadingNavigationTarget: Bool = false
    @State private var navigationTargetItemId: Int? = nil

    @State private var previewLinkTargetFromComment: PreviewLinkTarget? = nil
    @State private var didLoad: Bool = false


    private let apiService = APIService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserProfileSheetView")

    private let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    private var isCurrentUserProfile: Bool {
        authService.currentUser?.name.lowercased() == username.lowercased()
    }

    private var isFollowingThisUser: Bool {
        if let apiFollows = profileInfo?.follows {
            return apiFollows
        }
        return authService.followedUsers.contains { $0.name.lowercased() == username.lowercased() }
    }

    private var isSubscribedToThisUser: Bool {
        if let apiSubscribed = profileInfo?.subscribed {
            return apiSubscribed
        }
        return authService.subscribedUsernames.contains(username)
    }


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
                    await loadAllData()
                }
            }
            .refreshable {
                await loadAllData(forceRefresh: true)
            }
            .onChange(of: settings.apiFlags) {
                UserProfileSheetView.logger.info("Global filters (apiFlags) changed. Reloading data for \(username) sheet.")
                Task { await loadAllData(forceRefresh: true) }
            }
            .onChange(of: authService.followedUsers) {
                UserProfileSheetView.logger.debug("authService.followedUsers changed, profile sheet for \(username) might re-evaluate buttons.")
                Task { await loadProfileInfo(forceRefresh: true) }
            }
            .onChange(of: authService.subscribedUsernames) {
                UserProfileSheetView.logger.debug("authService.subscribedUsernames changed, profile sheet for \(username) might re-evaluate buttons.")
                Task { await loadProfileInfo(forceRefresh: true) }
            }
            .environment(\.openURL, OpenURLAction { url in
                if let (itemID, commentID) = parsePr0grammLink(url: url) {
                    UserProfileSheetView.logger.info("Pr0gramm link tapped in UserProfileSheet comment, setting previewLinkTargetFromComment. itemID: \(itemID), commentID: \(commentID ?? -1)")
                    self.previewLinkTargetFromComment = PreviewLinkTarget(itemID: itemID, commentID: commentID)
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
            .confirmationDialog("Aktionen für \(username)", isPresented: $showingFollowActions, titleVisibility: .visible) {
                confirmationDialogButtons()
            } message: {
                Text("Wähle eine Aktion:")
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
                            targetCommentID: targetCommentIDForDetailSheet,
                            isPresentedInSheet: true
                        )
                        .environmentObject(settings)
                        .environmentObject(authService)
                    }
                }
            }
            .sheet(isPresented: $showAllUploadsSheet) {
                NavigationStack {
                    UserUploadsView(username: username)
                        .environmentObject(settings)
                        .environmentObject(authService)
                        .environmentObject(playerManager)
                        .toolbar{ ToolbarItem(placement: .confirmationAction){ Button("Schließen"){ showAllUploadsSheet = false } } }
                }
            }
            .sheet(isPresented: $showAllCommentsSheet) {
                NavigationStack {
                    UserProfileCommentsView(username: username)
                        .environmentObject(settings)
                        .environmentObject(authService)
                        .environmentObject(playerManager)
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
                 LinkedItemPreviewView(itemID: target.itemID, targetCommentID: target.commentID)
                     .environmentObject(settings)
                     .environmentObject(authService)
            }
        }
        .tint(settings.accentColorChoice.swiftUIColor)
    }

    private func loadAllData(forceRefresh: Bool = false) async {
        UserProfileSheetView.logger.info("Loading all data for user \(username). Force refresh: \(forceRefresh)")
        if authService.isLoggedIn && (forceRefresh || authService.followedUsers.isEmpty && !isCurrentUserProfile) {
            await authService.fetchFollowList()
        }
        await loadProfileInfo(forceRefresh: forceRefresh)
        
        await withTaskGroup(of: Void.self) { group in
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
                        .padding(.vertical, 4)
                }
                
                if authService.isLoggedIn && !isCurrentUserProfile {
                    HStack(spacing: 0) {
                        Button {
                            UserProfileSheetView.logger.info("Nachricht senden an \(username) getippt.")
                            showConversationSheet = true
                        } label: {
                            Label("Nachricht senden", systemImage: "paperplane.fill")
                                .font(UIConstants.bodyFont)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(Color.accentColor)
                        .disabled(info.user.banned != nil && info.user.banned == 1)

                        Button {
                            UserProfileSheetView.logger.info("Follow/Subscribe Aktionen für \(username) getippt.")
                            showingFollowActions = true
                        } label: {
                            Label(isFollowingThisUser ? "Gefolgt" : "Folgen", systemImage: isFollowingThisUser ? "person.fill.checkmark" : "person.badge.plus")
                                .font(UIConstants.bodyFont)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(isFollowingThisUser ? .green : Color.accentColor)
                        .disabled(authService.isModifyingFollowStatus[username] ?? false)
                    }
                    .padding(.vertical, 5)
                }

            } else {
                Text("Keine Profilinformationen verfügbar.").foregroundColor(.secondary)
            }
        }
        .headerProminence(.increased)
    }
    
    @ViewBuilder
    private func confirmationDialogButtons() -> some View {
        let modifyingStatus = authService.isModifyingFollowStatus[username] ?? false

        Button(isFollowingThisUser ? "Entfolgen" : "Folgen") {
            Task {
                if isFollowingThisUser {
                    await authService.unfollowUser(name: username)
                } else {
                    await authService.followUser(name: username)
                }
                await loadProfileInfo(forceRefresh: true)
            }
        }
        .disabled(modifyingStatus)

        if isFollowingThisUser {
            Button(isSubscribedToThisUser ? "Benachrichtigungen Deaktivieren" : "Benachrichtigen") {
                Task {
                    if isSubscribedToThisUser {
                        await authService.unsubscribeFromUserNotifications(name: username, keepFollow: true)
                    } else {
                        await authService.subscribeToUserNotifications(name: username)
                    }
                    await loadProfileInfo(forceRefresh: true)
                }
            }
            .disabled(modifyingStatus)
        } else {
             Button("Folgen und Benachrichtigen") {
                 Task {
                     UserProfileSheetView.logger.info("Attempting to follow AND subscribe to \(username)")
                     await authService.followUser(name: username)
                     try? await Task.sleep(for: .milliseconds(500))
                     await loadProfileInfo(forceRefresh: true)
                     if self.isFollowingThisUser {
                         await authService.subscribeToUserNotifications(name: username)
                         await loadProfileInfo(forceRefresh: true)
                     } else {
                         UserProfileSheetView.logger.warning("Konnte nicht subscriben, da Follow-Aktion für \(username) nicht erfolgreich zu sein scheint oder Status nicht schnell genug aktualisiert wurde.")
                     }
                 }
             }
             .disabled(modifyingStatus)
        }
        
        Button("Abbrechen", role: .cancel) { }
    }


    private func loadProfileInfo(forceRefresh: Bool = false) async {
        if !forceRefresh && profileInfo != nil {
             UserProfileSheetView.logger.trace("Skipping profile info load for \(username), already loaded and not forced.")
            return
        }
        UserProfileSheetView.logger.info("Loading profile info for \(username)... Force: \(forceRefresh)")
        await MainActor.run { isLoadingProfileInfo = true; profileInfoError = nil }
        do {
            let infoResponse = try await apiService.getProfileInfo(username: username, flags: 31)
            await MainActor.run { profileInfo = infoResponse }
            let followsStatus = infoResponse.follows.map { String(describing: $0) } ?? "N/A"
            let subscribedStatus = infoResponse.subscribed.map { String(describing: $0) } ?? "N/A"
            UserProfileSheetView.logger.info("Profile info for \(username) loaded. API-Reported Follows: \(followsStatus), Subscribed: \(subscribedStatus)")
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

    private func parsePr0grammLink(url: URL) -> (itemID: Int, commentID: Int?)? {
        guard let host = url.host?.lowercased(), (host == "pr0gramm.com" || host == "www.pr0gramm.com") else { return nil }

        let path = url.path
        let components = path.components(separatedBy: "/")
        var itemID: Int? = nil
        var commentID: Int? = nil

        if let lastPathComponent = components.last {
            if lastPathComponent.contains(":comment") {
                let parts = lastPathComponent.split(separator: ":")
                if parts.count == 2, let idPart = Int(parts[0]), parts[1].starts(with: "comment"), let cID = Int(parts[1].dropFirst("comment".count)) {
                    itemID = idPart
                    commentID = cID
                }
            } else {
                var potentialItemIDIndex: Int? = nil
                if let idx = components.lastIndex(where: { $0 == "new" || $0 == "top" }), idx + 1 < components.count {
                    potentialItemIDIndex = idx + 1
                } else if components.count > 1 && Int(components.last!) != nil {
                    potentialItemIDIndex = components.count - 1
                }
                
                if let idx = potentialItemIDIndex, let id = Int(components[idx]) {
                    itemID = id
                }
            }
        }
        
        if itemID == nil, let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let id = Int(value) {
                    itemID = id
                    break
                }
            }
        }
        
        if let itemID = itemID {
            return (itemID, commentID)
        }

        UserProfileSheetView.logger.warning("Could not parse item or comment ID from pr0gramm link: \(url.absoluteString)")
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
            .padding(.leading, 1)
        }
    }

    private func formatDateGerman(date: Date) -> String { germanDateFormatter.string(from: date) }
}
// --- END OF COMPLETE FILE ---


