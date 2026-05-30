import SwiftUI

// MARK: - Tab Bar Item Data

private struct TabBarItem: Identifiable {
    let tab: WorkspaceTab
    let icon: String
    let label: String

    var id: WorkspaceTab {
        tab
    }
}

// MARK: - Root View

/// The main tab-based view hierarchy with a custom bottom bar that includes
/// the account switcher as an integrated tab item.
struct RootView: View {
    // MARK: - Properties

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var clearskyHeartbeat: ClearskyHeartbeatService

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// UserDefaults key `"hasSeenOnboarding"`: whether the first-launch onboarding
    /// has been shown. Suppresses the onboarding sheet on subsequent launches.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    /// UserDefaults key `"appearanceMode"`: the user's preferred color scheme.
    /// Values: `"light"`, `"dark"`, or `"system"` (default).
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    /// Converts the `appearanceMode` string to a SwiftUI `ColorScheme?`.
    /// Returns `.light`, `.dark`, or `nil` for system-following mode.
    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private let tabBarItems: [TabBarItem] = [
        TabBarItem(tab: .moderation, icon: "checklist.checked", label: "tab.moderation"),
        TabBarItem(tab: .timeline, icon: "clock.arrow.circlepath", label: "tab.timeline"),
        TabBarItem(tab: .notifications, icon: "bell", label: "tab.notifications"),
        TabBarItem(tab: .chat, icon: "bubble.left.and.bubble.right", label: "tab.chat"),
        TabBarItem(tab: .info, icon: "sparkles.rectangle.stack", label: "tab.info"),
        TabBarItem(tab: .settings, icon: "gearshape", label: "tab.settings"),
    ]

    private struct TabBarItemView: View {
        let item: TabBarItem
        let isSelected: Bool
        let localizationManager: LocalizationManager
        let tint: Color

        var body: some View {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                Text(localizationManager.localized(item.label))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : .secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    private func switchAccount(_ account: AppAccount) {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        Task {
            await accountStore.switchAccount(to: account, using: blueskyClient)
            workspaceStore.returnToModerationRoot()
            generator.selectionChanged()
        }
    }

    // MARK: - Body

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
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

    private var compactBody: some View {
        let tint: Color = clearskyHeartbeat.isClearskyAvailable ? .skyPrimary : Color.red.opacity(0.7)

        return VStack(spacing: 0) {
            // MARK: Clearsky Outage Banner

            if !clearskyHeartbeat.isClearskyAvailable {
                ClearskyBanner()
                    .environmentObject(localizationManager)
            }

            // MARK: Tab Content

            ZStack {
                switch workspaceStore.selectedTab {
                case .moderation:
                    ModerationSplitView()
                case .timeline:
                    TimelineTab()
                case .notifications:
                    NotificationTab()
                case .chat:
                    ChatTab()
                case .info:
                    InfoView()
                case .settings:
                    SettingsView()
                case .account:
                    AccountTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: Custom Bottom Bar

            HStack(spacing: 0) {
                ForEach(tabBarItems) { item in
                    Button {
                        workspaceStore.selectedTab = item.tab
                    } label: {
                        TabBarItemView(
                            item: item,
                            isSelected: workspaceStore.selectedTab == item.tab,
                            localizationManager: localizationManager,
                            tint: tint
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Account switcher — inline in the tab bar
                AccountTabBarButton(
                    accountStore: accountStore,
                    workspaceStore: workspaceStore,
                    localizationManager: localizationManager,
                    tint: tint,
                    onSwitch: switchAccount
                )
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, safeAreaBottomInset + 4)
            .background(.bar)
            .preferredColorScheme(preferredScheme)
            .environment(\.locale, localizationManager.locale)
            .environment(\.layoutDirection, localizationManager.layoutDirection)

            // MARK: Onboarding Sheet

            // On first-ever launch, presents an onboarding sheet that introduces
            // the app's tabs and core features. Dismissing it sets `hasSeenOnboarding`
            // to true, preventing future showings.
            .sheet(isPresented: .init(get: { !hasSeenOnboarding }, set: { hasSeenOnboarding = !$0 })) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            // MARK: Header

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

                            // MARK: Feature Rows

                            VStack(alignment: .leading, spacing: 16) {
                                OnboardingRow(icon: "checklist.checked", color: .skyPrimary, title: localizationManager.localized("tab.moderation"), description: localizationManager.localized("onboarding.moderation.desc"))
                                OnboardingRow(icon: "person.circle", color: .skyPrimary, title: localizationManager.localized("tab.accounts"), description: localizationManager.localized("onboarding.accounts.desc"))
                                OnboardingRow(icon: "gearshape", color: .orange, title: localizationManager.localized("tab.settings"), description: localizationManager.localized("onboarding.settings.desc"))
                                OnboardingRow(icon: "sparkles.rectangle.stack", color: .purple, title: localizationManager.localized("tab.info"), description: localizationManager.localized("onboarding.info.desc"))
                            }

                            // MARK: Get Started Button

                            Button {
                                hasSeenOnboarding = true
                            } label: {
                                Text(verbatim: localizationManager.localized("onboarding.get_started"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.borderedProminent)
                            // Custom glass-material prominent button style used consistently
                            // throughout the app for primary action buttons.
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
        }
    }

    // MARK: - Private Helpers

    /// The bottom safe area inset for the custom tab bar.
    private var safeAreaBottomInset: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first
        {
            window.safeAreaInsets.bottom
        }
        return 0
    }
}

// MARK: - Account Tab Bar Button

/// A standalone view for the account switcher button in the custom tab bar.
/// Observed as a separate struct to ensure the label re-renders on account changes.
private struct AccountTabBarButton: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject var workspaceStore: ModerationWorkspaceStore
    let localizationManager: LocalizationManager
    let tint: Color
    let onSwitch: (AppAccount) -> Void

    var body: some View {
        Menu {
            if let active = accountStore.activeAccount {
                ForEach(accountStore.accounts) { acct in
                    Button {
                        onSwitch(acct)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.accountTint(acct.tintColor))
                                .frame(width: 10, height: 10)
                            AccountAvatarView(account: acct, tint: .accountTint(acct.tintColor), size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(acct.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(acct.handle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if acct.id == accountStore.activeAccountID {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(tint)
                            }
                            if accountStore.isDeactivated(acct) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .disabled(acct.id == accountStore.activeAccountID || accountStore.isDeactivated(acct))
                }
                Divider()
            }
            Button {
                workspaceStore.selectedTab = .account
            } label: {
                Label(loc("account.switcher.manage"), systemImage: "slider.horizontal.3")
            }
        } label: {
            VStack(spacing: 4) {
                if let account = accountStore.activeAccount {
                    AccountAvatarView(account: account, tint: .accountTint(account.tintColor), size: 24)
                        .overlay {
                            Circle()
                                .stroke(tint.opacity(workspaceStore.selectedTab == .account ? 1 : 0.3), lineWidth: 2)
                        }
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                }
                Text(localizationManager.localized("tab.accounts"))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(workspaceStore.selectedTab == .account ? tint : .secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel(loc("account.switcher.label"))
    }
}

/// Renders an account avatar (async image or initial-letter placeholder).
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
