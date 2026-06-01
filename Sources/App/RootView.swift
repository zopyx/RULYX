import SwiftUI

struct RootView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var clearskyHeartbeat: ClearskyHeartbeatService

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    @State private var showAccountSheet = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !clearskyHeartbeat.isClearskyAvailable {
                    ClearskyBanner()
                        .environmentObject(localizationManager)
                }
                if let statusMessage = chatStore.statusMessage {
                    ChatStatusBanner(message: statusMessage)
                }

                tabContent
            }
            .preferredColorScheme(preferredScheme)
            .environment(\.locale, localizationManager.locale)
            .environment(\.layoutDirection, localizationManager.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    tabPicker
                }
                ToolbarItem(placement: .topBarTrailing) {
                    accountButton
                }
            }
            .sheet(isPresented: $showAccountSheet) {
                AccountSwitcherSheet(isPresented: $showAccountSheet)
            }
            .sheet(isPresented: .init(get: { !hasSeenOnboarding }, set: { hasSeenOnboarding = !$0 })) {
                onboardingContent
            }
        }
    }

    private var tabPicker: some View {
        Menu {
            ForEach(TabItem.allCases) { item in
                Button {
                    workspaceStore.selectedTab = item.tab
                } label: {
                    Label(localizationManager.localized(item.labelKey), systemImage: item.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedTabItem.icon)
                Text(localizationManager.localized(selectedTabItem.labelKey))
                    .font(.headline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch workspaceStore.selectedTab {
        case .moderation: ModerationSplitView()
        case .timeline: TimelineTab()
        case .notifications: NotificationTab()
        case .chat: ChatTab()
        case .info: InfoView()
        case .settings: SettingsView()
        case .account: AccountTabView()
        }
    }

    private var accountButton: some View {
        Button {
            showAccountSheet = true
        } label: {
            if let account = accountStore.activeAccount {
                HStack(spacing: 6) {
                    AvatarView(account: account, size: 24)
                    Text(account.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
            }
        }
    }

    private var onboardingContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "checklist.checked")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.skyPrimary)
                        Image("RulyxLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 36)
                        Text(verbatim: localizationManager.localized("onboarding.title"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(verbatim: localizationManager.localized("onboarding.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 16) {
                        OnboardingRow(icon: "checklist.checked", color: .skyPrimary, title: localizationManager.localized("tab.moderation"), description: localizationManager.localized("onboarding.moderation.desc"))
                        OnboardingRow(icon: "person.circle", color: .skyPrimary, title: localizationManager.localized("tab.accounts"), description: localizationManager.localized("onboarding.accounts.desc"))
                        OnboardingRow(icon: "gearshape", color: .orange, title: localizationManager.localized("tab.settings"), description: localizationManager.localized("onboarding.settings.desc"))
                        OnboardingRow(icon: "sparkles.rectangle.stack", color: .purple, title: localizationManager.localized("tab.info"), description: localizationManager.localized("onboarding.info.desc"))
                    }

                    Button {
                        hasSeenOnboarding = true
                    } label: {
                        Text(verbatim: localizationManager.localized("onboarding.get_started"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .glassProminentButton()
                    .padding(.horizontal)
                }
                .padding()
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizationManager.localized("onboarding.close")) {
                        hasSeenOnboarding = true
                    }
                    .accessibilityLabel(loc: "onboarding.close.label")
                }
            }
        }
    }

    private var selectedTabItem: TabItem {
        TabItem.allCases.first { $0.tab == workspaceStore.selectedTab } ?? .moderation
    }
}

// MARK: - Tab Item

private enum TabItem: String, Identifiable, CaseIterable {
    case moderation
    case timeline
    case notifications
    case chat
    case info
    case settings

    var id: String {
        rawValue
    }

    var tab: WorkspaceTab {
        switch self {
        case .moderation: .moderation
        case .timeline: .timeline
        case .notifications: .notifications
        case .chat: .chat
        case .info: .info
        case .settings: .settings
        }
    }

    var icon: String {
        switch self {
        case .moderation: "checklist.checked"
        case .timeline: "clock.arrow.circlepath"
        case .notifications: "bell"
        case .chat: "bubble.left.and.bubble.right"
        case .info: "sparkles.rectangle.stack"
        case .settings: "gearshape"
        }
    }

    var labelKey: String {
        switch self {
        case .moderation: "tab.moderation"
        case .timeline: "tab.timeline"
        case .notifications: "tab.notifications"
        case .chat: "tab.chat"
        case .info: "tab.info"
        case .settings: "tab.settings"
        }
    }
}

// MARK: - Avatar View

private struct AvatarView: View {
    let account: AppAccount
    let size: CGFloat

    private var tint: Color {
        .accountTint(account.tintColor)
    }

    var body: some View {
        if let avatarURL = account.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(tint)
                    .overlay {
                        Text(account.displayName.prefix(1).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        } else {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
                .overlay {
                    Text(account.displayName.prefix(1).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
    }
}
