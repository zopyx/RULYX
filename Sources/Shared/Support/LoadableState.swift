import Foundation

// MARK: - LoadableState

/// A type-safe state machine for async data loading with four states: idle, loading, loaded, failed.
///
/// Use cases:
/// - `viewModel.state.startLoading()` at the beginning of a fetch
/// - `viewModel.state.succeed(with: value)` on success
/// - `viewModel.state.fail(with: error)` on failure
/// - Check `isLoaded`, `isLoading`, `value`, `error` in views
enum LoadableState<Value: Sendable> {
    /// Initial state before loading begins.
    case idle
    /// A load operation is in progress.
    case loading
    /// Data loaded successfully.
    case loaded(Value)
    /// Loading failed with an error.
    case failed(AppError)

    /// The loaded value, if any.
    var value: Value? {
        if case let .loaded(v) = self { v } else { nil }
    }

    /// Whether the state is `.loaded`.
    var isLoaded: Bool {
        if case .loaded = self { true } else { false }
    }

    /// Whether the state is `.loading`.
    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    /// The error if the state is `.failed`.
    var error: AppError? {
        if case let .failed(e) = self { e } else { nil }
    }

    /// Transition to `.loading`.
    mutating func startLoading() {
        self = .loading
    }

    /// Transition to `.loaded` with the given value.
    mutating func succeed(with value: Value) {
        self = .loaded(value)
    }

    /// Transition to `.failed` with the given error.
    mutating func fail(with error: AppError) {
        self = .failed(error)
    }
}
