import SwiftUI

/// Sheet displaying full group conversation metadata: name, member count,
/// creation date, lock status, and a scrollable member list.
///
/// Accessible from the conversation detail toolbar menu for group conversations.
struct GroupInfoSheet: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    let conversation: ChatConversation
    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var showLockConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var memberToRemove: ChatMemberProfile?
    @State private var showAddMember = false

    private var groupInfo: ChatGroupInfo? { conversation.groupInfo }
    private var isLocked: Bool { groupInfo?.lockStatus == "locked" || groupInfo?.lockStatus == "permanently locked" }
    private var isPermanentlyLocked: Bool { groupInfo?.lockStatus == "permanently locked" }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Group Identity

                Section {
                    HStack(spacing: 16) {
                        GroupAvatarView(
                            members: conversation.members,
                            groupName: conversation.groupInfo?.name ?? "",
                            size: 60
                        )
                        .frame(width: 60, height: 60)

                        VStack(alignment: .leading, spacing: 4) {
                            if isEditingName {
                                TextField(loc("chat.group_info.name_placeholder"), text: $editedName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.headline)
                            } else {
                                Text(conversation.groupInfo?.name ?? loc("chat.unknown"))
                                    .font(.headline)
                                    .lineLimit(1)
                            }

                            Text(String.localized("chat.group_info.members", replacements: ["n": "\(groupInfo?.memberCount ?? conversation.members.count)"]))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    if !isEditingName {
                        Button {
                            editedName = conversation.groupInfo?.name ?? ""
                            isEditingName = true
                        } label: {
                            Label(loc("chat.edit_name.save"), systemImage: "pencil")
                        }
                    } else {
                        HStack {
                            Button(loc("chat.edit_name.save")) {
                                let name = editedName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                Task { await chatStore.updateGroupName(convoId: conversation.id, name: name) }
                                isEditingName = false
                            }
                            .buttonStyle(.borderedProminent)

                            Button(loc("chat.edit_name.cancel")) {
                                isEditingName = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // MARK: Info

                Section {
                    if let createdAt = groupInfo?.createdAt {
                        LabeledContent(loc("chat.group_info.created"), value: createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent(loc("chat.group_info.locked"), value: isLocked ? loc("chat.lock.locked") : loc("chat.lock.unlocked"))

                    if !isPermanentlyLocked {
                        Button(isLocked ? loc("chat.lock.unlock") : loc("chat.lock.lock")) {
                            if isLocked {
                                Task { await chatStore.unmute(convoId: conversation.id) }
                            } else {
                                showLockConfirmation = true
                            }
                        }
                    }
                }

                // MARK: Members

                Section {
                    ForEach(conversation.members) { member in
                        HStack(spacing: 12) {
                            memberAvatar(member, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName ?? member.handle)
                                    .font(.subheadline.weight(.semibold))
                                Text("@\(member.handle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if member.did == accountStore.activeAccount?.did {
                                Text(loc("chat.group_info.you"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openProfile(member)
                        }
                        .swipeActions(edge: .trailing) {
                            if member.did != accountStore.activeAccount?.did {
                                Button(role: .destructive) {
                                    memberToRemove = member
                                    showRemoveConfirmation = true
                                } label: {
                                    Label(loc("chat.remove_member.remove"), systemImage: "person.fill.badge.minus")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(loc("chat.group_info.members_header"))
                        Spacer()
                        if !isLocked {
                            Button {
                                showAddMember = true
                            } label: {
                                Image(systemName: "person.badge.plus")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .pageTitle(loc("chat.group_info.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.done")) { dismiss() }
                }
            }
            .confirmationDialog(
                loc("chat.lock.confirm"),
                isPresented: $showLockConfirmation,
                titleVisibility: .visible
            ) {
                Button(loc("chat.lock.lock"), role: .destructive) {
                    Task { await chatStore.mute(convoId: conversation.id) }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                loc("chat.remove_member.confirm"),
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible,
                presenting: memberToRemove
            ) { member in
                Button(loc("chat.remove_member.remove"), role: .destructive) {
                    Task { await chatStore.removeMember(convoId: conversation.id, memberDID: member.did) }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            } message: { member in
                Text(String.localized("chat.remove_member.confirm_desc", replacements: ["handle": member.handle]))
            }
            .sheet(isPresented: $showAddMember) {
                AddMemberSheet(conversation: conversation)
                    .environmentObject(chatStore)
                    .environmentObject(accountStore)
                    .environmentObject(container)
                    .environmentObject(localizationManager)
            }
        }
    }

    @ViewBuilder
    private func memberAvatar(_ member: ChatMemberProfile, size: CGFloat) -> some View {
        if let url = member.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.tertiary)
        }
    }

    private func openProfile(_ member: ChatMemberProfile) {
        // Profile sheet handled by the parent view via navigation
        // In a full implementation, this would open BlueskyProfileView
    }
}
