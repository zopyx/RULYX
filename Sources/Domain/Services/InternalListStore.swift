import Foundation

// MARK: - InternalListStore

/// Manages user-created internal (local-only) lists that are not synced to
/// Bluesky. Persisted via `UserDefaults` with automatic seeding of default
/// lists ("Hostile" and "Friends") on first launch.
@MainActor
final class InternalListStore: ObservableObject {
    /// The list of internal lists, published for SwiftUI observation.
    @Published var lists: [InternalList] = [] {
        didSet { persist() }
    }

    private let storageKey = "internal.lists"
    private let seededKey = "internal.lists.seeded"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        if !defaults.bool(forKey: seededKey) {
            seedDefaults()
            defaults.set(true, forKey: seededKey)
        }
    }

    private func seedDefaults() {
        lists = [
            InternalList(name: "Hostile", color: .red),
            InternalList(name: "Friends", color: .green),
        ]
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([InternalList].self, from: data)
        else { return }
        lists = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func addList(name: String, color: InternalListColor) {
        let list = InternalList(name: name, color: color)
        lists.append(list)
    }

    func updateList(_ list: InternalList) {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index] = list
    }

    func deleteList(_ list: InternalList) {
        lists.removeAll { $0.id == list.id }
    }

    func addMember(did: String, handle: String, displayName: String? = nil, avatarURL: String? = nil, to listID: InternalList.ID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        guard !lists[index].members.contains(where: { $0.id == did }) else { return }
        let member = InternalListMember(did: did, handle: handle, displayName: displayName, avatarURL: avatarURL)
        lists[index].members.append(member)
    }

    func removeMember(did: String, from listID: InternalList.ID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[index].members.removeAll { $0.id == did }
    }

    func isMember(did: String, in listID: InternalList.ID) -> Bool {
        guard let list = lists.first(where: { $0.id == listID }) else { return false }
        return list.members.contains(where: { $0.id == did })
    }

    func memberStatus(did: String) -> [InternalList.ID: Bool] {
        var status: [InternalList.ID: Bool] = [:]
        for list in lists {
            status[list.id] = list.members.contains(where: { $0.id == did })
        }
        return status
    }
}
