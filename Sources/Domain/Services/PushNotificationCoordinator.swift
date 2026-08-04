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
        Task { await syncRegistrations() }
    }

    private func observeAppNotifications() {
        NotificationCenter.default.publisher(for: .pushTokenDidUpdate)
            .sink { [weak self] notification in
                guard let self,
                      let tokenData = notification.userInfo?["deviceToken"] as? Data
                else { return }
                deviceTokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
                AppLogger.moderation.debug("Received APNs device token for push registration.")
                Task { await self.syncRegistrations() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pushRegistrationDidFail)
            .sink { notification in
                let error = notification.userInfo?["error"] as? Error
                AppLogger.moderation.error("APNs registration failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
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

            // Without the aps-environment entitlement (e.g. simulator/dev builds
            // without a push provisioning profile) registration fails loudly on
            // every launch — skip it entirely in that case.
            guard hasAPNsEntitlement else {
                AppLogger.moderation.debug("APNs entitlement missing — skipping remote notification registration.")
                return
            }

            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            AppLogger.moderation.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncRegistrations() async {
        guard isPushNotificationsEnabled else { return }
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
                AppLogger.moderation.error("Push unregister failed for removed account \(account.handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        var successfulRegistrations: [UUID: AppAccount] = [:]
        for account in accountStore.accounts {
            do {
                try await pushService.registerPush(
                    serviceDID: serviceDID,
                    token: token,
                    appID: appID,
                    account: account,
                    appPassword: accountStore.appPassword(for: account)
                )
                successfulRegistrations[account.id] = account
            } catch {
                AppLogger.moderation.error("Push register failed for \(account.handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        registeredAccountsByToken[token] = successfulRegistrations
    }

    private func handlePushPayload(_ payload: [AnyHashable: Any], shouldNavigate: Bool) async {
        AppLogger.moderation.debug("Received push payload with keys: \(payload.keys.map { String(describing: $0) }.joined(separator: ","), privacy: .public)")

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

    /// Whether the running build carries the `aps-environment` entitlement.
    /// `registerForRemoteNotifications()` faults with "Keine gültige aps-environment-
    /// Entitlement-Zeichenkette" when it is absent (simulator/dev builds without a
    /// push provisioning profile). The entitlement is read from the embedded
    /// provisioning profile — on the simulator none exists, so registration is skipped.
    private var hasAPNsEntitlement: Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
                  let data = try? Data(contentsOf: url)
            else { return false }
            // The profile is a CMS signature; the entitlements plist is embedded between
            // the first "<?xml" marker and the closing "</plist>".
            guard let xmlStart = data.range(of: Data("<?xml".utf8)),
                  let xmlEnd = data.range(of: Data("</plist>".utf8), in: xmlStart.lowerBound ..< data.endIndex)
            else { return false }
            let plistData = data.subdata(in: xmlStart.lowerBound ..< xmlEnd.upperBound)
            guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
                  let entitlements = plist["Entitlements"] as? [String: Any]
            else { return false }
            return (entitlements["aps-environment"] as? String)?.isEmpty == false
        #endif
    }

    private var serviceDID: String {
        Bundle.main.object(forInfoDictionaryKey: "BskyPushServiceDID") as? String ?? ""
    }

    private var appID: String {
        Bundle.main.bundleIdentifier ?? ""
    }
}
