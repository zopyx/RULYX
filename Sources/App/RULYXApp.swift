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
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(deps.accountStore)
                    .environmentObject(deps.workspaceStore)
                    .environmentObject(deps.blueskyClient)
                    .environmentObject(deps.localizationManager)
                    .environmentObject(deps.mutedWordsStore)
                    .environmentObject(deps.analyticsStore)
                    .environmentObject(deps.chatStore)
                    .environmentObject(deps.httpRequestDebugStore)
                    .environmentObject(deps.clearskyHeartbeat)
                    .environmentObject(appLockManager)
                    .environmentObject(iCloudAccountSync.shared)
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
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        DispatchQueue.main.async {
                            appLockManager.appDidBecomeActive()
                            deps.pushNotificationCoordinator.start()
                            deps.chatStore.startPolling()
                        }
                    }

                if showSplash {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
        }
    }
}

