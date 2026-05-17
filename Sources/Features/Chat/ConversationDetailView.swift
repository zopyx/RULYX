import SwiftUI

struct ConversationDetailView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @State private var messageText = ""
    @State private var showProfile = false
    @State private var showScrollToBottom = false
    @FocusState private var isFocused: Bool

    let conversation: ChatConversation

    private var convoMessages: [ChatMessageKind] {
        chatStore.messages[conversation.id] ?? []
    }

    private var otherMember: ChatMemberProfile? {
        conversation.members.first { $0.did != chatStore.currentAccountDID }
    }

    private var displayName: String {
        if let groupInfo = conversation.groupInfo, !groupInfo.name.isEmpty {
            return groupInfo.name
        }
        if let member = otherMember {
            return member.displayName ?? member.handle
        }
        return conversation.members.first?.handle ?? loc("chat.unknown")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = chatStore.error, convoMessages.isEmpty {
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
                .frame(maxHeight: .infinity)
            } else {
                scrollView
            }

            Divider()

            sendBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chatStore.setVisibleConversation(conversation.id)
            await chatStore.loadMessages(convoId: conversation.id)
            await chatStore.markRead(convoId: conversation.id, messageId: lastMessageId)
        }
        .onDisappear {
            if chatStore.currentAccountDID != nil {
                chatStore.setVisibleConversation(nil)
            }
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
                        ToolbarItem(placement: .confirmationAction) {
                            Button(loc("actions.done")) {
                                showProfile = false
                            }
                        }
                    }
                }
                .interactiveDismissDisabled(false)
            }
        }
    }

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
        .background(.bar)
    }

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

    @ViewBuilder
    private func messageView(for kind: ChatMessageKind) -> some View {
        switch kind {
        case let .message(msg):
            ChatMessageBubble(message: msg, isOutgoing: msg.senderDID == chatStore.currentAccountDID)
        case let .deleted(d):
            deletedMessageView(d)
        case let .system(s):
            systemMessageView(s)
        }
    }

    private func deletedMessageView(_: ChatDeletedMessage) -> some View {
        HStack {
            Spacer()
            Text(loc("chat.message.deleted"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
            Spacer()
        }
    }

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

    private var lastMessageId: String? {
        convoMessages.last.map { idFor($0) }
    }

    private func idFor(_ kind: ChatMessageKind) -> String {
        switch kind {
        case let .message(m): m.id
        case let .deleted(d): d.id
        case let .system(s): s.id
        }
    }
}

