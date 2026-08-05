import Foundation

/// A Sendable box for a NotificationCenter observer token.
///
/// `@MainActor @Observable` view models need to unregister their observer from
/// `deinit` (nonisolated in Swift 6). `nonisolated(unsafe)` on a mutable stored
/// property is not honored by the `@Observable` macro (it warns "has no
/// effect"), so the token is boxed in a `@unchecked Sendable` class instead:
/// an immutable `let` of Sendable type is freely readable from `deinit`.
final class ObserverTokenBox: @unchecked Sendable {
    var token: NSObjectProtocol?

    init() {}
}
