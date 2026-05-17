import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @State private var showNewConvo = false
    @State private var searchText = ""
    @State private var navPath: [ChatConversation] = []
    @State private var editMode: EditMode = .inactive
    @State private var selectedConvos: Set<String> = []

    private var filteredConvos: [ChatConversation] {
        guard !searchText.isEmpty else { return chatStore.conversations }
        return chatStore.conversations.filter { convo in
            convo.members.contains { member in
                member.handle.localizedCaseInsensitiveContains(searchText) ||
                    (member.displayName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if chatStore.isLoadingConvos, chatStore.conversations.isEmpty {
                    LoadingPanel(message: loc("chat.loading"))
                } else if let chatError = chatStore.error, chatStore.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text(loc("chat.error.title"))
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
                    .padding()
                } else if chatStore.conversations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text(loc("chat.empty.title"))
                            .font(.headline)
                        Text(loc("chat.empty.desc"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
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
                    .searchable(text: $searchText, prompt: loc("chat.search.placeholder"))
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationDestination(for: ChatConversation.self) { convo in
                ConversationDetailView(conversation: convo)
                    .environmentObject(chatStore)
                    .environmentObject(accountStore)
            }
            .navigationTitle(loc("tab.chat"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await chatStore.loadConvos() }
                    } label: {
                        if chatStore.isLoadingConvos {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel(loc("chat.reload"))
                    .disabled(chatStore.isLoadingConvos)
                }

                ToolbarItem(placement: .primaryAction) {
                    if editMode.isEditing {
                        Button(loc("chat.select_all")) {
                            let allIDs = Set(filteredConvos.map(\.id))
                            if selectedConvos == allIDs {
                                selectedConvos = []
                            } else {
                                selectedConvos = allIDs
                            }
                        }
                    } else {
                        Button {
                            showNewConvo = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel(loc("chat.new"))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? loc("actions.done") : loc("chat.edit")) {
                        withAnimation {
                            if editMode.isEditing {
                                selectedConvos = []
                            }
                            editMode = editMode.isEditing ? .inactive : .active
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
                guard chatStore.conversations.isEmpty, accountStore.activeAccount != nil else { return }
                let pw = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
                chatStore.setAccount(accountStore.activeAccount, appPassword: pw)
                await chatStore.loadConvos()
                openPendingConversationIfNeeded()
            }
            .onAppear {
                openPendingConversationIfNeeded()
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
            return names.joined(separator: ", ")
        }

        private var avatarURL: URL? {
            if conversation.kind == .group { return nil }
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
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(lastMessageTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

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
                            .foregroundStyle(.tertiary)
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
            let diff = Date().timeIntervalSince(date)
            if diff < 60 { return loc("time.just_now") }
            if diff < 3600 { return "\(Int(diff / 60))m" }
            if diff < 86400 { return "\(Int(diff / 3600))h" }
            if diff < 604_800 { return "\(Int(diff / 86400))d" }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
