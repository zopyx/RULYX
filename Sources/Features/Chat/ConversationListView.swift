import SwiftUI

/// Lists all chat conversations for the active account with search,
/// swipe-to-mute/delete, batch edit (mute/unmute/delete), and navigation
/// to conversation detail or the new-conversation sheet.
struct ConversationListView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @State private var showNewConvo = false
    @State private var searchText = ""
    @State private var navPath: [ChatConversation] = []
    @State private var editMode: EditMode = .inactive
    @State private var selectedConvos: Set<String> = []

    // MARK: - Computed properties

    /// Conversations filtered by the search text.
    /// Searches member names, group name, last message text, and any loaded message history.
    private var filteredConvos: [ChatConversation] {
        guard !searchText.isEmpty else { return chatStore.conversations }
        let query = searchText.lowercased()
        return chatStore.conversations.filter { convo in
            // 1. Member display name / handle
            if convo.members.contains(where: { member in
                member.handle.lowercased().contains(query) ||
                    (member.displayName?.lowercased().contains(query) ?? false)
            }) {
                return true
            }
            // 2. Group name
            if let groupName = convo.groupInfo?.name.lowercased(), groupName.contains(query) {
                return true
            }
            // 3. Last message preview text
            if let lastMessage = convo.lastMessage {
                switch lastMessage {
                case let .message(msg):
                    if msg.text.lowercased().contains(query) {
                        return true
                    }
                case .deleted, .system:
                    break
                }
            }
            // 4. Loaded message history (conversations the user has opened)
            if let messages = chatStore.messages[convo.id] {
                for kind in messages {
                    switch kind {
                    case let .message(msg):
                        if msg.text.lowercased().contains(query) {
                            return true
                        }
                    case .deleted, .system:
                        break
                    }
                }
            }
            return false
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if chatStore.isLoadingConvos, chatStore.conversations.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0 ..< 8, id: \.self) { _ in
                                SkeletonRow()
                                Divider()
                            }
                        }
                    }
                } else if let chatError = chatStore.error, chatStore.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.warningOrange)
                        Text(loc: "chat.error.title")
                            .font(.headline)
                        Text(chatError.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(loc("state.error.retry")) {
                            Task { await chatStore.loadConvos() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if chatStore.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(loc: "chat.empty.title")
                            .font(.headline)
                        Text(loc: "chat.empty.desc")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List(selection: $selectedConvos) {
                        ForEach(filteredConvos) { convo in
                            NavigationLink(value: convo) {
                                ConversationRowView(conversation: convo, currentAccountDID: chatStore.currentAccountDID)
                            }
                            .swipeActions(edge: .trailing) {
                                if convo.muted {
                                    Button {
                                        Task { await chatStore.unmute(convoId: convo.id) }
                                    } label: {
                                        Label(loc("chat.unmute"), systemImage: "bell")
                                    }
                                    .tint(.orange)
                                } else {
                                    Button {
                                        Task { await chatStore.mute(convoId: convo.id) }
                                    } label: {
                                        Label(loc("chat.mute"), systemImage: "bell.slash")
                                    }
                                    .tint(.orange)
                                }
                                Button(role: .destructive) {
                                    Task { await chatStore.leave(convoId: convo.id) }
                                } label: {
                                    Label(loc("chat.delete"), systemImage: "trash")
                                }
                            }
                        }

                        if chatStore.conversations.count >= 50 {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .task { await chatStore.loadMoreConvos() }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, $editMode)
                }
            }
            .searchable(text: $searchText, prompt: loc("chat.search.placeholder"))
            .navigationDestination(for: ChatConversation.self) { convo in
                ConversationDetailView(conversation: convo)
                    .environmentObject(chatStore)
                    .environmentObject(accountStore)
            }
            .pageTitle(Text(loc: "tab.chat"))
            .toolbar {
                if !chatStore.conversations.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        if editMode.isEditing {
                            Button(loc("chat.select_all")) {
                                let allIDs = Set(filteredConvos.map(\.id))
                                if selectedConvos == allIDs {
                                    selectedConvos = []
                                } else {
                                    selectedConvos = allIDs
                                }
                            }
                            .font(.body.weight(.medium))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if editMode.isEditing {
                            Button(loc("actions.done")) {
                                withAnimation {
                                    selectedConvos = []
                                    editMode = .inactive
                                }
                            }
                            .font(.body.weight(.medium))
                        } else {
                            Button(loc("chat.edit")) {
                                withAnimation { editMode = .active }
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if editMode.isEditing, !selectedConvos.isEmpty {
                    HStack(spacing: 16) {
                        Button {
                            let toMute = filteredConvos.filter { selectedConvos.contains($0.id) && !$0.muted }
                            for convo in toMute {
                                Task { await chatStore.mute(convoId: convo.id) }
                            }
                            withAnimation { selectedConvos = [] }
                        } label: {
                            Label(loc("chat.mute"), systemImage: "bell.slash")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            let toUnmute = filteredConvos.filter { selectedConvos.contains($0.id) && $0.muted }
                            for convo in toUnmute {
                                Task { await chatStore.unmute(convoId: convo.id) }
                            }
                            withAnimation { selectedConvos = [] }
                        } label: {
                            Label(loc("chat.unmute"), systemImage: "bell")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive) {
                            for convo in filteredConvos where selectedConvos.contains(convo.id) {
                                Task { await chatStore.leave(convoId: convo.id) }
                            }
                            withAnimation { selectedConvos = [] }
                        } label: {
                            Label(loc("chat.delete"), systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !editMode.isEditing {
                    Button {
                        showNewConvo = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.skyPrimary))
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .accessibilityLabel(loc("chat.new"))
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showNewConvo) {
                NewConversationSheet { convo in
                    showNewConvo = false
                    if let convo {
                        workspaceStore.pendingChatConversation = convo
                    }
                    Task { await chatStore.loadConvos() }
                }
                .environmentObject(accountStore)
                .environmentObject(chatStore)
            }
            .alert(loc("chat.error.title"), isPresented: Binding(
                get: { chatStore.error != nil },
                set: { isPresented in
                    if !isPresented {
                        chatStore.error = nil
                    }
                }
            )) {
                Button(loc("actions.ok")) {
                    chatStore.error = nil
                }
            } message: {
                if let error = chatStore.error {
                    Text(error.localizedDescription)
                }
            }
            .refreshable {
                await chatStore.loadConvos()
            }
            .task {
                openPendingConversationIfNeeded()
                guard chatStore.conversations.isEmpty, !chatStore.isLoadingConvos, accountStore.activeAccount != nil else { return }
                let pw = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
                await chatStore.rebuildConversations(for: accountStore.activeAccount, appPassword: pw)
            }
            .onAppear {
                openPendingConversationIfNeeded()
                chatStore.setChatViewVisible(true, token: "conversationList")
            }
            .onDisappear {
                chatStore.setChatViewVisible(false, token: "conversationList")
            }
            .onChange(of: accountStore.activeAccountID) { _, _ in
                navPath = []
                selectedConvos = []
                editMode = .inactive
                searchText = ""
            }
            .onChange(of: workspaceStore.pendingChatConversation) { _, _ in
                openPendingConversationIfNeeded()
            }
            .onChange(of: workspaceStore.selectedTab) { _, _ in
                openPendingConversationIfNeeded()
            }
        }
    }

    private func openPendingConversationIfNeeded() {
        guard workspaceStore.selectedTab == .chat else { return }

        if let conversation = workspaceStore.pendingChatConversation {
            navPath = [conversation]
            workspaceStore.pendingChatConversation = nil
            workspaceStore.pendingChatConversationID = nil
            return
        }

        guard let conversationID = workspaceStore.pendingChatConversationID,
              let conversation = chatStore.conversations.first(where: { $0.id == conversationID })
        else { return }

        navPath = [conversation]
        workspaceStore.pendingChatConversationID = nil
    }

    struct ConversationRowView: View {
        let conversation: ChatConversation
        let currentAccountDID: String?

        private var partnerMembers: [ChatMemberProfile] {
            guard let did = currentAccountDID else { return conversation.members }
            return conversation.members.filter { $0.did != did }
        }

        private var displayName: String {
            if let groupInfo = conversation.groupInfo, !groupInfo.name.isEmpty {
                return groupInfo.name
            }
            let others = partnerMembers
            if others.count == 1 {
                return others[0].displayName ?? others[0].handle
            }
            let names = others.prefix(3).map { $0.displayName ?? $0.handle }
            if others.count > 3 {
                return (names + ["+\(others.count - 3)"]).joined(separator: ", ")
            }
            if others.isEmpty {
                return loc("chat.unknown")
            }
            return names.joined(separator: ", ")
        }

        private var avatarURL: URL? {
            if conversation.kind == .group {
                return nil
            }
            return partnerMembers.first?.avatarURL
        }

        private var lastMessagePreview: String {
            guard let last = conversation.lastMessage else { return "" }
            switch last {
            case let .message(m): return m.text
            case .deleted: return loc("chat.message.deleted")
            case let .system(s): return systemMessageText(s)
            }
        }

        private var lastMessageTime: String {
            guard let last = conversation.lastMessage else { return "" }
            let date: Date = switch last {
            case let .message(m): m.sentAt
            case let .deleted(d): d.sentAt
            case let .system(s): s.sentAt
            }
            return formatRelativeTime(date)
        }

        var body: some View {
            HStack(spacing: 12) {
                if let url = avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "person.circle.fill")
                                .resizable()
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                } else {
                    Image(systemName: conversation.kind == .group ? "person.3.fill" : "person.circle.fill")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(lastMessageTime)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.skyPrimary)
                            .clipShape(Capsule())
                    }

                    if conversation.muted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        private func systemMessageText(_ msg: ChatSystemMessage) -> String {
            switch msg.data {
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

        private func formatRelativeTime(_ date: Date) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.dateTimeStyle = .numeric
            return formatter.localizedString(for: date, relativeTo: .now)
        }
    }
}
