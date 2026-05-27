import SwiftUI

func configureCache() {
    let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "bluesky-cache")
    URLCache.shared = cache
}

@main
struct RULYXApp: App {
    @UIApplicationDelegateAdaptor(BlueskyAppDelegate.self) private var appDelegate
    @StateObject private var deps = AppDependencies()
    @ObservedObject private var appLockManager = AppLockManager.shared
    @AppStorage("hasSplashed") private var hasSplashed = false
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(deps.accountStore)
                    .environmentObject(deps.workspaceStore)
                    .environmentObject(deps.blueskyClient)
                    .environmentObject(deps.localizationManager)
                    .environment(\.locale, deps.localizationManager.locale)
                    .environmentObject(deps.mutedWordsStore)
                    .environmentObject(deps.analyticsStore)
                    .environmentObject(deps.chatStore)
                    .environmentObject(deps.httpRequestDebugStore)
                    .environmentObject(deps.clearskyHeartbeat)
                    .environmentObject(deps.internalListStore)
                    .environmentObject(deps.aiService)
                    .environmentObject(appLockManager)
                    .environmentObject(iCloudAccountSync.shared)
                    .alert(Text(loc: "settings.icloud.privacy.title"), isPresented: Binding(get: { iCloudAccountSync.shared.showPrivacyAlert }, set: { if !$0 { iCloudAccountSync.shared.showPrivacyAlert = false } })) {
                        Button(loc("settings.icloud.privacy.cancel"), role: .cancel) {
                            iCloudAccountSync.shared.cancelEnable()
                        }
                        Button(loc("settings.icloud.privacy.confirm")) {
                            iCloudAccountSync.shared.confirmEnable()
                        }
                    } message: {
                        Text(loc: "settings.icloud.privacy.message")
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            configureCache()
                        }
                    }
                    .animation(UIAccessibility.isReduceMotionEnabled ? nil : .default, value: appLockManager.isLocked)
                    .task {
                        await deps.blueskyClient.restoreSessions(for: deps.accountStore.accounts)
                    }
                    .task {
                        guard CommandLine.arguments.contains("--test-account"),
                              let handle = ProcessInfo.processInfo.environment["TEST_HANDLE"],
                              let password = ProcessInfo.processInfo.environment["TEST_PASSWORD"] else { return }
                        guard !deps.accountStore.accounts.contains(where: { $0.handle == handle }) else { return }
                        let pdsURL = ProcessInfo.processInfo.environment["TEST_PDS"].flatMap { URL(string: $0) }
                        _ = await deps.accountStore.addAccount(handle: handle, appPassword: password, entrywayURL: pdsURL, client: deps.blueskyClient)
                    }
                    .task {
                        DispatchQueue.main.async {
                            deps.pushNotificationCoordinator.start()
                        }
                    }
                    .task {
                        DispatchQueue.main.async {
                            deps.clearskyHeartbeat.start()
                        }
                    }
                    .task(id: deps.accountStore.activeAccountID) {
                        let appPassword = deps.accountStore.activeAccount.flatMap { deps.accountStore.appPassword(for: $0) }
                        deps.chatStore.setAccount(deps.accountStore.activeAccount, appPassword: appPassword)
                        deps.chatStore.startPolling()
                        await deps.chatStore.loadConvos()
                        deps.pushNotificationCoordinator.syncAccounts()
                    }
                    .onReceive(deps.accountStore.$accounts) { _ in
                        DispatchQueue.main.async {
                            deps.pushNotificationCoordinator.syncAccounts()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        DispatchQueue.main.async {
                            appLockManager.appDidEnterBackground()
                            deps.clearskyHeartbeat.stop()
                            deps.chatStore.stopPolling()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        DispatchQueue.main.async {
                            appLockManager.appDidBecomeActive()
                            deps.clearskyHeartbeat.start()
                            deps.pushNotificationCoordinator.start()
                            deps.chatStore.startPolling()
                        }
                    }

                if showSplash {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        .zIndex(100)
                        .onAppear {
                            if hasSplashed {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation { showSplash = false }
                                }
                            }
                            hasSplashed = true
                        }
                }
            }
        }
    }
}
