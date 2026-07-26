import Combine
import Foundation
import UIKit
import UserNotifications

// MARK: - PushNotificationCoordinator

/// Coordinates push notification registration and handling across multiple
/// Bluesky accounts. Listens for APNs device tokens, registers/unregisters
/// each account with the Bluesky push service, and routes incoming push
/// payloads to the appropriate stores (chat, navigation, etc.).
@MainActor
final class PushNotificationCoordinator: ObservableObject {
    private let pushService: BlueskyPushNotificationServicing
    private let accountStore: AccountStore
    private let workspaceStore: ModerationWorkspaceStore
    private let chatStore: ChatStore

    private var cancellables: Set<AnyCancellable> = []
    private var deviceTokenHex: String?
    private var registeredAccountsByToken: [String: [UUID: AppAccount]] = [:]
    private var registrationRetryAfterByToken: [String: [UUID: Date]] = [:]
    private var isSyncingRegistrations = false
    private var syncRequestedWhileBusy = false
    private var hasRequestedRemoteRegistration = false
    private var isConfiguringRemoteRegistration = false

    init(
        pushService: BlueskyPushNotificationServicing,
        accountStore: AccountStore,
        workspaceStore: ModerationWorkspaceStore,
        chatStore: ChatStore
    ) {
        self.pushService = pushService
        self.accountStore = accountStore
        self.workspaceStore = workspaceStore
        self.chatStore = chatStore
        observeAppNotifications()
    }

    func start() {
        guard isPushNotificationsEnabled else { return }
        Task { await configureRemoteNotificationsIfPossible() }
    }

    func syncAccounts() {
        guard isPushNotificationsEnabled else { return }
        requestRegistrationSync()
    }

    private func observeAppNotifications() {
        NotificationCenter.default.publisher(for: .pushTokenDidUpdate)
            .sink { [weak self] notification in
                guard let self,
                      let tokenData = notification.userInfo?["deviceToken"] as? Data
                else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                guard deviceTokenHex != token else { return }
                deviceTokenHex = token
                AppLogger.moderation.debug("Received APNs device token for push registration.")
                requestRegistrationSync()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pushRegistrationDidFail)
            .sink { notification in
                let error = notification.userInfo?["error"] as? Error
                AppLogger.moderation.error("APNs registration failed: \(error?.localizedDescription ?? "unknown", privacy: .private)")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pushNotificationDidReceive)
            .sink { [weak self] notification in
                guard let self,
                      let payload = notification.userInfo?["payload"] as? [AnyHashable: Any]
                else { return }
                Task { await self.handlePushPayload(payload, shouldNavigate: false) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pushNotificationDidOpen)
            .sink { [weak self] notification in
                guard let self,
                      let payload = notification.userInfo?["payload"] as? [AnyHashable: Any]
                else { return }
                Task { await self.handlePushPayload(payload, shouldNavigate: true) }
            }
            .store(in: &cancellables)
    }

    private func configureRemoteNotificationsIfPossible() async {
        guard isPushNotificationsEnabled else { return }
        guard !serviceDID.isEmpty, !appID.isEmpty, !accountStore.accounts.isEmpty else { return }
        guard !hasRequestedRemoteRegistration else { return }
        guard !isConfiguringRemoteRegistration else { return }
        isConfiguringRemoteRegistration = true
        defer { isConfiguringRemoteRegistration = false }

        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else { return }
            case .denied:
                return
            default:
                break
            }

            hasRequestedRemoteRegistration = true
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            AppLogger.moderation.error("Notification authorization failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func requestRegistrationSync() {
        guard !isSyncingRegistrations else {
            syncRequestedWhileBusy = true
            return
        }
        Task { await syncRegistrations() }
    }

    private func syncRegistrations() async {
        guard isPushNotificationsEnabled else { return }
        guard !isSyncingRegistrations else {
            syncRequestedWhileBusy = true
            return
        }
        isSyncingRegistrations = true
        defer {
            isSyncingRegistrations = false
            if syncRequestedWhileBusy {
                syncRequestedWhileBusy = false
                requestRegistrationSync()
            }
        }
        await configureRemoteNotificationsIfPossible()

        guard let token = deviceTokenHex, !token.isEmpty else { return }
        guard !serviceDID.isEmpty, !appID.isEmpty else { return }

        let currentAccountsByID = Dictionary(uniqueKeysWithValues: accountStore.accounts.map { ($0.id, $0) })
        let currentAccountIDs = Set(currentAccountsByID.keys)
        let previouslyRegistered = registeredAccountsByToken[token] ?? [:]

        for (accountID, account) in previouslyRegistered where !currentAccountIDs.contains(accountID) {
            do {
                try await pushService.unregisterPush(
                    serviceDID: serviceDID,
                    token: token,
                    appID: appID,
                    account: account,
                    appPassword: accountStore.appPassword(for: account)
                )
            } catch {
                AppLogger.moderation.error("Push unregister failed for removed account \(account.handle): \(error.localizedDescription, privacy: .private)")
            }
        }

        var successfulRegistrations = previouslyRegistered
        for accountID in previouslyRegistered.keys where !currentAccountIDs.contains(accountID) {
            successfulRegistrations.removeValue(forKey: accountID)
        }
        let now = Date()
        var retryAfter = registrationRetryAfterByToken[token] ?? [:]
        for account in accountStore.accounts
            where previouslyRegistered[account.id] == nil
            && (retryAfter[account.id] ?? .distantPast) <= now
        {
            do {
                try await pushService.registerPush(
                    serviceDID: serviceDID,
                    token: token,
                    appID: appID,
                    account: account,
                    appPassword: accountStore.appPassword(for: account)
                )
                successfulRegistrations[account.id] = account
                retryAfter.removeValue(forKey: account.id)
            } catch {
                // APNs registration endpoints commonly return transient 5xx errors.
                // Avoid retrying the same account on every accounts/lifecycle event.
                retryAfter[account.id] = now.addingTimeInterval(60)
                AppLogger.moderation.error("Push register failed for \(account.handle): \(error.localizedDescription, privacy: .private)")
            }
        }

        registeredAccountsByToken[token] = successfulRegistrations
        registrationRetryAfterByToken[token] = retryAfter
    }

    private func handlePushPayload(_ payload: [AnyHashable: Any], shouldNavigate: Bool) async {
        AppLogger.moderation.debug("Received push payload with keys: \(payload.keys.map { String(describing: $0) }.joined(separator: ","), privacy: .private)")

        if let activeAccount = accountStore.activeAccount {
            let appPassword = accountStore.appPassword(for: activeAccount)
            chatStore.setAccount(activeAccount, appPassword: appPassword)
        }

        chatStore.signalSync()

        if let route = PushNotificationRoute(userInfo: payload) {
            if let conversationID = route.conversationID {
                workspaceStore.pendingChatConversationID = conversationID
                workspaceStore.selectedTab = .chat
                if shouldNavigate {
                    return
                }
            }

            if let memberDID = route.memberDID,
               let conversation = await chatStore.getOrCreateConvo(memberDID: memberDID)
            {
                workspaceStore.pendingChatConversation = conversation
                workspaceStore.selectedTab = .chat
            }
        }
    }

    private var isPushNotificationsEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "PushNotificationsEnabled") as? Bool ?? false
    }

    private var serviceDID: String {
        Bundle.main.object(forInfoDictionaryKey: "BskyPushServiceDID") as? String ?? ""
    }

    private var appID: String {
        Bundle.main.bundleIdentifier ?? ""
    }
}
