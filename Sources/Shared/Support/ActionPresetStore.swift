import Foundation

// MARK: - ActionPreset

/// A named set of moderation actions (block, mute, report, add to list) that can be saved
/// as a preset and applied to actors quickly.
struct ActionPreset: Identifiable, Codable, Hashable {
    /// Unique identifier for the preset.
    let id: UUID
    /// Display name of the preset.
    var name: String
    /// Whether to block the actor.
    var shouldBlock: Bool
    /// Whether to mute the actor.
    var shouldMute: Bool
    /// Whether to report the actor.
    var shouldReport: Bool
    /// Target list name for adding the actor to a list.
    var targetListName: String?
    /// When the preset was created.
    var createdAt: Date

    // MARK: - Init

    init(id: UUID = UUID(), name: String, shouldBlock: Bool = false, shouldMute: Bool = false, shouldReport: Bool = false, targetListName: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.shouldBlock = shouldBlock
        self.shouldMute = shouldMute
        self.shouldReport = shouldReport
        self.targetListName = targetListName
        self.createdAt = createdAt
    }
}

// MARK: - ActionPresetStore

/// Persisted store for `ActionPreset` objects, backed by `UserDefaults`.
/// Singleton shared across the app.
@MainActor
final class ActionPresetStore: ObservableObject {
    static let shared = ActionPresetStore()
    /// All saved presets, ordered by creation (newest first).
    @Published private(set) var presets: [ActionPreset] = []

    private let defaults: UserDefaults
    private let storageKey = "actionPresets"

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Public

    /// Insert or update a preset (inserts at index 0 for new entries).
    func save(_ preset: ActionPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.insert(preset, at: 0)
        }
        persist()
    }

    /// Remove a preset by ID.
    func delete(_ preset: ActionPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    /// Create a copy of a preset with "(Copy)" suffix and insert at index 0.
    func duplicate(_ preset: ActionPreset) {
        let copy = ActionPreset(name: "\(preset.name) Copy", shouldBlock: preset.shouldBlock, shouldMute: preset.shouldMute, shouldReport: preset.shouldReport, targetListName: preset.targetListName)
        presets.insert(copy, at: 0)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ActionPreset].self, from: data) else { return }
        presets = decoded
    }
}
