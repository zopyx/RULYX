import Foundation
import SwiftUI

@MainActor
final class iCloudAccountSync: ObservableObject {
    static let shared = iCloudAccountSync()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "iCloudSyncEnabled")
        }
    }

    private let store = NSUbiquitousKeyValueStore.default
    private let accountKey = "syncedAccounts"

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
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

    func pushAccounts(_ accounts: [AppAccount]) {
        guard isEnabled else { return }
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

    func pullFromCloud() {
        guard isEnabled else { return }
        guard let json = store.string(forKey: accountKey),
              let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else {
            return
        }
        NotificationCenter.default.post(name: .iCloudAccountsReceived, object: entries)
    }
}

extension Notification.Name {
    static let iCloudAccountsReceived = Notification.Name("iCloudAccountsReceived")
}
