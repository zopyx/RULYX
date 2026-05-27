import SwiftUI

// MARK: - BulkProfileLookupView

/// Bulk-resolve handles or DIDs entered as a block of text. Shows each
/// resolved profile (with avatar, display name, handle) or an error for
/// unresolvable entries.
struct BulkProfileLookupView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var viewModel = BulkProfileLookupViewModel()

    // MARK: - Body

    var body: some View {
        List {
            Section {
                TextField("bulk.input_placeholder", text: $viewModel.rawInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(5 ... 15)
                    .font(.body.monospaced())
            } header: {
                Text(loc: "bulk.input")
            } footer: {
                Text(loc: "bulk.input_footer")
            }

            if !viewModel.results.isEmpty {
                Section {
                    ForEach(viewModel.results) { result in
                        if result.isResolved, let profile = result.profile {
                            NavigationLink {
                                BlueskyProfileView(
                                    member: BlueskyListMember(
                                        recordURI: "bulk:\(profile.did)",
                                        actor: BlueskyActor(
                                            did: profile.did,
                                            handle: profile.handle,
                                            displayName: profile.displayName,
                                            avatarURL: profile.avatarURL
                                        )
                                    ),
                                    list: nil
                                )
                            } label: {
                                ProfileLookupResultRow(result: result, profile: profile)
                            }
                            .accessibilityHint("Opens the profile view for this account")
                        } else {
                            ProfileLookupResultRow(result: result, profile: nil)
                        }
                    }
                } header: {
                    HStack {
                        Text(loc: "bulk.results")
                        Spacer()
                        let resolved = viewModel.results.filter(\.isResolved).count
                        Text(verbatim: String.localized("bulk.resolved", replacements: ["resolved": "\(resolved)", "total": "\(viewModel.results.count)"]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorRetryBanner(message: errorMessage) {
                    viewModel.errorMessage = nil
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(loc: "bulk.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await runLookup() }
                    } label: {
                        Text(loc: "bulk.lookup")
                    }
                    .disabled(viewModel.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Looks up the entered handles or DIDs")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.results.isEmpty {
                    Button("bulk.clear") { viewModel.clear() }
                        .accessibilityHint("Clears all lookup results")
                }
            }
        }
    }

    /// Triggers the viewModel lookup with the active account.
    private func runLookup() async {
        await viewModel.lookup(
            account: accountStore.activeAccount,
            appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) },
            using: blueskyClient
        )
    }
}

// MARK: - ProfileLookupResultRow

/// Row showing a resolved profile (avatar, name, handle) or an error state.
private struct ProfileLookupResultRow: View {
    let result: ProfileLookupResult
    let profile: BlueskyProfile?

    var body: some View {
        HStack(spacing: 12) {
            if result.isResolved, let profile {
                Group {
                    if let avatarURL = profile.avatarURL {
                        ThumbnailImageView(url: avatarURL, maxPixelSize: 80) {
                            Circle().fill(Color.skyPrimary.opacity(0.16))
                                .overlay { Text(profile.title.prefix(1).uppercased()).font(.headline).foregroundStyle(Color.skyPrimary) }
                        }
                        .scaledToFill()
                    } else {
                        Circle().fill(Color.skyPrimary.opacity(0.16))
                            .overlay { Text(profile.title.prefix(1).uppercased()).font(.headline).foregroundStyle(Color.skyPrimary) }
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.title).font(.headline)
                    Text(profile.handle).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay { Image(systemName: "questionmark").font(.headline).foregroundStyle(.red) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.query).font(.subheadline.monospaced())
                    if let error = result.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        BulkProfileLookupView()
            .environmentObject(AccountStore(preview: true))
            .environmentObject(PreviewBlueskyClient())
    }
}
