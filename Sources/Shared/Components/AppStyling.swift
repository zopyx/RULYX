import SwiftUI

// MARK: - AppCardStyle

/// Applies a background fill and optional shadow to create a card appearance.
struct AppCardStyle: ViewModifier {
    /// Corner radius for the card shape.
    let cornerRadius: CGFloat
    /// Visual density of the card fill.
    let style: AppCardStyleLevel
    /// Whether to reserve space for a shadow.
    let hasShadow: Bool

    /// Determines the surface color for the card fill.
    enum AppCardStyleLevel {
        /// Standard card background.
        case standard
        /// Lighter, more subtle card background.
        case subtle

        var fill: Color {
            switch self {
            case .standard: .surfacePrimary
            case .subtle: .surfaceSecondary
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .background(style.fill, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .background {
                // Invisible shadow layer to allocate shadow space for smooth animation
                if hasShadow {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.shadow(.drop(color: .black.opacity(0.06), radius: 4, y: 2)))
                        .opacity(0)
                }
            }
    }
}

extension View {
    /// Apply a card-style background with the given corner radius, fill level, and optional shadow.
    func appCardStyle(cornerRadius: CGFloat = 16, style: AppCardStyle.AppCardStyleLevel = .standard, hasShadow: Bool = false) -> some View {
        modifier(AppCardStyle(cornerRadius: cornerRadius, style: style, hasShadow: hasShadow))
    }
}

// MARK: - GradientCardStyle

/// Applies a gradient fill with shadow for accent cards (e.g. summary cards).
struct GradientCardStyle: ViewModifier {
    /// The gradient to use as background.
    let gradient: LinearGradient
    /// Corner radius for the card shape.
    let cornerRadius: CGFloat

    // MARK: - ViewModifier

    func body(content: Content) -> some View {
        content
            .background(gradient, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.shadow(.drop(color: .black.opacity(0.08), radius: 6, y: 3)))
                    .opacity(0)
            }
    }
}

extension View {
    /// Apply a gradient card background with optional shadow.
    func gradientCardStyle(gradient: LinearGradient = .skySubtleGradient, cornerRadius: CGFloat = 16) -> some View {
        modifier(GradientCardStyle(gradient: gradient, cornerRadius: cornerRadius))
    }
}

// MARK: - Section Header Style

extension View {
    /// Apply standard section header styling: semibold subheadline, no uppercase.
    func sectionHeaderStyle() -> some View {
        font(.subheadline.weight(.semibold))
            .textCase(.none)
    }
}

// MARK: - Adaptive Background Colors

extension Color {
    /// Standard card background, adapts to light/dark mode.
    static let cardBackground = Color(.secondarySystemFill)
    static let subtleBackground = Color(.tertiarySystemFill)
    static let appDivider = Color(.separator)
    static let iconBackground = Color(.quaternarySystemFill)
}

// MARK: - AppTextStyle

/// Typography scale with semantic names for consistent text sizing across the app.
enum AppTextStyle {
    case largeTitle
    case title
    case heading
    case subheading
    case body
    case caption
    case captionSmall
    case statistic
    case label
    case buttonLabel

    var font: Font {
        switch self {
        case .largeTitle: .largeTitle.weight(.bold)
        case .title: .title2.weight(.bold)
        case .heading: .headline.weight(.semibold)
        case .subheading: .subheadline.weight(.semibold)
        case .body: .body
        case .caption: .caption.weight(.semibold)
        case .captionSmall: .caption2.weight(.semibold)
        case .statistic: .title3.weight(.semibold).monospacedDigit()
        case .label: .subheadline
        case .buttonLabel: .headline
        }
    }

    var uiTextStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title2
        case .heading: .headline
        case .subheading: .subheadline
        case .body: .body
        case .caption: .caption
        case .captionSmall: .caption2
        case .statistic: .title3
        case .label: .subheadline
        case .buttonLabel: .headline
        }
    }
}

extension View {
    /// Apply a named `AppTextStyle` font to the view.
    func appFont(_ style: AppTextStyle) -> some View {
        font(style.font)
    }
}

// MARK: - Reduce Motion Animation Helper

extension Animation {
    /// Spring animation that respects Reduce Motion accessibility setting.
    @MainActor
    static func appSpring(_ response: Double = 0.35, _ dampingFraction: Double = 0.8) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .default
        }
        return .interpolatingSpring(mass: 1, stiffness: 100 / response, damping: 20 * dampingFraction)
    }

    /// Ease-in-out animation that respects Reduce Motion.
    @MainActor
    static func appEaseInOut(duration: Double = 0.25) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .default
        }
        return .easeInOut(duration: duration)
    }
}

extension View {
    /// Conditionally apply animation based on Reduce Motion setting.
    func appAnimation(_ animation: Animation? = .appSpring(), value: some Equatable) -> some View {
        self.animation(animation, value: value)
    }

    /// Transition that falls back to plain opacity when Reduce Motion is enabled.
    @ViewBuilder
    func appTransition(_ transition: AnyTransition = .opacity.combined(with: .scale(scale: 0.96))) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self.transition(.opacity)
        } else {
            self.transition(transition)
        }
    }

    /// Scroll transition for iOS 18+ that fades and slightly scales non-identity phases.
    /// Disabled entirely when Reduce Motion is active.
    func appScrollTransition() -> some View {
        if UIAccessibility.isReduceMotionEnabled { return self }
        if #available(iOS 18, *) {
            return scrollTransition(.interactive, axis: .vertical) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.6)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
            }
        }
        return self
    }
}

// MARK: - Haptic Feedback Helper

extension View {
    /// Trigger a haptic feedback when the view is tapped.
    func hapticOnTap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        simultaneousGesture(
            TapGesture().onEnded { _ in
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            }
        )
    }
}

// MARK: - Accessibility Helpers

extension View {
    /// Convenience modifier to mark a view as a button with label and hint.
    func appButtonAccessibility(label: String, hint: String = "") -> some View {
        accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
    }
}
