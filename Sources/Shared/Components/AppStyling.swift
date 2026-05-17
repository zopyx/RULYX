import SwiftUI

// MARK: - Card Style

struct AppCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let style: AppCardStyleLevel
    let hasShadow: Bool

    enum AppCardStyleLevel {
        case standard
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
                if hasShadow {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.shadow(.drop(color: .black.opacity(0.06), radius: 4, y: 2)))
                        .opacity(0)
                }
            }
    }
}

extension View {
    func appCardStyle(cornerRadius: CGFloat = 16, style: AppCardStyle.AppCardStyleLevel = .standard, hasShadow: Bool = false) -> some View {
        modifier(AppCardStyle(cornerRadius: cornerRadius, style: style, hasShadow: hasShadow))
    }
}

// MARK: - Gradient Card

struct GradientCardStyle: ViewModifier {
    let gradient: LinearGradient
    let cornerRadius: CGFloat

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
    func gradientCardStyle(gradient: LinearGradient = .skySubtleGradient, cornerRadius: CGFloat = 16) -> some View {
        modifier(GradientCardStyle(gradient: gradient, cornerRadius: cornerRadius))
    }
}

// MARK: - Section Header Style

extension View {
    func sectionHeaderStyle() -> some View {
        font(.subheadline.weight(.semibold))
            .textCase(.none)
    }
}

// MARK: - Adaptive Background Colors

extension Color {
    static let cardBackground = Color(.secondarySystemFill)
    static let subtleBackground = Color(.tertiarySystemFill)
    static let appDivider = Color(.separator)
    static let iconBackground = Color(.quaternarySystemFill)
}

// MARK: - Typography System

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
    func appFont(_ style: AppTextStyle) -> some View {
        font(style.font)
    }
}

// MARK: - Reduce Motion Animation Helper

extension Animation {
    @MainActor
    static func appSpring(_ response: Double = 0.35, _ dampingFraction: Double = 0.8) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .default
        }
        return .interpolatingSpring(mass: 1, stiffness: 100 / response, damping: 20 * dampingFraction)
    }

    @MainActor
    static func appEaseInOut(duration: Double = 0.25) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .default
        }
        return .easeInOut(duration: duration)
    }
}

extension View {
    func appAnimation(_ animation: Animation? = .appSpring(), value: some Equatable) -> some View {
        self.animation(animation, value: value)
    }

    @ViewBuilder
    func appTransition(_ transition: AnyTransition = .opacity.combined(with: .scale(scale: 0.96))) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self.transition(.opacity)
        } else {
            self.transition(transition)
        }
    }

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
    func appButtonAccessibility(label: String, hint: String = "") -> some View {
        accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
    }
}
