import Foundation

struct GIFResult: Identifiable, Hashable {
    let id: String
    let mp4URL: String
    let previewURL: String
    let width: Int
    let height: Int
    let title: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GIFResult, rhs: GIFResult) -> Bool {
        lhs.id == rhs.id
    }
}

enum GIFError: LocalizedError {
    case missingAPIKey
    case networkError(String)
    case noResults

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "KLIPY API key not configured. Add it in Settings."
        case let .networkError(msg): msg
        case .noResults: "No GIFs found"
        }
    }
}

final class GIFService: Sendable {
    static let shared = GIFService()

    private let httpClient = HTTPClient()
    private let baseURL = "https://api.klipy.com/api/v1"
    private let perPage = 24
    private let keychain: KeychainServicing

    private let keychainService = "com.ajung.RULYX.klipy"
    private let keychainAccount = "apiKey"

    init(keychain: KeychainServicing = KeychainService()) {
        self.keychain = keychain
        seedKeyIfNeeded()
        migrateFromUserDefaults()
    }

    private func seedKeyIfNeeded() {
        guard (try? keychain.read(service: keychainService, account: keychainAccount)) == nil else { return }
        try? keychain.save("W3FgVTePIgmlS4FEj8oF2xbMzXgwx3QGPX3pYEmrQZIvH4eRB0sin6PKqzun4f6R", service: keychainService, account: keychainAccount)
    }

    private var apiKey: String? {
        guard let key = try? keychain.read(service: keychainService, account: keychainAccount) else { return nil }
        return key.isEmpty ? nil : key
    }

    private func migrateFromUserDefaults() {
        if let oldKey = UserDefaults.standard.string(forKey: "klipyAPIKey"), !oldKey.isEmpty {
            try? keychain.save(oldKey, service: keychainService, account: keychainAccount)
            UserDefaults.standard.removeObject(forKey: "klipyAPIKey")
        }
    }

    func search(query: String) async throws -> [GIFResult] {
        guard let apiKey else { throw GIFError.missingAPIKey }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "\(baseURL)/\(apiKey)/gifs/search?q=\(encoded)&per_page=\(perPage)&format_filter=mp4,gif")!
        let (data, _) = try await httpClient.data(from: url, source: "GIF Search")
        let decoded = try JSONDecoder().decode(KlipyResponse.self, from: data)
        return decoded.data.data.map { $0.toGIFResult() }
    }

    func trending() async throws -> [GIFResult] {
        guard let apiKey else { throw GIFError.missingAPIKey }
        let url = URL(string: "\(baseURL)/\(apiKey)/gifs/trending?per_page=\(perPage)&format_filter=mp4,gif")!
        let (data, _) = try await httpClient.data(from: url, source: "GIF Trending")
        let decoded = try JSONDecoder().decode(KlipyResponse.self, from: data)
        return decoded.data.data.map { $0.toGIFResult() }
    }

    func downloadGIF(url: String) async throws -> Data {
        guard let url = URL(string: url) else { throw GIFError.networkError("Invalid URL") }
        let (data, _) = try await httpClient.data(from: url, source: "GIF Download")
        return data
    }
}

// MARK: - Keychain Helper

enum KlipyKeychainHelper {
    private static let service = "com.ajung.RULYX.klipy"
    private static let account = "apiKey"
    private static let keychain: KeychainServicing = KeychainService()

    static func read() -> String {
        (try? keychain.read(service: service, account: account)) ?? ""
    }

    static func save(_ value: String) {
        if value.isEmpty {
            try? keychain.delete(service: service, account: account)
        } else {
            try? keychain.save(value, service: service, account: account)
        }
    }

    static func exists() -> Bool {
        guard let key = try? keychain.read(service: service, account: account) else { return false }
        return !key.isEmpty
    }
}

// MARK: - KLIPY Response Models

private struct KlipyResponse: Decodable {
    let result: Bool
    let data: KlipyData
}

private struct KlipyData: Decodable {
    let data: [KlipyGIF]
}

private struct KlipyGIF: Decodable {
    let id: Int
    let title: String?
    let file: KlipyFile?

    func toGIFResult() -> GIFResult {
        let format = file?.hd ?? file?.md ?? file?.sm
        return GIFResult(
            id: "\(id)",
            mp4URL: format?.mp4?.url ?? "",
            previewURL: format?.gif?.url ?? format?.mp4?.url ?? "",
            width: format?.gif?.width ?? format?.mp4?.width ?? 0,
            height: format?.gif?.height ?? format?.mp4?.height ?? 0,
            title: title ?? ""
        )
    }
}

private struct KlipyFile: Decodable {
    let hd: KlipyFormat?
    let md: KlipyFormat?
    let sm: KlipyFormat?
}

private struct KlipyFormat: Decodable {
    let gif: KlipyMedia?
    let mp4: KlipyMedia?
}

private struct KlipyMedia: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}
