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

    private var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: "klipyAPIKey")
        return key?.isEmpty == true ? nil : key
    }

    func search(query: String) async throws -> [GIFResult] {
        guard let apiKey else { throw GIFError.missingAPIKey }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "\(baseURL)/\(apiKey)/gifs/search?q=\(encoded)&per_page=\(perPage)&format_filter=mp4,gif")!
        let (data, _) = try await httpClient.data(from: url)
        let decoded = try JSONDecoder().decode(KlipyResponse.self, from: data)
        return decoded.data.data.map { $0.toGIFResult() }
    }

    func trending() async throws -> [GIFResult] {
        guard let apiKey else { throw GIFError.missingAPIKey }
        let url = URL(string: "\(baseURL)/\(apiKey)/gifs/trending?per_page=\(perPage)&format_filter=mp4,gif")!
        let (data, _) = try await httpClient.data(from: url)
        let decoded = try JSONDecoder().decode(KlipyResponse.self, from: data)
        return decoded.data.data.map { $0.toGIFResult() }
    }

    func downloadGIF(url: String) async throws -> Data {
        guard let url = URL(string: url) else { throw GIFError.networkError("Invalid URL") }
        let (data, _) = try await httpClient.data(from: url)
        return data
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
