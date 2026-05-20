import SwiftUI

extension ListDetailView {
    struct ListDetailSubscribeSection: View {
        let currentList: BlueskyList
        @Binding var subscriptionRecordURI: String?
        @Binding var subscribeError: String?
        @Binding var isSubscribing: Bool
        let account: AppAccount
        let appPassword: String

        @EnvironmentObject var blueskyClient: LiveBlueskyClient
        @EnvironmentObject private var localizationManager: LocalizationManager

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: subscriptionRecordURI != nil ? "bell.slash.fill" : "bell.badge.fill")
                            .font(.title3)
                            .foregroundStyle(subscriptionRecordURI != nil ? .red : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: subscriptionRecordURI != nil ? loc("list.detail.subscribed") : loc("list.detail.subscribe"))
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
                        guard let myDID = account.did else {
                            subscribeError = "Account DID not available"
                            return
                        }
                        isSubscribing = true
                        subscribeError = nil
                        Task {
                            do {
                                if let recordURI = subscriptionRecordURI {
                                    try await blueskyClient.removeMember(
                                        recordURI: recordURI,
                                        account: account,
                                        appPassword: appPassword
                                    )
                                    subscriptionRecordURI = nil
                                } else {
                                    let uri = try await blueskyClient.addActor(
                                        did: myDID,
                                        to: currentList,
                                        account: account,
                                        appPassword: appPassword
                                    )
                                    subscriptionRecordURI = uri
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
                            } else if subscriptionRecordURI != nil {
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
                    .tint(subscriptionRecordURI != nil ? .red : .blue)
                    .accessibilityHint(loc("list.detail.subscribe.hint"))
                }
                .padding(.vertical, 4)
            }
        }
    }
}
