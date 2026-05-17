import Foundation

struct ProfileLookupResult: Identifiable {
    let id: String
    let query: String
    let profile: BlueskyProfile?
    let error: String?
    let isResolved: Bool
}

@MainActor
final class BulkProfileLookupViewModel: ObservableObject {
    @Published var rawInput = ""
    @Published private(set) var results: [ProfileLookupResult] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func lookup(account: AppAccount?, appPassword: String?, using client: LiveBlueskyClient) async {
        let tokens = parsedIdentifiers(from: rawInput)
        guard !tokens.isEmpty else {
            errorMessage = "Paste at least one handle, DID, or profile URL."
            return
        }
        guard let account else {
            errorMessage = "Select an active account first."
            return
        }
        guard let appPassword, !appPassword.isEmpty else {
            errorMessage = "No saved app password found."
            return
        }

        isLoading = true
        errorMessage = nil
        results = tokens.map { ProfileLookupResult(id: UUID().uuidString, query: $0, profile: nil, error: nil, isResolved: false) }

        for index in results.indices {
            let token = results[index].query
            do {
                let profile = try await client.fetchProfile(did: token, account: account, appPassword: appPassword)
                results[index] = ProfileLookupResult(id: results[index].id, query: token, profile: profile, error: nil, isResolved: true)
            } catch {
                results[index] = ProfileLookupResult(id: results[index].id, query: token, profile: nil, error: AppError.userMessage(from: error), isResolved: false)
            }
        }

        isLoading = false
    }

    func clear() {
        rawInput = ""
        results = []
        errorMessage = nil
    }

    private func parsedIdentifiers(from rawInput: String) -> [String] {
        let separators = CharacterSet.newlines
        let rows = rawInput
            .components(separatedBy: separators)
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return [] }
                if trimmed.contains(",") { return trimmed.split(separator: ",").map(String.init) }
                if trimmed.contains(";") { return trimmed.split(separator: ";").map(String.init) }
                return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            }
            .map { normalizedImportedIdentifier($0) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return rows.filter { seen.insert($0.lowercased()).inserted }
    }

    private func normalizedImportedIdentifier(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !trimmed.isEmpty else { return "" }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("https://bsky.app/profile/") || lowercased.hasPrefix("http://bsky.app/profile/") {
            return extractProfileIdentifier(from: trimmed)
        }
        if lowercased.hasPrefix("bsky.app/profile/") {
            return extractProfileIdentifier(from: "https://\(trimmed)")
        }
        if trimmed.hasPrefix("@") { return String(trimmed.dropFirst()) }
        return trimmed
    }

    private func extractProfileIdentifier(from value: String) -> String {
        guard let url = URL(string: value),
              let profileIndex = url.pathComponents.firstIndex(of: "profile"),
              url.pathComponents.indices.contains(profileIndex + 1) else { return value }
        return url.pathComponents[profileIndex + 1]
    }
}
