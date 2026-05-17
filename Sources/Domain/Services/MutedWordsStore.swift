import Foundation

@MainActor
final class MutedWordsStore: ObservableObject {
    @Published var words: [String] {
        didSet {
            UserDefaults.standard.set(words, forKey: "mutedWords")
        }
    }

    init() {
        words = UserDefaults.standard.stringArray(forKey: "mutedWords") ?? []
    }

    func contains(_ text: String) -> Bool {
        let lower = text.lowercased()
        return words.contains { lower.contains($0.lowercased()) }
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        words.append(trimmed)
    }

    func remove(at index: Int) {
        words.remove(at: index)
    }
}
