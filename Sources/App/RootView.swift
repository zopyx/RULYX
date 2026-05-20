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
    @AppStorage("showBetaFeatures") private var showBetaFeatures = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !clearskyHeartbeat.isClearskyAvailable {
                ClearskyBanner()
                    .environmentObject(localizationManager)
            }
            TabView(selection: $workspaceStore.selectedTab) {
                ModerationSplitView()
                    .tag(WorkspaceTab.moderation)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.moderation"))
                        } icon: {
                            Image(systemName: "checklist.checked")
                        }
                    }

                if showBetaFeatures {
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
                }

                InfoView()
                    .tag(WorkspaceTab.info)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.info"))
                        } icon: {
                            Image(systemName: "sparkles.rectangle.stack")
                        }
                    }

                SettingsView()
                    .tag(WorkspaceTab.settings)
                    .tabItem {
                        Label {
                            Text(localizationManager.localized("tab.settings"))
                        } icon: {
                            Image(systemName: "gearshape")
                        }
                    }

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
            .tint(clearskyHeartbeat.isClearskyAvailable ? .skyPrimary : Color.red.opacity(0.7))
            .preferredColorScheme(preferredScheme)
            .environment(\.locale, localizationManager.locale)
            .environment(\.layoutDirection, localizationManager.layoutDirection)
            .onChange(of: showBetaFeatures) { _, newValue in
                if !newValue, workspaceStore.selectedTab == .timeline || workspaceStore.selectedTab == .notifications || workspaceStore.selectedTab == .chat {
                    workspaceStore.selectedTab = .moderation
                }
            }
            .sheet(isPresented: .init(get: { !hasSeenOnboarding }, set: { hasSeenOnboarding = !$0 })) {
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
        }
    }

    private func orderedTabs(showBeta: Bool) -> [WorkspaceTab] {
        if showBeta {
            [.moderation, .timeline, .notifications, .chat, .info, .settings, .account]
        } else {
            [.moderation, .info, .settings, .account]
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
        .environmentObject(ModerationWorkspaceStore(preview: true))
}
