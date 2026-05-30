import SwiftUI

struct iPadRootView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var mutedWordsStore: MutedWordsStore
    @EnvironmentObject private var analyticsStore: AnalyticsStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var clearskyHeartbeat: ClearskyHeartbeatService
    @EnvironmentObject private var internalListStore: InternalListStore

    @StateObject private var navState = iPadNavigationState()
    @StateObject private var keyboardShortcuts = iPadKeyboardShortcuts.shared

    @State private var showCommandPalette = false

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
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

            NavigationSplitView(columnVisibility: $navState.columnVisibility) {
                iPadSidebar(selection: $navState.sidebarSelection)
            } content: {
                contentColumn(for: navState.sidebarSelection)
            } detail: {
                detailColumn
            }
            .preferredColorScheme(preferredScheme)
            .environment(\.locale, localizationManager.locale)
            .environment(\.layoutDirection, localizationManager.layoutDirection)
            .tint(clearskyHeartbeat.isClearskyAvailable ? .skyPrimary : Color.red.opacity(0.7))
            .environmentObject(navState)
        }
        .sheet(isPresented: .init(get: { !hasSeenOnboarding }, set: { hasSeenOnboarding = !$0 })) {
            onboardingSheet
        }
        .overlay {
            if showCommandPalette {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showCommandPalette = false }
                iPadCommandPalette(
                    isPresented: $showCommandPalette,
                    onNavigate: { item in
                        navState.sidebarSelection = item
                    }
                )
                .environmentObject(localizationManager)
                .transition(AnyTransition.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35), value: showCommandPalette)
        .background {
            Button("") { showCommandPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .iPadNavigateTo)) { notification in
            if let item = notification.object as? SidebarItem {
                navState.sidebarSelection = item
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let did = navState.selectedProfileDID {
            iPadProfileInspector(did: did)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
                .environmentObject(navState)
                .environmentObject(internalListStore)
        } else if let list = navState.selectedList, navState.sidebarSelection == .allLists {
            iPadListDetailView(list: list)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
                .environmentObject(navState)
        } else {
            iPadEmptyDetailPlaceholder()
                .environmentObject(localizationManager)
        }
    }

    @ViewBuilder
    private func contentColumn(for item: SidebarItem?) -> some View {
        switch item {
        case .allLists:
            iPadListsView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
                .environmentObject(internalListStore)
                .environmentObject(navState)
        case .templates:
            ListTemplatesView(onListCreated: { _ in })
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
        case .rules:
            ModerationRulesView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
        case .dashboard:
            DashboardView()
                .environmentObject(accountStore)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
        case .relationships:
            RelationshipsView(mode: .followers, initialCount: nil)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
                .environmentObject(workspaceStore)
        case .customSearch:
            CustomSearchView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
        case .mentionsSearch:
            iPadMentionsSearchWrapper()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
        case .bulkLookup:
            BulkProfileLookupView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
        case .networkGraph:
            NetworkGraphView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
        case .timeline:
            iPadTimelineView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(workspaceStore)
                .environmentObject(localizationManager)
        case .notifications:
            iPadNotificationsView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
        case .chat:
            iPadChatView()
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
                .environmentObject(chatStore)
                .environmentObject(localizationManager)
        case .settings:
            SettingsView()
                .environmentObject(accountStore)
                .environmentObject(localizationManager)
                .environmentObject(blueskyClient)
        case .accounts:
            AccountTabView()
                .environmentObject(accountStore)
                .environmentObject(localizationManager)
        case .info:
            InfoView()
                .environmentObject(localizationManager)
        case nil:
            iPadEmptyDetailPlaceholder()
                .environmentObject(localizationManager)
        }
    }

    private var onboardingSheet: some View {
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
