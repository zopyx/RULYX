import SwiftUI

// MARK: - ConversationDetailView

/// Full conversation view with scrollable message list, send bar,
/// profile navigation, mute/leave actions, group management, and scroll-to-bottom button.
struct ConversationDetailView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var messageText = ""
    @State private var showProfile = false
    @State private var mentionProfileHandle: String?
    @State private var showScrollToBottom = false
    @State private var showGroupInfo = false
    @FocusState private var isFocused: Bool

    let conversation: ChatConversation

    /// Messages for the current conversation.
    private var convoMessages: [ChatMessageKind] {
        chatStore.messages[conversation.id] ?? []
    }

    /// The other participant in a 1:1 conversation.
    private var otherMember: ChatMemberProfile? {
        conversation.members.first { $0.did != chatStore.currentAccountDID }
    }

    /// User-facing name: group name, other member's name, or fallback.
    private var displayName: String {
        if let groupInfo = conversation.groupInfo, !groupInfo.name.isEmpty {
            return groupInfo.name
        }
        if let member = otherMember {
            return member.displayName ?? member.handle
        }
        return conversation.members.first?.handle ?? loc("chat.unknown")
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            if let error = chatStore.messageError, convoMessages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(loc("state.error.retry")) {
                        Task { await chatStore.loadMessages(convoId: conversation.id) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                scrollView
                    .padding(.bottom, 52)
            }

            sendBar
        }
        .pageTitle(displayName)
        .task {
            chatStore.error = nil
            chatStore.setVisibleConversation(conversation.id)
            await chatStore.loadMessages(convoId: conversation.id)
            await chatStore.markRead(convoId: conversation.id, messageId: lastMessageId)
        }
        .onAppear {
            chatStore.setChatViewVisible(true, token: "conversationDetail")
        }
        .onDisappear {
            if chatStore.currentAccountDID != nil {
                chatStore.setVisibleConversation(nil)
            }
            chatStore.setChatViewVisible(false, token: "conversationDetail")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let member = otherMember {
                    Button {
                        showProfile = true
                    } label: {
                        HStack(spacing: 6) {
                            avatarView(url: member.avatarURL, size: 32)
                            Text(displayName)
                                .font(.headline)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(displayName)
                        .font(.headline)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Group info (for group conversations)
                    if conversation.kind == .group {
                        Button {
                            showGroupInfo = true
                        } label: {
                            Label(loc("chat.group.info"), systemImage: "person.3")
                        }
                    }

                    if conversation.muted {
                        Button {
                            Task { await chatStore.unmute(convoId: conversation.id) }
                        } label: {
                            Label(loc("chat.unmute"), systemImage: "bell")
                        }
                    } else {
                        Button {
                            Task { await chatStore.mute(convoId: conversation.id) }
                        } label: {
                            Label(loc("chat.mute"), systemImage: "bell.slash")
                        }
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await chatStore.loadMessages(convoId: conversation.id) }
                    } label: {
                        Label(loc("chat.reload"), systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        Task { await chatStore.leave(convoId: conversation.id) }
                    } label: {
                        Label(loc("chat.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            if let member = otherMember {
                NavigationStack {
                    BlueskyProfileView(
                        member: BlueskyListMember(
                            recordURI: "chat:\(member.did)",
                            actor: BlueskyActor(
                                did: member.did,
                                handle: member.handle,
                                displayName: member.displayName,
                                avatarURL: member.avatarURL
                            )
                        ),
                        list: nil
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                    .environmentObject(workspaceStore)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showProfile = false
                            } label: {
                                Image(systemName: "chevron.down.circle.fill")
                            }
                            .accessibilityLabel(loc("actions.done"))
                        }
                    }
                }
                .interactiveDismissDisabled(false)
            }
        }
        .sheet(item: $mentionProfileHandle) { handle in
            NavigationStack {
                BlueskyProfileView(
                    member: BlueskyListMember(
                        recordURI: "mention:\(handle)",
                        actor: BlueskyActor(
                            did: handle,
                            handle: handle,
                            displayName: nil,
                            avatarURL: nil
                        )
                    ),
                    list: nil
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            mentionProfileHandle = nil
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                        }
                        .accessibilityLabel(loc("actions.done"))
                    }
                }
            }
            .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showGroupInfo) {
            if conversation.kind == .group {
                GroupInfoSheet(conversation: conversation)
                    .environmentObject(chatStore)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
    }

    // MARK: - Subviews

    /// Scrollable message list with auto-scroll and load-more trigger.
    private var scrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if chatStore.isLoadingMessages, convoMessages.isEmpty {
                        VStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(maxHeight: .infinity)
                    }

                    if chatStore.hasMoreMessages[conversation.id] == true {
                        HStack {
                            Spacer()
                            if chatStore.isLoadingMoreMessages {
                                ProgressView()
                            } else {
                                Button(loc("chat.load_older")) {
                                    Task { await chatStore.loadMoreMessages(convoId: conversation.id) }
                                }
                                .font(.subheadline)
                                .buttonStyle(.bordered)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .task {
                            guard chatStore.hasMoreMessages[conversation.id] == true else { return }
                            await chatStore.loadMoreMessages(convoId: conversation.id)
                        }
                    }

                    let withIds = convoMessages.enumerated().map { index, kind in
                        (id: "msg-\(idFor(kind))-\(index)", kind: kind)
                    }

                    ForEach(withIds, id: \.id) { item in
                        messageView(for: item.kind)
                            .id(item.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { showScrollToBottom = false }
                        .onDisappear { showScrollToBottom = true }
                }
            }
            .task(id: convoMessages.count) {
                guard convoMessages.count > 0, convoMessages.count <= 50 else { return }
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToBottom {
                    Button {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        showScrollToBottom = false
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.skyPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.bar))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    /// Bottom input bar with text field and send button.
    private var sendBar: some View {
        HStack(spacing: 8) {
            TextField(loc("chat.message.placeholder"), text: $messageText)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .disabled(chatStore.isSendingMessage)

            Button {
                let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                messageText = ""
                Task { await chatStore.sendMessage(convoId: conversation.id, text: text) }
            } label: {
                if chatStore.isSendingMessage {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.tertiaryLabel) : Color.skyPrimary)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || chatStore.isSendingMessage)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.bar)
    }

    /// Async avatar image with person.circle.fill fallback.
    @ViewBuilder
    private func avatarView(url: URL?, size: CGFloat) -> some View {
        if let url {
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

    /// Renders a message bubble, deleted placeholder, or system message.
    @ViewBuilder
    private func messageView(for kind: ChatMessageKind) -> some View {
        switch kind {
        case let .message(msg):
            ChatMessageBubble(
                message: msg,
                isOutgoing: msg.senderDID == chatStore.currentAccountDID,
                onOpenProfile: { handle in
                    mentionProfileHandle = handle
                },
                onRetry: msg.rev == "failed" ? { Task { await retrySend(msg) } } : nil,
                onDelete: msg.senderDID == chatStore.currentAccountDID ? { Task { await deleteMessage(msg) } } : nil,
                onReact: { value in
                    Task { await chatStore.toggleReaction(convoId: conversation.id, messageId: msg.id, value: value) }
                },
                onReactionTap: { value in
                    Task { await chatStore.toggleReaction(convoId: conversation.id, messageId: msg.id, value: value) }
                }
            )
        case let .deleted(d):
            deletedMessageView(d)
        case let .system(s):
            systemMessageView(s)
        }
    }

    /// Centered "message deleted" placeholder.
    private func deletedMessageView(_: ChatDeletedMessage) -> some View {
        HStack {
            Spacer()
            Text(loc: "chat.message.deleted")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
            Spacer()
        }
    }

    /// Styled system event notification (join, leave, lock, etc.).
    private func systemMessageView(_ msg: ChatSystemMessage) -> some View {
        HStack {
            Spacer()
            Text(systemText(msg.data))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Localized text for a system message type.
    private func systemText(_ data: ChatSystemMessageData) -> String {
        switch data {
        case .addMember: loc("chat.system.added")
        case .removeMember: loc("chat.system.removed")
        case .memberJoin: loc("chat.system.joined")
        case .memberLeave: loc("chat.system.left")
        case .lockConvo: loc("chat.system.locked")
        case .unlockConvo: loc("chat.system.unlocked")
        case .lockConvoPermanently: loc("chat.system.locked_permanent")
        case .editGroup: loc("chat.system.group_updated")
        case .unknown: ""
        }
    }

    /// ID of the most recent message for marking as read.
    private var lastMessageId: String? {
        convoMessages.last.map { idFor($0) }
    }

    /// Extracts a stable ID regardless of message variant.
    private func idFor(_ kind: ChatMessageKind) -> String {
        switch kind {
        case let .message(m): m.id
        case let .deleted(d): d.id
        case let .system(s): s.id
        }
    }

    /// Retry sending a failed message.
    private func retrySend(_ msg: ChatMessage) async {
        await chatStore.resendFailedMessage(convoId: conversation.id, messageId: msg.id, text: msg.text)
    }

    /// Delete a message for self.
    private func deleteMessage(_ msg: ChatMessage) async {
        await chatStore.deleteMessage(convoId: conversation.id, messageId: msg.id)
    }
}

// MARK: - GroupInfoSheet

/// Sheet showing group information with member management, name editing, and lock controls.
private struct GroupInfoSheet: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var showAddMembers = false
    @State private var editName = false
    @State private var newName: String = ""

    let conversation: ChatConversation

    private var isLocked: Bool {
        conversation.groupInfo?.lockStatus == "locked"
    }

    private var groupMembers: [ChatMemberProfile] {
        conversation.members
    }

    var body: some View {
        NavigationStack {
            List {
                // Group name section
                Section {
                    HStack {
                        Text(loc("chat.group.name"))
                        Spacer()
                        Text(conversation.groupInfo?.name ?? loc("chat.unnamed"))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        newName = conversation.groupInfo?.name ?? ""
                        editName = true
                    }
                }

                // Lock status
                Section {
                    Toggle(isOn: Binding(
                        get: { isLocked },
                        set: { newValue in
                            Task {
                                if newValue {
                                    await chatStore.lockGroup(convoId: conversation.id)
                                } else {
                                    await chatStore.unlockGroup(convoId: conversation.id)
                                }
                            }
                        }
                    )) {
                        Label(isLocked ? loc("chat.group.locked") : loc("chat.group.unlocked"),
                              systemImage: isLocked ? "lock.fill" : "lock.open")
                    }
                } header: {
                    Text(loc("chat.group.settings"))
                }

                // Members section
                Section {
                    ForEach(groupMembers) { member in
                        HStack {
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
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(alignment: .leading) {
                                Text(member.displayName ?? member.handle)
                                    .font(.body)
                                Text("@\(member.handle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Cannot remove self
                            if member.did != chatStore.currentAccountDID, !isLocked {
                                Button {
                                    Task { await chatStore.removeGroupMember(convoId: conversation.id, memberDID: member.did) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(loc("chat.group.members"))
                        Spacer()
                        Text("\(groupMembers.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                if !isLocked {
                    Button {
                        showAddMembers = true
                    } label: {
                        Label(loc("chat.group.add_members"), systemImage: "person.badge.plus")
                    }
                }
            }
            .pageTitle(loc("chat.group.info"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddMembers) {
                AddMembersSheet(conversation: conversation)
                    .environmentObject(chatStore)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .alert(loc("chat.group.edit_name"), isPresented: $editName) {
                TextField(loc("chat.new.group_name_placeholder"), text: $newName)
                Button(loc("actions.save")) {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        Task { await chatStore.editGroupName(convoId: conversation.id, name: name) }
                    }
                }
                Button(loc("actions.cancel"), role: .cancel) {}
            }
        }
    }
}

// MARK: - AddMembersSheet

/// Sheet for adding members to an existing group conversation.
private struct AddMembersSheet: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var searchResults: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var selectedDIDs: Set<String> = []

    let conversation: ChatConversation

    /// Filter out existing members.
    private var availableResults: [BlueskyActor] {
        let existingDIDs = Set(conversation.members.map(\.did))
        return searchResults.filter { !existingDIDs.contains($0.did) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(loc("chat.new.search_placeholder"), text: $searchQuery)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { Task { await search() } }
                    }
                }

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if !availableResults.isEmpty {
                    Section {
                        ForEach(availableResults) { actor in
                            HStack {
                                ActorSearchRow(actor: actor, isSelected: selectedDIDs.contains(actor.did))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedDIDs.contains(actor.did) {
                                            selectedDIDs.remove(actor.did)
                                        } else {
                                            selectedDIDs.insert(actor.did)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .pageTitle(loc("chat.group.add_members"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("chat.group.add")) {
                        Task {
                            await chatStore.addGroupMembers(
                                convoId: conversation.id,
                                memberDIDs: Array(selectedDIDs)
                            )
                            dismiss()
                        }
                    }
                    .disabled(selectedDIDs.isEmpty)
                }
            }
        }
    }

    private func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        guard let account = accountStore.activeAccount else { return }
        do {
            let pw = accountStore.appPassword(for: account)
            let response = try await blueskyClient.searchActors(query: searchQuery, account: account, appPassword: pw)
            searchResults = response
        } catch {
            searchResults = []
        }
    }
}

// MARK: - Actor Search Row Helper

private struct ActorSearchRow: View {
    let actor: BlueskyActor
    let isSelected: Bool

    var body: some View {
        HStack {
            if let url = actor.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading) {
                Text(actor.displayName ?? actor.handle)
                    .font(.headline)
                Text("@\(actor.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.skyPrimary)
            }
        }
    }
}
