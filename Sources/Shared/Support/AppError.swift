import Foundation

enum AppErrorCategory: String, Equatable {
    case authentication
    case network
    case decoding
    case validation
    case server
    case cancellation
    case unknown
}

struct AppError: LocalizedError, Equatable {
    let category: AppErrorCategory
    let message: String

    var errorDescription: String? {
        message
    }

    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if isCancellation(error) {
            return AppError(category: .cancellation, message: "The request was cancelled.")
        }

        if let apiError = error as? BlueskyAPIError {
            switch apiError {
            case .invalidURL:
                return AppError(category: .validation, message: apiError.localizedDescription)
            case .invalidResponse:
                return AppError(category: .decoding, message: apiError.localizedDescription)
            case .unauthorized, .missingCredentials:
                return AppError(category: .authentication, message: apiError.localizedDescription)
            case .sslPinFailure:
                return AppError(category: .network, message: apiError.localizedDescription)
            case .server:
                return AppError(category: .server, message: apiError.localizedDescription)
            }
        }

        if error is DecodingError {
            return AppError(
                category: .decoding,
                message: "The app could not understand the Bluesky response."
            )
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return AppError(category: .cancellation, message: "The request was cancelled.")
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost:
                return AppError(
                    category: .network,
                    message: "Network connection failed. Check connectivity and try again."
                )
            default:
                return AppError(category: .network, message: urlError.localizedDescription)
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return AppError(category: .network, message: nsError.localizedDescription)
        }

        return AppError(category: .unknown, message: error.localizedDescription)
    }

    static func userMessage(from error: Error) -> String {
        from(error).message
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        return nsError.localizedDescription.localizedCaseInsensitiveContains("cancelled")
    }
}
