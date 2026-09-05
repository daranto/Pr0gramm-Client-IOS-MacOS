import SwiftUI

/// Handles profile links locally and preserves the enclosing view's post-link routing.
private struct UserMentionNavigation: ViewModifier {
    @Environment(\.openURL) private var openURL
    @State private var profileTarget: UserProfileSheetTarget?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                if let username = Pr0grammLinkParser.profileUsername(from: url) {
                    profileTarget = UserProfileSheetTarget(username: username)
                } else {
                    openURL(url)
                }
                return .handled
            })
            .sheet(item: $profileTarget) { target in
                MentionedUserProfile(username: target.username)
            }
    }
}

private struct MentionedUserProfile: View {
    let username: String
    @Environment(AppSettings.self) private var settings
    @State private var playerManager = VideoPlayerManager()

    var body: some View {
        UserProfileSheetView(username: username)
            .environment(playerManager)
            .onAppear { playerManager.configure(settings: settings) }
    }
}

extension View {
    func userMentionNavigation() -> some View {
        modifier(UserMentionNavigation())
    }
}
