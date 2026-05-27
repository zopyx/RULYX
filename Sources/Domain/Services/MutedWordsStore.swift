import Foundation

/// Manages a list of muted words used to filter timeline content.
/// Persisted in UserDefaults under the `"mutedWords"` key.
@MainActor
final class MutedWordsStore: ObservableObject {
    /// The current list of muted words. Any change is immediately persisted to UserDefaults.
    @Published var words: [String] {
        didSet {
            UserDefaults.standard.set(words, forKey: "mutedWords")
        }
    }

    // MARK: - Init

    /// Loads muted words from UserDefaults on initialization.
    init() {
        words = UserDefaults.standard.stringArray(forKey: "mutedWords") ?? []
    }

    // MARK: - Public Methods

    /// Returns `true` if the given text contains any muted word (case-insensitive match).
    func contains(_ text: String) -> Bool {
        let lower = text.lowercased()
        return words.contains { lower.contains($0.lowercased()) }
    }

    /// Adds a word to the muted list. Trims whitespace and prevents duplicates.
    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        words.append(trimmed)
    }

    /// Removes the word at the specified index.
    func remove(at index: Int) {
        words.remove(at: index)
    }
}
