import Foundation

// MARK: - AppErrorCategory

/// Broad category for an error, used for user-facing messaging and analytics.
enum AppErrorCategory: String, Equatable {
    /// Authentication failures (invalid credentials, unauthorized).
    case authentication
    /// Network connectivity errors.
    case network
    /// Response parsing or data decoding errors.
    case decoding
    /// Input validation errors.
    case validation
    /// Server-side errors.
    case server
    /// Request was cancelled.
    case cancellation
    /// Uncategorized errors.
    case unknown
}

// MARK: - AppError

/// Normalized error type used throughout the app.
/// Converts various error types (`URLError`, `BlueskyAPIError`, `DecodingError`, etc.)
/// into a consistent `category` + `message` format via `AppError.from(_:)`.
struct AppError: LocalizedError, Equatable {
    /// The broad category of the error.
    let category: AppErrorCategory
    /// User-facing error message.
    let message: String

    var errorDescription: String? {
        message
    }

    // MARK: - Public

    // MARK: - Public

    /// Convert any `Error` to an `AppError`, categorizing it appropriately.
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
            case .deactivated:
                return AppError(category: .authentication, message: apiError.localizedDescription)
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

    /// Extract a user-facing message string from any error.
    static func userMessage(from error: Error) -> String {
        from(error).message
    }

    /// Check whether an error represents a cancellation (Swift `CancellationError` or `URLError.cancelled`).
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
