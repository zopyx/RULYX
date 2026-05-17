import Foundation

@MainActor
final class ListImportController {
    func preparePreview(
        from rawInput: String,
        sourceDescription: String,
        existingMemberDIDs: Set<String>,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws -> ImportPreview {
        let start = CFAbsoluteTimeGetCurrent()
        let tokens = importedIdentifiers(from: rawInput)
        guard !tokens.isEmpty else {
            throw AppError(category: .validation, message: "Paste at least one handle, DID, or profile URL.")
        }

        var seenTokens: Set<String> = []
        var seenResolvedDIDs: Set<String> = []
        var items: [ImportPreviewItem] = []
        var tokensToResolve: [(index: Int, token: String)] = []

        for (index, token) in tokens.enumerated() {
            let normalizedToken = token.lowercased()
            if !seenTokens.insert(normalizedToken).inserted {
                items.append(
                    ImportPreviewItem(
                        token: token,
                        actor: nil,
                        classification: .duplicate,
                        message: "Duplicate identifier in this import payload."
                    )
                )
                continue
            }
            tokensToResolve.append((index, token))
            items.append(.init(token: token, actor: nil, classification: .unresolved, message: nil))
        }

        let session = URLSession.shared
        let apiBatchSize = 25

        if !tokensToResolve.isEmpty {
            try await withThrowingTaskGroup(of: [(index: Int, actor: BlueskyActor?)].self) { group in
                var offset = 0
                while offset < tokensToResolve.count {
                    let chunk = tokensToResolve[offset ..< min(offset + apiBatchSize, tokensToResolve.count)]
                    offset += apiBatchSize
                    let batchIndices = Array(chunk)
                    group.addTask {
                        let batchTokens = batchIndices.map(\.token)
                        let profiles = (try? await LiveBlueskyClient.fetchProfileBatch(identifiers: batchTokens, session: session)) ?? []
                        let byHandle: [String: BlueskyActor] = Dictionary(
                            uniqueKeysWithValues: profiles.map { ($0.handle.lowercased(), $0) }
                        )
                        let byDID: [String: BlueskyActor] = Dictionary(
                            uniqueKeysWithValues: profiles.map { ($0.did, $0) }
                        )
                        return batchIndices.map { entry in
                            let lowerToken = entry.token.lowercased()
                            if let actor = byDID[lowerToken] ?? byHandle[lowerToken] {
                                return (entry.index, actor)
                            }
                            return (entry.index, nil as BlueskyActor?)
                        }
                    }
                }

                for try await batch in group {
                    for (index, resolved) in batch {
                        guard let actor = resolved else { continue }

                        if existingMemberDIDs.contains(actor.did) {
                            items[index] = ImportPreviewItem(
                                token: tokens[index],
                                actor: actor,
                                classification: .alreadyPresent,
                                message: "Already a member of this list."
                            )
                        } else if !seenResolvedDIDs.insert(actor.did).inserted {
                            items[index] = ImportPreviewItem(
                                token: tokens[index],
                                actor: actor,
                                classification: .duplicate,
                                message: "Another entry in this import resolves to the same account."
                            )
                        } else {
                            items[index] = ImportPreviewItem(
                                token: tokens[index],
                                actor: actor,
                                classification: .ready,
                                message: nil
                            )
                        }
                    }
                }
            }
        }

        AppLogger.performance.debug("Import preview for '\(sourceDescription, privacy: .public)' with \(tokens.count) tokens took \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")

        return ImportPreview(
            sourceDescription: sourceDescription,
            items: items
        )
    }

    private func importedIdentifiers(from rawInput: String) -> [String] {
        let separators = CharacterSet.newlines
        return rawInput
            .components(separatedBy: separators)
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return [] }

                if trimmed.contains(",") {
                    return trimmed.split(separator: ",").map(String.init)
                }

                if trimmed.contains(";") {
                    return trimmed.split(separator: ";").map(String.init)
                }

                return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            }
            .map { normalizedImportedIdentifier($0) }
            .filter { !$0.isEmpty }
    }

    private func normalizedImportedIdentifier(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !trimmed.isEmpty else { return "" }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("https://bsky.app/profile/") {
            return extractProfileIdentifier(from: trimmed)
        }

        if lowercased.hasPrefix("http://bsky.app/profile/") {
            return extractProfileIdentifier(from: trimmed)
        }

        if lowercased.hasPrefix("bsky.app/profile/") {
            return extractProfileIdentifier(from: "https://\(trimmed)")
        }

        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }

        return trimmed
    }

    private func extractProfileIdentifier(from value: String) -> String {
        guard let url = URL(string: value),
              let profileIndex = url.pathComponents.firstIndex(of: "profile"),
              url.pathComponents.indices.contains(profileIndex + 1)
        else {
            return value
        }

        return url.pathComponents[profileIndex + 1]
    }
}
