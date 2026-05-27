import SwiftUI

extension ListDetailView {
    // MARK: - ListDetailSubscribeSection

    /// Section for subscribing/unsubscribing to a moderation list, with
    /// error display and a prominent toggle button.
    struct ListDetailSubscribeSection: View {
        let currentList: BlueskyList
        @Binding var isSubscribed: Bool
        @Binding var subscribeError: String?
        @Binding var isSubscribing: Bool
        let account: AppAccount
        let appPassword: String

        @EnvironmentObject var blueskyClient: LiveBlueskyClient
        @EnvironmentObject private var localizationManager: LocalizationManager

        // MARK: - Body

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: isSubscribed ? "bell.slash.fill" : "bell.badge.fill")
                            .font(.title3)
                            .foregroundStyle(isSubscribed ? .red : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: isSubscribed ? loc("list.detail.subscribed") : loc("list.detail.subscribe"))
                                .font(.subheadline.weight(.semibold))
                            Text(loc: "list.detail.subscribe.desc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = subscribeError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        isSubscribing = true
                        subscribeError = nil
                        Task {
                            do {
                                if isSubscribed {
                                    try await blueskyClient.unsubscribeFromModerationList(
                                        currentList.id,
                                        account: account,
                                        appPassword: appPassword
                                    )
                                    isSubscribed = false
                                } else {
                                    try await blueskyClient.subscribeToModerationList(
                                        currentList.id,
                                        account: account,
                                        appPassword: appPassword
                                    )
                                    isSubscribed = true
                                }
                            } catch {
                                subscribeError = AppError.userMessage(from: error)
                            }
                            isSubscribing = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubscribing {
                                ProgressView()
                                    .tint(.white)
                            } else if isSubscribed {
                                Label("list.detail.unsubscribe", systemImage: "bell.slash.fill")
                            } else {
                                Text(loc: "list.detail.subscribe")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubscribing)
                    .buttonStyle(.borderedProminent)
                    .tint(isSubscribed ? .red : .blue)
                    .accessibilityHint(loc("list.detail.subscribe.hint"))
                }
                .padding(.vertical, 4)
            }
        }
    }
}
