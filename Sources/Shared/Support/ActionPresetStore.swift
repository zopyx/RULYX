import Foundation

struct ActionPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var shouldBlock: Bool
    var shouldMute: Bool
    var shouldReport: Bool
    var targetListName: String?
    var createdAt: Date

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

@MainActor
final class ActionPresetStore: ObservableObject {
    static let shared = ActionPresetStore()
    @Published private(set) var presets: [ActionPreset] = []

    private let defaults: UserDefaults
    private let storageKey = "actionPresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func save(_ preset: ActionPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.insert(preset, at: 0)
        }
        persist()
    }

    func delete(_ preset: ActionPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

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
