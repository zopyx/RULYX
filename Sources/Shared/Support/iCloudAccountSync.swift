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

    private let accountKey = "syncedAccounts"

    // MARK: - Init

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                Task { @MainActor in
                    self?.pullFromCloud()
                }
            }
        )
    }

    /// The shared KVS store, only reachable when the app has the
    /// `com.apple.developer.ubiquity-kvstore-identifier` entitlement and the user is
    /// signed in to iCloud. Accessing `NSUbiquitousKeyValueStore.default` without the
    /// entitlement logs "Unable to find entitlement for KVS store" plus a
    /// "BUG IN CLIENT OF KVS" fault on every launch, so the store must never be
    /// touched unconditionally.
    private var store: NSUbiquitousKeyValueStore? {
        guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
        return NSUbiquitousKeyValueStore.default
    }

    /// Show a privacy alert before enabling iCloud sync.
    func requestEnable() {
        showPrivacyAlert = true
    }

    /// Called when the user confirms the privacy alert.
    func confirmEnable() {
        isEnabled = true
        showPrivacyAlert = false
        // Pull any state that changed on other devices while sync was off.
        store?.synchronize()
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
    /// Validates DID/handle format before posting to prevent malicious KV injection.
    func pullFromCloud() {
        guard isEnabled, let store else { return }
        guard let json = store.string(forKey: accountKey),
              let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else {
            return
        }
        let validated = entries.filter { entry in
            guard let id = entry["id"], UUID(uuidString: id) != nil,
                  let handle = entry["handle"], isValidHandle(handle),
                  let did = entry["did"], isValidDID(did) else { return false }
            return true
        }
        guard !validated.isEmpty else { return }
        NotificationCenter.default.post(name: .iCloudAccountsReceived, object: validated)
    }

    private func isValidHandle(_ handle: String) -> Bool {
        // Bluesky handle: 1-253 chars, alphanumerics/hyphen/dot, must contain dot, no leading/trailing dot
        guard handle.count >= 3, handle.count <= 253, handle.contains(".") else { return false }
        let pattern = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$"
        return handle.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidDID(_ did: String) -> Bool {
        did.hasPrefix("did:plc:") || did.hasPrefix("did:web:")
    }
}

extension Notification.Name {
    /// Posted when iCloud sync delivers account metadata.
    static let iCloudAccountsReceived = Notification.Name("iCloudAccountsReceived")
}
