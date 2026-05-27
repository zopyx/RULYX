import Foundation

// MARK: - ModerationRule

/// A single moderation rule: when a condition (trigger) is met, perform an action.
struct ModerationRule: Identifiable, Codable, Hashable {
    /// Conditions that can trigger a rule when evaluating a profile.
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

    /// Actions to take when a rule triggers.
    enum Action: String, Codable, CaseIterable, Identifiable {
        case addToModList = "Add to Moderation List"
        case block = "Block"
        case mute = "Mute"
        case report = "Report"
        var id: String {
            rawValue
        }
    }

    /// Unique identifier.
    let id: UUID
    /// Display name for the rule.
    var name: String
    /// The condition that triggers this rule.
    var trigger: Trigger
    /// Value used by the trigger (e.g. text to match, threshold).
    var triggerValue: String
    /// Action to take when the rule triggers.
    var action: Action
    /// Target list ID for `addToModList` action.
    var targetListId: String?
    /// Whether the rule is active.
    var isEnabled: Bool

    // MARK: - Init

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

// MARK: - ModerationRuleStore

/// Persisted store for auto-moderation rules. Evaluates rules against profiles
/// and returns the matching actions. Backed by `UserDefaults`.
@MainActor
final class ModerationRuleStore: ObservableObject {
    /// All stored rules.
    @Published private(set) var rules: [ModerationRule] = []

    private let defaults: UserDefaults
    private let storageKey = "moderationRules"

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Public

    /// Insert or update a rule.
    func save(_ rule: ModerationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persist()
    }

    /// Remove a rule by ID.
    func delete(_ rule: ModerationRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    /// Toggle the rule's `isEnabled` state.
    func toggle(_ rule: ModerationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled.toggle()
        persist()
    }

    /// Evaluate all enabled rules against a profile and return the suggested actions.
    /// Returns an empty array if the profile has no DID or no rules match.
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
