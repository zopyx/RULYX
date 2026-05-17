import Foundation

struct BlueskyListMember: Identifiable, Hashable {
    let id: String
    let recordURI: String
    let actor: BlueskyActor
    let createdAt: Date?

    init(recordURI: String, actor: BlueskyActor, createdAt: Date? = nil) {
        id = recordURI
        self.recordURI = recordURI
        self.actor = actor
        self.createdAt = createdAt ?? Self.extractTimestampFromURI(recordURI)
    }

    private static func extractTimestampFromURI(_ uri: String) -> Date? {
        let tidChars = "234567abcdefghijklmnopqrstuvwxyz"
        var charToValue: [Character: UInt64] = [:]
        for (i, c) in tidChars.enumerated() {
            charToValue[c] = UInt64(i)
        }
        guard let tid = uri.split(separator: "/").last, tid.count == 13 else { return nil }
        var value: UInt64 = 0
        for c in tid {
            guard let v = charToValue[c] else { return nil }
            value = (value << 5) | v
        }
        let timestampMicros = value & ((1 << 53) - 1)
        return Date(timeIntervalSince1970: Double(timestampMicros) / 1_000_000)
    }
}
