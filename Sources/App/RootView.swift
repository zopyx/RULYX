import SwiftUI

struct RootView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore
    @EnvironmentObject private var chatStore: ChatStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("showBetaFeatures") private var showBetaFeatures = false

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
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
        .tint(.skyPrimary)
        .preferredColorScheme(preferredScheme)
        .gesture(
            DragGesture()
                .onEnded { value in
                    let threshold: CGFloat = 60
                    guard abs(value.translation.width) > threshold, abs(value.translation.height) < threshold * 2 else { return }
                    let tabs = orderedTabs(showBeta: showBetaFeatures)
                    guard let currentIndex = tabs.firstIndex(of: workspaceStore.selectedTab) else { return }
                    if value.translation.width < -threshold {
                        let nextIndex = currentIndex + 1
                        if nextIndex < tabs.count {
                            workspaceStore.selectedTab = tabs[nextIndex]
                        }
                    } else if value.translation.width > threshold {
                        let prevIndex = currentIndex - 1
                        if prevIndex >= 0 {
                            workspaceStore.selectedTab = tabs[prevIndex]
                        }
                    }
                }
        )
        .onChange(of: showBetaFeatures) { _, newValue in
            if !newValue, workspaceStore.selectedTab == .timeline || workspaceStore.selectedTab == .chat {
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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localizationManager.localized("onboarding.close")) {
                            hasSeenOnboarding = true
                        }
                        .accessibilityLabel(loc("onboarding.close.label"))
                    }
                }
            }
        }
    }

    private func orderedTabs(showBeta: Bool) -> [WorkspaceTab] {
        if showBeta {
            [.moderation, .timeline, .chat, .info, .settings, .account]
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
