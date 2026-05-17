import SwiftUI

struct LikesListView: View {
    let uri: String

    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var likes: [LikeItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var cursor: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingPanel(message: loc("timeline.loading"))
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        loc("list.detail.alert_title"),
                        systemImage: "exclamationmark.bubble",
                        description: Text(error)
                    )
                } else if likes.isEmpty {
                    ContentUnavailableView(
                        loc("likes.empty"),
                        systemImage: "heart",
                        description: Text(verbatim: loc("likes.empty_desc"))
                    )
                } else {
                    List {
                        ForEach(likes, id: \.createdAt) { like in
                            HStack(spacing: 10) {
                                if let avatar = like.actor.avatar.flatMap(URL.init) {
                                    AsyncImage(url: avatar) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Circle().fill(Color.skyPrimary.opacity(0.16))
                                    }
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.skyPrimary.opacity(0.16))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Text((like.actor.displayName ?? like.actor.handle ?? "?").prefix(1).uppercased())
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.skyPrimary)
                                        }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(like.actor.displayName ?? like.actor.handle ?? "")
                                        .font(.subheadline.weight(.semibold))
                                    if let handle = like.actor.handle {
                                        Text("@\(handle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        if cursor != nil {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                Spacer()
                            }
                            .task {
                                await loadMore()
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(loc("likes.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.close")) { dismiss() }
                }
            }
            .task {
                await loadLikes()
            }
        }
    }

    private func loadLikes() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await blueskyClient.fetchLikes(uri: uri, account: account, appPassword: appPassword)
            likes = response.likes
            cursor = response.cursor
        } catch {
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load likes: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let cursor else { return }
        do {
            let response = try await blueskyClient.fetchLikes(uri: uri, cursor: cursor, account: account, appPassword: appPassword)
            likes += response.likes
            self.cursor = response.cursor
        } catch {
            AppLogger.moderation.error("Failed to load more likes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
