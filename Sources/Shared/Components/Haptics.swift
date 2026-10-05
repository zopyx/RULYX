import UIKit

// MARK: - Haptics

/// The single entry point for haptic feedback.
///
/// Generators used to be built at each call site (14 of them, with styles spread across
/// `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator` and
/// `UINotificationFeedbackGenerator`), so the feel of the app could not be tuned or audited in
/// one place. Everything now goes through here.
///
/// The whole enum is `@MainActor`: UIKit's `impactOccurred()`/`selectionChanged()`/
/// `notificationOccurred()` are main-actor isolated, and calling them from a nonisolated context
/// is a strict-concurrency warning (an error once the Swift 6 language mode is enforced).
///
/// The two-phase variants exist because a generator that is `prepare()`d before an `await`
/// fires with noticeably lower latency — account switching keeps that behaviour.
@MainActor
enum Haptics {
    /// A short impact: row taps, toggles, drag handles.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        preparedImpact(style).impactOccurred()
    }

    /// A selection change: account cycling, segmented control changes.
    static func selection() {
        preparedSelection().selectionChanged()
    }

    /// A success notification: a batch operation or export finished.
    static func success() {
        preparedNotification().notificationOccurred(.success)
    }

    /// A warning notification.
    static func warning() {
        preparedNotification().notificationOccurred(.warning)
    }

    /// An error notification.
    static func error() {
        preparedNotification().notificationOccurred(.error)
    }

    /// An impact generator that is already spinning — fire it after an `await`.
    static func preparedImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> UIImpactFeedbackGenerator {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        return generator
    }

    /// A selection generator that is already spinning — fire it after an `await`.
    static func preparedSelection() -> UISelectionFeedbackGenerator {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }

    /// A notification generator that is already spinning — fire it after an `await`.
    static func preparedNotification() -> UINotificationFeedbackGenerator {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }
}
