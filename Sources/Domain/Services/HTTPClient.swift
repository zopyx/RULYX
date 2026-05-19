import Foundation

struct HTTPClient {
    private let session: URLSession
    private let debugStore: HTTPRequestDebugStore?

    init(session: URLSession = .shared, debugStore: HTTPRequestDebugStore? = HTTPRequestDebugStore.shared) {
        self.session = session
        self.debugStore = debugStore
    }

    func data(
        for request: URLRequest,
        source: String? = nil,
        origin: String? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let entryID = await debugStore?.begin(
            request: request,
            source: source,
            origin: origin ?? Self.makeOrigin(fileID: originFileID, function: originFunction, line: originLine)
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    errorMessage: AppError.userMessage(from: BlueskyAPIError.invalidResponse)
                )
                throw BlueskyAPIError.invalidResponse
            }
            if (200 ..< 300).contains(httpResponse.statusCode) {
                await debugStore?.succeed(id: entryID ?? UUID(), statusCode: httpResponse.statusCode)
            } else {
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    statusCode: httpResponse.statusCode,
                    errorMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    errorResponseJSON: Self.prettyPrintedJSON(from: data)
                )
            }
            return (data, httpResponse)
        } catch {
            await debugStore?.fail(
                id: entryID ?? UUID(),
                errorMessage: AppError.userMessage(from: error)
            )
            throw error
        }
    }

    func data(
        from url: URL,
        source: String? = nil,
        origin: String? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (Data, HTTPURLResponse) {
        try await data(
            for: URLRequest(url: url),
            source: source,
            origin: origin,
            originFileID: originFileID,
            originFunction: originFunction,
            originLine: originLine
        )
    }

    func download(
        for request: URLRequest,
        source: String? = nil,
        origin: String? = nil,
        originFileID: String = #fileID,
        originFunction: String = #function,
        originLine: Int = #line
    ) async throws -> (URL, HTTPURLResponse) {
        var request = request
        request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
        let entryID = await debugStore?.begin(
            request: request,
            source: source,
            origin: origin ?? Self.makeOrigin(fileID: originFileID, function: originFunction, line: originLine)
        )
        do {
            let (fileURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    errorMessage: AppError.userMessage(from: BlueskyAPIError.invalidResponse)
                )
                throw BlueskyAPIError.invalidResponse
            }
            if (200 ..< 300).contains(httpResponse.statusCode) {
                await debugStore?.succeed(id: entryID ?? UUID(), statusCode: httpResponse.statusCode)
            } else {
                let responseData = try? Data(contentsOf: fileURL)
                await debugStore?.fail(
                    id: entryID ?? UUID(),
                    statusCode: httpResponse.statusCode,
                    errorMessage: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    errorResponseJSON: responseData.flatMap(Self.prettyPrintedJSON(from:))
                )
            }
            return (fileURL, httpResponse)
        } catch {
            await debugStore?.fail(
                id: entryID ?? UUID(),
                errorMessage: AppError.userMessage(from: error)
            )
            throw error
        }
    }

    private static func makeOrigin(fileID: String, function: String, line: Int) -> String {
        "\(fileID):\(line) \(function)"
    }

    private static func prettyPrintedJSON(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: prettyData, encoding: .utf8)
        else {
            return nil
        }
        return string
    }
}
