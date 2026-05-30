import SwiftUI

struct iPadProfileInspector: View {
    let did: String

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var navState: iPadNavigationState

    @StateObject private var profileVM = BlueskyProfileViewModel()

    @State private var selectedTab: ProfileTab = .profile

    enum ProfileTab: String, CaseIterable {
        case profile
        case media
        case lists

        var label: String {
            switch self {
            case .profile: "Overview"
            case .media: "Media"
            case .lists: "Lists"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if profileVM.isLoading, profileVM.inspection == nil {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(loc("lists.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let inspection = profileVM.inspection {
                profileCard(inspection)
                Divider()
                Picker("", selection: $selectedTab) {
                    ForEach(ProfileTab.allCases, id: \.self) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                tabContent(for: inspection)
            } else if let error = profileVM.errorMessage {
                ContentUnavailableView(
                    loc("profile.error"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            }
        }
        .task {
            guard let active = accountStore.activeAccount else { return }
            let password = accountStore.appPassword(for: active) ?? ""
            let dataAccount: AppAccount = if let preferredID = accountStore.preferredSearchAccountID,
                                             let preferred = accountStore.accounts.first(where: { $0.id == preferredID })
            {
                preferred
            } else {
                active
            }
            let dataPassword = accountStore.appPassword(for: dataAccount) ?? ""
            await profileVM.load(
                did: did,
                account: active,
                viewerPassword: password,
                dataAccount: dataAccount,
                dataPassword: dataPassword,
                using: blueskyClient
            )
        }
        .pageTitle(profileVM.inspection?.profile.handle ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = did
                } label: {
                    Image(systemName: "doc.on.doc")
                        .accessibilityLabel(loc("context.copy_handle"))
                }
            }
        }
    }

    private func profileCard(_ inspection: ProfileInspection) -> some View {
        let profile = inspection.profile
        let viewer = profile.viewerState
        return VStack(spacing: 12) {
            HStack(spacing: 16) {
                AsyncImage(url: profile.avatarURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName ?? profile.handle)
                        .font(.title2.weight(.bold))
                    Text("@\(profile.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let description = profile.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer()
            }

            HStack(spacing: 24) {
                statView(loc("profile.followers"), value: profile.followersCount)
                statView(loc("profile.following"), value: profile.followsCount)
                statView(loc("profile.posts"), value: profile.postsCount)
            }

            HStack(spacing: 8) {
                actionButton(loc("profile.block"), isActive: viewer?.isBlocking == true) {
                    await profileVM.toggleBlock(account: accountStore.activeAccount!, appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? "", using: blueskyClient)
                }
                actionButton(loc("profile.mute"), isActive: viewer?.muted == true) {
                    await profileVM.toggleMute(account: accountStore.activeAccount!, appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? "", using: blueskyClient)
                }
                actionButton(loc("profile.follow"), isActive: viewer?.isFollowing == true) {
                    await profileVM.toggleFollow(account: accountStore.activeAccount!, appPassword: accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) } ?? "", using: blueskyClient)
                }
            }
        }
        .padding()
    }

    private func statView(_ label: String, value: Int?) -> some View {
        VStack(spacing: 2) {
            Text("\(value ?? 0)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.skyPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func actionButton(_ title: String, isActive: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isActive ? Color.skyPrimary.opacity(0.2) : Color.fillQuarternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.skyPrimary, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    @ViewBuilder
    private func tabContent(for inspection: ProfileInspection) -> some View {
        switch selectedTab {
        case .profile:
            profileTab(inspection)
        case .media:
            mediaTab(inspection)
        case .lists:
            listsTab(inspection)
        }
    }

    private func profileTab(_ inspection: ProfileInspection) -> some View {
        List {
            if let viewer = inspection.profile.viewerState, !viewer.blockingByListName.isEmpty {
                Section(loc("profile.blocking_lists")) {
                    ForEach(viewer.blockingByListName, id: \.self) { name in
                        Text(name)
                            .font(.subheadline)
                    }
                }
            }
            if let owned = profileVM.ownedLists, !owned.isEmpty {
                Section(loc("profile.owned_lists")) {
                    ForEach(owned) { list in
                        HStack {
                            Image(systemName: list.kind.symbolName)
                                .foregroundStyle(.secondary)
                            Text(list.name)
                                .font(.subheadline)
                            Spacer()
                            if let count = list.memberCount {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func mediaTab(_ inspection: ProfileInspection) -> some View {
        let handle = inspection.profile.handle
        return MediaBrowserView(did: did, handle: handle)
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(localizationManager)
    }

    private func listsTab(_: ProfileInspection) -> some View {
        ClearskyListsView(entries: profileVM.clearskyLists)
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(localizationManager)
    }
}

private extension Color {
    static let fillQuarternary = Color(.quaternarySystemFill)
}
