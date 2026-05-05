import SwiftUI

struct BlockedUsersListView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        List {
            if authService.isLoadingBlockedUsers && authService.blockedUsers.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Lade Blockierungen…")
                    Spacer()
                }
            } else if authService.blockedUsers.isEmpty {
                ContentUnavailableView {
                    Label("Keine Blockierungen", systemImage: "person.crop.circle.badge.checkmark")
                } description: {
                    Text("Du hast aktuell keine User blockiert.")
                }
            } else {
                ForEach(authService.blockedUsers) { blockedUser in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(blockedUser.name)
                                .font(UIConstants.bodyFont)
                            UserMarkView(markValue: blockedUser.mark)
                        }
                        Spacer()
                    Button("Entblocken") {
                        Task { await authService.unblockUser(name: blockedUser.name) }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .disabled(authService.isModifyingBlockStatus[blockedUser.name] ?? false)
                }
                }
            }
        }
        .navigationTitle("Blockierungen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable {
            await authService.fetchBlockedUsers()
        }
        .task {
            await authService.fetchBlockedUsers()
        }
    }
}
