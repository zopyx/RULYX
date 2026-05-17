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

enum GIFProvider: String, CaseIterable, Identifiable {
    case giphy = "GIPHY"
    case tenor = "Tenor"
    case imgur = "Imgur"

    var id: String { rawValue }

    var apiKeyUserDefaultsKey: String {
        "gifProviderAPIKey_\(rawValue.lowercased())"
    }
}

enum GIFError: LocalizedError {
    case missingAPIKey(String)
    case networkError(String)
    case noResults

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider): "\(provider) API key not configured. Add it in Settings."
        case let .networkError(msg): msg
        case .noResults: "No GIFs found"
        }
    }
}

final class GIFService: Sendable {
    static let shared = GIFService()

    private var session: URLSession { URLSession.shared }

    func search(query: String, provider: GIFProvider) async throws -> [GIFResult] {
        switch provider {
        case .giphy: try await searchGIPHY(query: query)
        case .tenor: try await searchTenor(query: query)
        case .imgur: try await searchImgur(query: query)
        }
    }

    func trending(provider: GIFProvider) async throws -> [GIFResult] {
        switch provider {
        case .giphy: try await trendingGIPHY()
        case .tenor: try await trendingTenor()
        case .imgur: try await trendingImgur()
        }
    }

    private func searchGIPHY(query: String) async throws -> [GIFResult] {
        guard let apiKey = apiKey(for: .giphy) else { throw GIFError.missingAPIKey("GIPHY") }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://api.giphy.com/v1/gifs/search?api_key=\(apiKey)&q=\(encoded)&limit=25&rating=pg13")!
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(GIPHYResponse.self, from: data)
        return decoded.data.map { gif in
            GIFResult(
                id: gif.id,
                mp4URL: gif.images?.original?.mp4 ?? "",
                previewURL: gif.images?.fixedWidth?.url ?? gif.images?.original?.url ?? "",
                width: Int(gif.images?.original?.width ?? "0") ?? 0,
                height: Int(gif.images?.original?.height ?? "0") ?? 0,
                title: gif.title ?? ""
            )
        }
    }

    private func trendingGIPHY() async throws -> [GIFResult] {
        guard let apiKey = apiKey(for: .giphy) else { throw GIFError.missingAPIKey("GIPHY") }
        let url = URL(string: "https://api.giphy.com/v1/gifs/trending?api_key=\(apiKey)&limit=25&rating=pg13")!
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(GIPHYResponse.self, from: data)
        return decoded.data.map { gif in
            GIFResult(
                id: gif.id,
                mp4URL: gif.images?.original?.mp4 ?? "",
                previewURL: gif.images?.fixedWidth?.url ?? gif.images?.original?.url ?? "",
                width: Int(gif.images?.original?.width ?? "0") ?? 0,
                height: Int(gif.images?.original?.height ?? "0") ?? 0,
                title: gif.title ?? ""
            )
        }
    }

    private func searchTenor(query: String) async throws -> [GIFResult] {
        guard let apiKey = apiKey(for: .tenor) else { throw GIFError.missingAPIKey("Tenor") }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://tenor.googleapis.com/v2/search?q=\(encoded)&key=\(apiKey)&limit=25")!
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(TenorResponse.self, from: data)
        return decoded.results?.map { gif in
            let mp4 = gif.mediaFormats?.first(where: { $0.url?.hasSuffix(".mp4") == true }) ?? gif.mediaFormats?.first
            let preview = gif.mediaFormats?.first(where: { $0.url?.hasSuffix(".gif") == true }) ?? mp4
            return GIFResult(
                id: gif.id ?? "",
                mp4URL: mp4?.url ?? "",
                previewURL: preview?.url ?? "",
                width: Int(gif.width ?? "0") ?? 0,
                height: Int(gif.height ?? "0") ?? 0,
                title: gif.title ?? ""
            )
        } ?? []
    }

    private func trendingTenor() async throws -> [GIFResult] {
        guard let apiKey = apiKey(for: .tenor) else { throw GIFError.missingAPIKey("Tenor") }
        let url = URL(string: "https://tenor.googleapis.com/v2/featured?key=\(apiKey)&limit=25")!
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(TenorResponse.self, from: data)
        return decoded.results?.map { gif in
            let mp4 = gif.mediaFormats?.first(where: { $0.url?.hasSuffix(".mp4") == true }) ?? gif.mediaFormats?.first
            let preview = gif.mediaFormats?.first(where: { $0.url?.hasSuffix(".gif") == true }) ?? mp4
            return GIFResult(
                id: gif.id ?? "",
                mp4URL: mp4?.url ?? "",
                previewURL: preview?.url ?? "",
                width: Int(gif.width ?? "0") ?? 0,
                height: Int(gif.height ?? "0") ?? 0,
                title: gif.title ?? ""
            )
        } ?? []
    }

    private func searchImgur(query: String) async throws -> [GIFResult] {
        guard let clientID = apiKey(for: .imgur) else { throw GIFError.missingAPIKey("Imgur") }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://api.imgur.com/3/gallery/search/time/all/0?q=\(encoded)")!
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(ImgurGalleryResponse.self, from: data)
        return decoded.data?.compactMap { item in
            guard !(item.isAlbum ?? false), let id = item.id, let link = item.mp4 ?? item.link, !link.isEmpty else { return nil }
            return GIFResult(
                id: id,
                mp4URL: item.mp4 ?? link,
                previewURL: item.link ?? link,
                width: item.width ?? 0,
                height: item.height ?? 0,
                title: item.title ?? ""
            )
        } ?? []
    }

    private func trendingImgur() async throws -> [GIFResult] {
        guard let clientID = apiKey(for: .imgur) else { throw GIFError.missingAPIKey("Imgur") }
        let url = URL(string: "https://api.imgur.com/3/gallery/hot/viral/0.json")!
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(ImgurGalleryResponse.self, from: data)
        return decoded.data?.compactMap { item in
            guard !(item.isAlbum ?? false), let id = item.id, let link = item.mp4 ?? item.link, !link.isEmpty else { return nil }
            return GIFResult(
                id: id,
                mp4URL: item.mp4 ?? link,
                previewURL: item.link ?? link,
                width: item.width ?? 0,
                height: item.height ?? 0,
                title: item.title ?? ""
            )
        } ?? []
    }

    func downloadGIF(url: String) async throws -> Data {
        guard let url = URL(string: url) else { throw GIFError.networkError("Invalid URL") }
        let (data, _) = try await session.data(from: url)
        return data
    }

    private func apiKey(for provider: GIFProvider) -> String? {
        let key = UserDefaults.standard.string(forKey: provider.apiKeyUserDefaultsKey)
        return key?.isEmpty == true ? nil : key
    }
}

// MARK: - GIPHY Response Models

private struct GIPHYResponse: Decodable {
    let data: [GIPHYGIF]
}

private struct GIPHYGIF: Decodable {
    let id: String
    let title: String?
    let images: GIPHYImages?
}

private struct GIPHYImages: Decodable {
    let original: GIPHYImage?
    let fixedWidth: GIPHYImage?

    enum CodingKeys: String, CodingKey {
        case original
        case fixedWidth = "fixed_width"
    }
}

private struct GIPHYImage: Decodable {
    let url: String?
    let mp4: String?
    let width: String?
    let height: String?
}

// MARK: - Tenor Response Models

private struct TenorResponse: Decodable {
    let results: [TenorGIF]?
}

private struct TenorGIF: Decodable {
    let id: String?
    let title: String?
    let mediaFormats: [TenorMediaFormat]?
    let width: String?
    let height: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case mediaFormats = "media_formats"
        case width
        case height
    }
}

private struct TenorMediaFormat: Decodable {
    let url: String?
    let dims: [Int]?
}

// MARK: - Imgur Response Models

private struct ImgurGalleryResponse: Decodable {
    let data: [ImgurGalleryItem]?
}

private struct ImgurGalleryItem: Decodable {
    let id: String?
    let title: String?
    let link: String?
    let mp4: String?
    let width: Int?
    let height: Int?
    let isAlbum: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, link, mp4, width, height
        case isAlbum = "is_album"
    }
}
