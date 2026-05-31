import Foundation
import SwiftUI

// MARK: - iCloudAccountSync

/// Manages syncing of `AppAccount` metadata across devices via `NSUbiquitousKeyValueStore`.
/// Toggle `isEnabled` to start syncing. Pushes on save, pulls on external change notification.
@MainActor
class iCloudAccountSync: ObservableObject {
    static let shared = iCloudAccountSync()

    /// Whether iCloud sync is enabled.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "iCloudSyncEnabled")
        }
    }

    /// Whether to show the privacy alert before enabling.
    @Published var showPrivacyAlert = false

    private let store: NSUbiquitousKeyValueStore?
    private let accountKey = "syncedAccounts"
    private let isCloudKVSEntitled: Bool

    // MARK: - Init

    init() {
        isCloudKVSEntitled = Self.hasEntitlement("com.apple.developer.ubiquity-kvstore-identifier")
        store = isCloudKVSEntitled ? NSUbiquitousKeyValueStore.default : nil
        isEnabled = isCloudKVSEntitled && (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false)

        guard let store else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main,
            using: { [weak self] _ in
                Task { @MainActor in
                    self?.pullFromCloud()
                }
            }
        )
        store.synchronize()
    }

    /// Show a privacy alert before enabling iCloud sync.
    func requestEnable() {
        guard isCloudKVSEntitled else { return }
        showPrivacyAlert = true
    }

    /// Called when the user confirms the privacy alert.
    func confirmEnable() {
        guard isCloudKVSEntitled else { return }
        isEnabled = true
        showPrivacyAlert = false
    }

    /// Called when the user cancels the privacy alert.
    func cancelEnable() {
        isEnabled = false
        showPrivacyAlert = false
    }

    /// Encode and push accounts to iCloud key-value store.
    func pushAccounts(_ accounts: [AppAccount]) {
        guard isEnabled, let store else { return }
        let data: [[String: String]] = accounts.compactMap { account in
            guard let did = account.did else { return nil }
            return [
                "id": account.id.uuidString,
                "handle": account.handle,
                "displayName": account.displayName,
                "did": did,
                "label": account.label ?? "",
                "pdsURL": account.pdsURL?.absoluteString ?? "",
                "entrywayURL": account.entrywayURL?.absoluteString ?? "",
            ]
        }
        if let encoded = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: encoded, encoding: .utf8)
        {
            store.set(json, forKey: accountKey)
            store.synchronize()
        }
    }

    /// Pull account data from iCloud and post a notification for the `AccountStore` to consume.
    func pullFromCloud() {
        guard isEnabled, let store else { return }
        guard let json = store.string(forKey: accountKey),
              let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else {
            return
        }
        NotificationCenter.default.post(name: .iCloudAccountsReceived, object: entries)
    }

    private static func hasEntitlement(_ name: String) -> Bool {
        #if targetEnvironment(simulator)
            false
        #else
            !name.isEmpty
        #endif
    }
}

extension Notification.Name {
    /// Posted when iCloud sync delivers account metadata.
    static let iCloudAccountsReceived = Notification.Name("iCloudAccountsReceived")
}
