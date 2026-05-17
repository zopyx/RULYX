import SwiftUI

struct BulkProfileLookupView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @StateObject private var viewModel = BulkProfileLookupViewModel()

    var body: some View {
        List {
            Section {
                TextField(loc("bulk.input_placeholder"), text: $viewModel.rawInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(5 ... 15)
                    .font(.body.monospaced())
            } header: {
                Text(verbatim: loc("bulk.input"))
            } footer: {
                Text(verbatim: loc("bulk.input_footer"))
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
                        Text(verbatim: loc("bulk.results"))
                        Spacer()
                        let resolved = viewModel.results.filter(\.isResolved).count
                        Text("\(resolved)/\(viewModel.results.count) resolved")
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
        .navigationTitle(loc("bulk.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await runLookup() }
                    } label: {
                        Text(verbatim: loc("bulk.lookup"))
                    }
                    .disabled(viewModel.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Looks up the entered handles or DIDs")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.results.isEmpty {
                    Button(loc("bulk.clear")) { viewModel.clear() }
                        .accessibilityHint("Clears all lookup results")
                }
            }
        }
    }

    private func runLookup() async {
        await viewModel.lookup(
            account: accountStore.activeAccount,
            appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) },
            using: blueskyClient
        )
    }
}

private struct ProfileLookupResultRow: View {
    let result: ProfileLookupResult
    let profile: BlueskyProfile?

    var body: some View {
        HStack(spacing: 12) {
            if result.isResolved, let profile {
                AsyncImage(url: profile.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.skyPrimary.opacity(0.16))
                        .overlay { Text(profile.title.prefix(1).uppercased()).font(.headline).foregroundStyle(Color.skyPrimary) }
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
