import Foundation

struct ModerationRule: Identifiable, Codable, Hashable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case accountYoungerThan = "Account younger than 30 days"
        case followerCountBelow = "Follower count below 100"
        case followerCountAbove = "Follower count above 1000"
        case handleContains = "Handle contains text"
        case hasLabel = "Has label"
        var id: String {
            rawValue
        }
    }

    enum Action: String, Codable, CaseIterable, Identifiable {
        case addToModList = "Add to Moderation List"
        case block = "Block"
        case mute = "Mute"
        case report = "Report"
        var id: String {
            rawValue
        }
    }

    let id: UUID
    var name: String
    var trigger: Trigger
    var triggerValue: String
    var action: Action
    var targetListId: String?
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, trigger: Trigger, triggerValue: String = "", action: Action, targetListId: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.triggerValue = triggerValue
        self.action = action
        self.targetListId = targetListId
        self.isEnabled = isEnabled
    }
}

@MainActor
final class ModerationRuleStore: ObservableObject {
    @Published private(set) var rules: [ModerationRule] = []

    private let defaults: UserDefaults
    private let storageKey = "moderationRules"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func save(_ rule: ModerationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persist()
    }

    func delete(_ rule: ModerationRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    func toggle(_ rule: ModerationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled.toggle()
        persist()
    }

    func evaluate(against profile: BlueskyProfile) -> [ModerationRule.Action] {
        guard !profile.did.isEmpty else { return [] }
        return rules.filter { rule in
            guard rule.isEnabled else { return false }
            switch rule.trigger {
            case .accountYoungerThan:
                guard let createdAt = profile.createdAt else { return false }
                return createdAt > Date.now.addingTimeInterval(-30 * 86400)
            case .followerCountBelow:
                guard let count = profile.followersCount else { return false }
                return count < 100
            case .followerCountAbove:
                guard let count = profile.followersCount else { return false }
                return count > 1000
            case .handleContains:
                return profile.handle.localizedCaseInsensitiveContains(rule.triggerValue) ||
                    (profile.displayName?.localizedCaseInsensitiveContains(rule.triggerValue) ?? false)
            case .hasLabel:
                return profile.labels.contains { $0.localizedCaseInsensitiveContains(rule.triggerValue) }
            }
        }.map(\.action)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ModerationRule].self, from: data) else { return }
        rules = decoded
    }
}
