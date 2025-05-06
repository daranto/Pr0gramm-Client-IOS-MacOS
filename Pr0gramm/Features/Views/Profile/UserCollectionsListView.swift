// Pr0gramm/Pr0gramm/Features/Views/Profile/UserCollectionsListView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import os

/// Displays a list of all collections for a given user.
/// Each collection is a navigation link to view its items.
struct UserCollectionsListView: View {
    let username: String // Username whose collections to display

    @EnvironmentObject var authService: AuthService // To get the collections
    @EnvironmentObject var settings: AppSettings // For PagedDetailViewWrapperForItem if needed

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UserCollectionsListView")

    private var collectionsToDisplay: [ApiCollection] {
        return authService.userCollections.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if authService.userCollections.isEmpty {
                ContentUnavailableView {
                    Label("Keine Sammlungen", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text("\(username) hat noch keine eigenen Sammlungen erstellt.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
            }
        }
        .navigationTitle("Sammlungen von \(username)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            UserCollectionsListView.logger.debug("UserCollectionsListView appeared for \(username). Found \(authService.userCollections.count) collections in AuthService.")
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            ForEach(collectionsToDisplay) { collection in
                NavigationLink(value: ProfileNavigationTarget.collectionItems(collection: collection, username: username)) {
                    HStack {
                        // --- MODIFIED: Removed Keyword display ---
                        Text(collection.name)
                            .font(UIConstants.bodyFont)
                            .foregroundColor(.primary)
                        // --- END MODIFICATION ---
                        Spacer()
                        Text("\(collection.itemCount) Posts")
                            .font(UIConstants.subheadlineFont)
                            .foregroundColor(.secondary)
                        // --- REMOVED: Star for default collection ---
                        // if collection.isActuallyDefault {
                        //     Image(systemName: "star.fill")
                        //         .foregroundColor(.yellow)
                        //         .font(.caption)
                        // }
                        // --- END REMOVAL ---
                    }
                }
            }
        }
    }
}

// MARK: - Previews
#Preview {
    struct UserCollectionsListViewPreviewWrapper: View {
        @StateObject private var settings: AppSettings
        @StateObject private var authService: AuthService
        let usernameForPreview: String

        init(collections: [ApiCollection], username: String) {
            let tempSettings = AppSettings()
            let tempAuthService = AuthService(appSettings: tempSettings)
            tempAuthService.isLoggedIn = true
            tempAuthService.currentUser = UserInfo(id: 1, name: username, registered: 1, score: 1337, mark: 2, badges: [], collections: collections)
            #if DEBUG
            tempAuthService.setUserCollectionsForPreview(collections)
            #endif

            _settings = StateObject(wrappedValue: tempSettings)
            _authService = StateObject(wrappedValue: tempAuthService)
            self.usernameForPreview = username
        }

        var body: some View {
            NavigationStack {
                UserCollectionsListView(username: usernameForPreview)
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
        }
    }

    let sampleCollections = [
        ApiCollection(id: 101, name: "Meine Favoriten", keyword: "favoriten", isPublic: 0, isDefault: 1, itemCount: 1234),
        ApiCollection(id: 102, name: "Lustige Katzen Videos", keyword: "katzen", isPublic: 0, isDefault: 0, itemCount: 45),
        ApiCollection(id: 103, name: "Wallpaper Material", keyword: "wallpaper", isPublic: 1, isDefault: 0, itemCount: 289)
    ]
    return UserCollectionsListViewPreviewWrapper(collections: sampleCollections, username: "Daranto")
}

#Preview("Empty Collections") {
    struct UserCollectionsListViewEmptyPreviewWrapper: View {
        @StateObject private var settings = AppSettings()
        @StateObject private var authService: AuthService
        let usernameForPreview: String

        init() {
            let tempSettings = AppSettings()
            let tempAuthService = AuthService(appSettings: tempSettings)
            tempAuthService.isLoggedIn = true
            tempAuthService.currentUser = UserInfo(id: 2, name: "TestUser", registered: 1, score: 100, mark: 1, badges: [], collections: [])
            #if DEBUG
            tempAuthService.setUserCollectionsForPreview([])
            #endif
            
            _settings = StateObject(wrappedValue: tempSettings)
            _authService = StateObject(wrappedValue: tempAuthService)
            self.usernameForPreview = "TestUser"
        }
        
        var body: some View {
            NavigationStack {
                UserCollectionsListView(username: usernameForPreview)
                    .environmentObject(settings)
                    .environmentObject(authService)
            }
        }
    }
    return UserCollectionsListViewEmptyPreviewWrapper()
}
// --- END OF COMPLETE FILE ---
