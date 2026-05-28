import Foundation

struct GIFResult: Identifiable, Hashable, Sendable {
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

enum GIFError: LocalizedError, Equatable {
    case missingAPIKey
    case networkError(String)
    case noResults
    case invalidURL
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "KLIPY API key not configured. Add it in Settings."
        case let .networkError(message):
            message
        case .noResults:
            "No GIFs found"
        case .invalidURL:
            "GIF service URL is invalid."
        case .tooLarge:
            "GIF is too large to attach."
        }
    }
}

final class GIFService: Sendable {
    static let shared = GIFService()

    static let keychainService = "com.ajung.RULYX.klipy"
    static let keychainAccount = "apiKey"

    private static let bundledAPIKey = "W3FgVTePIgmlS4FEj8oF2xbMzXgwx3QGPX3pYEmrQZIvH4eRB0sin6PKqzun4f6R"

    private let baseURL = URL(string: "https://api.klipy.com/api/v1")!
    private let httpClient: HTTPClient
    private let keychain: KeychainServicing
    private let maxAttachmentBytes: Int64
    private let perPage: Int

    init(
        httpClient: HTTPClient = HTTPClient(),
        keychain: KeychainServicing = KeychainService(),
        maxAttachmentBytes: Int64 = 20_000_000,
        perPage: Int = 24
    ) {
        self.httpClient = httpClient
        self.keychain = keychain
        self.maxAttachmentBytes = maxAttachmentBytes
        self.perPage = perPage
        migrateLegacyAPIKey()
        Self.seedKeyIfNeeded(in: keychain)
    }

    static func seedKeyIfNeeded(in keychain: KeychainServicing = KeychainService()) {
        guard (try? keychain.read(service: keychainService, account: keychainAccount)) == nil else { return }
        try? keychain.save(bundledAPIKey, service: keychainService, account: keychainAccount)
    }

    func search(query: String) async throws -> [GIFResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try await trending() }

        let url = try makeURL(
            path: "gifs/search",
            queryItems: [
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "per_page", value: "\(perPage)"),
                URLQueryItem(name: "format_filter", value: "mp4,gif"),
            ]
        )
        return try await loadResults(from: url, source: "GIF Search")
    }

    func trending() async throws -> [GIFResult] {
        let url = try makeURL(
            path: "gifs/trending",
            queryItems: [
                URLQueryItem(name: "per_page", value: "\(perPage)"),
                URLQueryItem(name: "format_filter", value: "mp4,gif"),
            ]
        )
        return try await loadResults(from: url, source: "GIF Trending")
    }

    func downloadGIF(url urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw GIFError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (fileURL, response) = try await httpClient.download(for: request, source: "GIF Download")

        guard (200 ..< 300).contains(response.statusCode) else {
            throw GIFError.networkError("GIF download failed.")
        }
        if response.expectedContentLength > maxAttachmentBytes {
            throw GIFError.tooLarge
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attributes[.size] as? NSNumber, size.int64Value > maxAttachmentBytes {
            throw GIFError.tooLarge
        }

        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    private var apiKey: String? {
        guard let value = try? keychain.read(service: Self.keychainService, account: Self.keychainAccount) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func migrateLegacyAPIKey() {
        guard let oldKey = UserDefaults.standard.string(forKey: "klipyAPIKey"), !oldKey.isEmpty else { return }
        try? keychain.save(oldKey, service: Self.keychainService, account: Self.keychainAccount)
        UserDefaults.standard.removeObject(forKey: "klipyAPIKey")
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard let apiKey else { throw GIFError.missingAPIKey }
        let endpoint = baseURL
            .appending(path: apiKey)
            .appending(path: path)

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw GIFError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw GIFError.invalidURL }
        return url
    }

    private func loadResults(from url: URL, source: String) async throws -> [GIFResult] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await httpClient.data(for: request, source: source)

        guard (200 ..< 300).contains(response.statusCode) else {
            throw GIFError.networkError("GIF service returned HTTP \(response.statusCode).")
        }

        do {
            let response = try JSONDecoder().decode(KlipyResponse.self, from: data)
            let results = response.results.compactMap(\.gifResult)
            guard !results.isEmpty else { throw GIFError.noResults }
            return results
        } catch let error as GIFError {
            throw error
        } catch {
            throw GIFError.networkError("GIF service response could not be read.")
        }
    }
}

enum KlipyKeychainHelper {
    private static let keychain: KeychainServicing = KeychainService()

    static func read() -> String {
        GIFService.seedKeyIfNeeded(in: keychain)
        return (try? keychain.read(service: GIFService.keychainService, account: GIFService.keychainAccount)) ?? ""
    }

    static func save(_ value: String) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? keychain.delete(service: GIFService.keychainService, account: GIFService.keychainAccount)
        } else {
            try? keychain.save(value, service: GIFService.keychainService, account: GIFService.keychainAccount)
        }
    }

    static func exists() -> Bool {
        GIFService.seedKeyIfNeeded(in: keychain)
        guard let key = try? keychain.read(service: GIFService.keychainService, account: GIFService.keychainAccount) else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct KlipyResponse: Decodable {
    let result: Bool?
    let payload: KlipyPayload

    var results: [KlipyGIF] {
        guard result != false else { return [] }
        return payload.items
    }

    private enum CodingKeys: String, CodingKey {
        case result
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decodeIfPresent(Bool.self, forKey: .result)
        payload = try container.decode(KlipyPayload.self, forKey: .data)
    }
}

private struct KlipyPayload: Decodable {
    let items: [KlipyGIF]

    private enum CodingKeys: String, CodingKey {
        case data
        case results
    }

    init(from decoder: Decoder) throws {
        if let direct = try? [KlipyGIF](from: decoder) {
            items = direct
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decode([KlipyGIF].self, forKey: .data))
            ?? (try? container.decode([KlipyGIF].self, forKey: .results))
            ?? []
    }
}

private struct KlipyGIF: Decodable {
    let id: String
    let title: String?
    let file: KlipyFile?

    var gifResult: GIFResult? {
        guard let media = file?.preferredMedia, !media.mp4URL.isEmpty else { return nil }
        return GIFResult(
            id: id,
            mp4URL: media.mp4URL,
            previewURL: media.previewURL,
            width: media.width,
            height: media.height,
            title: title ?? ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeStringOrInt(forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        file = try container.decodeIfPresent(KlipyFile.self, forKey: .file)
    }
}

private struct KlipyFile: Decodable {
    let hd: KlipyFormat?
    let md: KlipyFormat?
    let sm: KlipyFormat?

    var preferredMedia: KlipySelectedMedia? {
        [sm, md, hd].compactMap { $0?.selectedMedia }.first
    }
}

private struct KlipyFormat: Decodable {
    let gif: KlipyMedia?
    let mp4: KlipyMedia?

    var selectedMedia: KlipySelectedMedia? {
        guard let mp4URL = mp4?.url, !mp4URL.isEmpty else { return nil }
        let previewURL = gif?.url.flatMap { $0.isEmpty ? nil : $0 } ?? mp4URL
        return KlipySelectedMedia(
            mp4URL: mp4URL,
            previewURL: previewURL,
            width: mp4?.width ?? gif?.width ?? 0,
            height: mp4?.height ?? gif?.height ?? 0
        )
    }
}

private struct KlipyMedia: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

private struct KlipySelectedMedia {
    let mp4URL: String
    let previewURL: String
    let width: Int
    let height: Int
}

private extension KeyedDecodingContainer {
    func decodeStringOrInt(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        return String(try decode(Int.self, forKey: key))
    }
}
