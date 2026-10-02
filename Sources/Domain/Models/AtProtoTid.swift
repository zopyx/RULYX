import Foundation

/// Decoder for AT Protocol TIDs — the timestamp-ordered record keys used for most
/// records, including `app.bsky.graph.block`.
///
/// A TID is 13 base32-sortable characters: 1 unused bit, 53 bits of microseconds
/// since the Unix epoch, and 10 bits of clock/sequence data. Decoding a record key
/// therefore yields the record's creation time without an extra `getRecord` round
/// trip — which is what lets the Constellation fallback date block records.
///
/// Measured accuracy against `com.atproto.repo.getRecord` `createdAt`: < 1 second.
enum AtProtoTid {
    private static let alphabet = "234567abcdefghijklmnopqrstuvwxyz"

    private static let characterValues: [Character: UInt64] = {
        var values = [Character: UInt64](minimumCapacity: alphabet.count)
        for (index, character) in alphabet.enumerated() {
            values[character] = UInt64(index)
        }
        return values
    }()

    /// Decodes the record creation date from a TID record key.
    /// - Returns: `nil` when the key is not a well-formed TID (wrong length,
    ///   characters outside the base32-sortable alphabet, or a timestamp more
    ///   than a day in the future).
    static func date(fromRecordKey recordKey: String) -> Date? {
        guard recordKey.count == 13 else { return nil }

        var value: UInt64 = 0
        for character in recordKey {
            guard let digit = characterValues[character], value <= (UInt64.max >> 5) else { return nil }
            value = (value << 5) | digit
        }

        let micros = value >> 10
        guard micros > 0 else { return nil }

        let date = Date(timeIntervalSince1970: Double(micros) / 1_000_000)
        guard date <= Date().addingTimeInterval(60 * 60 * 24) else { return nil }
        return date
    }

    /// Decodes the record creation date from an AT URI (`at://<did>/<collection>/<rkey>`).
    static func date(fromATURI uri: String) -> Date? {
        guard let recordKey = uri.split(separator: "/").last else { return nil }
        return date(fromRecordKey: String(recordKey))
    }
}
