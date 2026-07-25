import SwiftUI

// MARK: - Root View

/// Main iPhone tab navigation using native TabView.
/// Each tab has its own NavigationStack for state preservation across switches.
struct RootView: View {
    // MARK: - Properties

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var clearskyHeartbeat: ClearskyHeartbeatService

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("performanceOverlayEnabled") private var performanceOverlayEnabled = false

    @State private var showAccountSwitcher = false
    @State private var overlayVisible = false
    @State private var showAddAccountFromOnboarding = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    // MARK: - Body

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootView()
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
                .environmentObject(mutedWordsStore)
                .environmentObject(analyticsStore)
                .environmentObject(chatStore)
                .environmentObject(clearskyHeartbeat)
        } else {
            compactBody
        }
    }

    // MARK: - Compact (iPhone) Body

    private var compactBody: some View {
        let tint: Color = clearskyHeartbeat.isClearskyAvailable
            ? .skyPrimary : Color.red.opacity(0.7)

        return ZStack {
            TabView(selection: Binding(
                get: { workspaceStore.selectedTab },
                set: { newTab in
                    if workspaceStore.selectedTab == .moderation, newTab == .moderation {
                        workspaceStore.returnToModerationRoot()
                    }
                    workspaceStore.selectedTab = newTab
                }
            )) {
                NavigationStack {
                    ModerationSplitView()
                        .navigationTitle(loc("tab.moderation"))
                }
                .tabItem {
                    Label(loc("tab.moderation"), systemImage: "checklist.checked")
                }
                .tag(WorkspaceTab.moderation)

                NavigationStack {
                    TimelineTab()
                        .navigationTitle(loc("tab.timeline"))
                }
                .tabItem {
                    Label(loc("tab.timeline"), systemImage: "clock.arrow.circlepath")
                }
                .tag(WorkspaceTab.timeline)

                NavigationStack {
                    NotificationTab()
                        .navigationTitle(loc("tab.notifications"))
                }
                .tabItem {
                    Label(loc("tab.notifications"), systemImage: "bell")
                }
                .tag(WorkspaceTab.notifications)

                NavigationStack {
                    ChatTab()
                        .navigationTitle(loc("tab.chat"))
                }
                .tabItem {
                    Label(loc("tab.chat"), systemImage: "bubble.left.and.bubble.right")
                }
                .tag(WorkspaceTab.chat)

                NavigationStack {
                    SettingsView()
                        .navigationTitle(loc("tab.settings"))
                }
                .tabItem {
                    Label(loc("tab.settings"), systemImage: "gearshape")
                }
                .tag(WorkspaceTab.settings)

                NavigationStack {
                    InfoView()
                        .navigationTitle(loc("tab.info"))
                }
                .tabItem {
                    Label(loc("tab.info"), systemImage: "sparkles.rectangle.stack")
                }
                .tag(WorkspaceTab.info)

                NavigationStack {
                    AccountTabView()
                        .navigationTitle(loc("tab.accounts"))
                }
                .tabItem {
                    Label(loc("tab.accounts"), systemImage: "person.circle")
                }
                .tag(WorkspaceTab.account)
            }
            .tint(tint)
            .preferredColorScheme(preferredScheme)
            .environment(\.locale, localizationManager.locale)
            .environment(\.layoutDirection, localizationManager.layoutDirection)

            // Banner overlay
            VStack(spacing: 0) {
                if !clearskyHeartbeat.isClearskyAvailable {
                    ClearskyBanner()
                }
                if let statusMessage = chatStore.statusMessage {
                    ChatStatusBanner(message: statusMessage)
                }
                Spacer()
            }

            // Performance overlay
            if overlayVisible || performanceOverlayEnabled {
                PerformanceMonitorOverlay()
                    .environmentObject(HTTPRequestDebugStore.shared)
            }
        }
        .sheet(isPresented: $showAccountSwitcher) {
            AccountSwitcherTabSheet(
                accountStore: accountStore,
                workspaceStore: workspaceStore,
                blueskyClient: container.blueskyClient,
                onSwitch: switchAccount
            )
        }
        .sheet(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { hasSeenOnboarding = !$0 }
        )) {
            onboardingContent
        }
        .sheet(isPresented: $showAddAccountFromOnboarding) {
            AddAccountView()
                .environmentObject(accountStore)
                .environmentObject(container)
                .environmentObject(localizationManager)
        }
        .highPriorityGesture(threeFingerGesture)
    }

    // MARK: - Account Switching

    private func switchAccount(_ account: AppAccount) {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        Task {
            await accountStore.switchAccount(to: account, using: container.blueskyClient)
            workspaceStore.returnToModerationRoot()
            generator.selectionChanged()
        }
    }

    // MARK: - Gestures

    private var threeFingerGesture: some Gesture {
        if UIAccessibility.isVoiceOverRunning {
            return TapGesture().onEnded {}
        }
        return TapGesture(count: 3)
            .onEnded { overlayVisible.toggle() }
    }

    // MARK: - Onboarding

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
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 16) {
                        OnboardingRow(icon: "checklist.checked", color: .skyPrimary, title: localizationManager.localized("tab.moderation"), description: localizationManager.localized("onboarding.moderation.desc"))
                        OnboardingRow(icon: "clock.arrow.circlepath", color: .skyPrimary, title: localizationManager.localized("tab.timeline"), description: localizationManager.localized("onboarding.timeline.desc"))
                        OnboardingRow(icon: "person.circle", color: .skyPrimary, title: localizationManager.localized("tab.accounts"), description: localizationManager.localized("onboarding.accounts.desc"))
                        OnboardingRow(icon: "gearshape", color: .orange, title: localizationManager.localized("tab.settings"), description: localizationManager.localized("onboarding.settings.desc"))
                    }

                    Button {
                        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                            showAddAccountFromOnboarding = true
                        }
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
                    .accessibilityIdentifier("Close")
                }
            }
        }
    }
}

// MARK: - Account Switcher Row

private struct AccountSwitcherRow: View {
    let account: AppAccount
    let isActive: Bool
    let isDeactivated: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AccountAvatarView(account: account, tint: .accountTint(account.tintColor), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(account.handle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Text(loc("account.active"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            if #available(iOS 26, *) {
                                Color.clear.glassEffect(.regular.tint(.skyPrimary), in: .rect(cornerRadius: .infinity))
                            } else {
                                Color.clear.background(Color.skyPrimary.opacity(0.14), in: Capsule())
                            }
                        }
                }
                if isDeactivated {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.warningOrange)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDeactivated)
    }
}

// MARK: - Account Switcher Sheet

private struct AccountSwitcherTabSheet: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var workspaceStore: ModerationWorkspaceStore
    let blueskyClient: LiveBlueskyClient
    let onSwitch: (AppAccount) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(accountStore.accounts) { acct in
                    AccountSwitcherRow(
                        account: acct,
                        isActive: acct.id == accountStore.activeAccountID,
                        isDeactivated: accountStore.isDeactivated(acct),
                        action: {
                            onSwitch(acct)
                            dismiss()
                        }
                    )
                }

                Button {
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        workspaceStore.selectedTab = .account
                    }
                } label: {
                    Label(loc("account.switcher.manage"), systemImage: "slider.horizontal.3")
                        .foregroundStyle(.primary)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListHeaderHeight, 0)
            .pageTitle(loc("account.switcher.title"))
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemBackground))
    }
}

// MARK: - Account Avatar

private struct AccountAvatarView: View {
    let account: AppAccount
    let tint: Color
    let size: CGFloat

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

// MARK: - Preview

#Preview {
    RootView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
}
