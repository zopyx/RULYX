import SwiftUI

// MARK: - Root View

/// The main tab-based view hierarchy. Shows the `TabView` with all tabs,
/// conditionally including beta features (Timeline, Notifications, Chat).
///
/// ## Tab Structure
/// - **All tabs always visible**: Moderation, Timeline, Notifications, Chat, Info, Settings, Accounts
/// - iOS tab bar supports at most 5 visible tabs before showing "More". The 7 total tabs
///   are split across two screenshot test methods (`testCaptureCoreTabs` / `testCaptureBetaTabs`).
///
/// ## Account Switching
/// Account switching is handled at the `RULYXApp` level via `.task(id: activeAccountID)`.
/// This view reads `activeAccount` from the environment but does not manage it directly.
/// The `TabView` selection is persisted via `workspaceStore.selectedTab`.
///
/// ## Onboarding Flow
/// On first launch (`hasSeenOnboarding` is false), a full-screen onboarding sheet
/// is presented explaining the app's core features and tabs. Dismissing it
/// permanently sets `hasSeenOnboarding = true`.
///
/// ## Tab Availability
/// All tabs are always visible; no beta gating.
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
        VStack(spacing: 0) {
            // MARK: Clearsky Outage Banner

            // Warning banner at the top when Clearsky API is unreachable.
            if !clearskyHeartbeat.isClearskyAvailable {
                ClearskyBanner()
                    .environmentObject(localizationManager)
            }

            // MARK: Tab Bar

            TabView(selection: $workspaceStore.selectedTab) {
                // MARK: Moderation Tab (always visible)

                ModerationSplitView()
                    .tag(WorkspaceTab.moderation)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.moderation"))
                        } icon: {
                            Image(systemName: "checklist.checked")
                        }
                    }

                TimelineTab()
                    .tag(WorkspaceTab.timeline)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.timeline"))
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }

                NotificationTab()
                    .tag(WorkspaceTab.notifications)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.notifications"))
                        } icon: {
                            Image(systemName: "bell")
                        }
                    }

                ChatTab()
                    .tag(WorkspaceTab.chat)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.chat"))
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                    }

                // MARK: Info Tab

                InfoView()
                    .tag(WorkspaceTab.info)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.info"))
                        } icon: {
                            Image(systemName: "sparkles.rectangle.stack")
                        }
                    }

                // MARK: Settings Tab

                SettingsView()
                    .tag(WorkspaceTab.settings)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.settings"))
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }

                // MARK: Accounts Tab

                AccountTabView()
                    .tag(WorkspaceTab.account)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.accounts"))
                        } icon: {
                            Image(systemName: "person.circle")
                        }
                    }
            }
            // Tint changes to red when Clearsky is unavailable, providing a
            // visual cue that Clearsky-dependent features will not work.
            .tint(clearskyHeartbeat.isClearskyAvailable ? .skyPrimary : Color.red.opacity(0.7))
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

    /// Returns the ordered list of tabs for the given beta state. Currently
    /// unused by `TabView` (tabs are hardcoded above) but available for
    /// future dynamic tab ordering or testing.
    private func orderedTabs(showBeta: Bool) -> [WorkspaceTab] {
        if showBeta {
            [.moderation, .timeline, .notifications, .chat, .info, .settings, .account]
        } else {
            [.moderation, .info, .settings, .account]
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
