import SwiftUI

// MARK: - Brand Palette

extension Color {
    /// Primary brand blue — adapts to light/dark mode.
    static let skyPrimary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.65, blue: 1.00, alpha: 1.0)
            : UIColor(red: 0.07, green: 0.53, blue: 0.98, alpha: 1.0)
    })

    /// Accent cyan-teal — adapts to light/dark mode.
    static let skyAccent = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.88, blue: 0.92, alpha: 1.0)
            : UIColor(red: 0.02, green: 0.78, blue: 0.82, alpha: 1.0)
    })

    /// Orange accent tone.
    static let skyOrange = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.60, blue: 0.18, alpha: 1.0)
    })

    /// Purple accent tone.
    static let skyPurple = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.75, green: 0.45, blue: 0.95, alpha: 1.0)
            : UIColor(red: 0.70, green: 0.35, blue: 0.90, alpha: 1.0)
    })
}

// MARK: - Semantic Colors

extension Color {
    /// Positive/green for success states.
    static let successGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.78, blue: 0.35, alpha: 1.0)
            : UIColor(red: 0.18, green: 0.67, blue: 0.28, alpha: 1.0)
    })

    /// Orange for warning states.
    static let warningOrange = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0)
            : UIColor(red: 0.85, green: 0.50, blue: 0.08, alpha: 1.0)
    })

    /// Red for error/destructive states.
    static let errorRed = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
            : UIColor(red: 0.80, green: 0.20, blue: 0.15, alpha: 1.0)
    })

    /// Informational blue (alias for `skyPrimary`).
    static let infoBlue = Color.skyPrimary
}

// MARK: - Surface Colors

extension Color {
    /// Primary surface background (white in light, dark gray in dark mode).
    static let surfacePrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    })

    /// Secondary surface fill (subtle gray tint).
    static let surfaceSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
    })

    /// Tertiary surface fill (darker tint for deeper backgrounds).
    static let surfaceTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            : UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
    })
}

// MARK: - Semantic Surface Helpers

extension Color {
    /// Surface color for a given card style level.
    static func surface(for style: AppCardStyle.AppCardStyleLevel) -> Color {
        switch style {
        case .standard: .surfacePrimary
        case .subtle: .surfaceSecondary
        }
    }

    /// Tint variant (12% opacity) of the given color.
    static func tint(for color: Color) -> Color {
        color.opacity(0.12)
    }
}

// MARK: - Gradients

extension LinearGradient {
    /// Primary blue-to-cyan gradient.
    static let skyPrimaryGradient = LinearGradient(
        colors: [Color.skyPrimary, Color.skyAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle version of the primary gradient (low opacity).
    static let skySubtleGradient = LinearGradient(
        colors: [Color.skyPrimary.opacity(0.14), Color.skyAccent.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Top-to-bottom highlight gradient for card overlays.
    static let cardHighlight = LinearGradient(
        colors: [Color.skyPrimary.opacity(0.10), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Card surface gradient with a subtle brand tint.
    static let cardSurfaceGradient = LinearGradient(
        colors: [Color.surfacePrimary, Color.skyPrimary.opacity(0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent card gradient with brand tones.
    static let cardAccentGradient = LinearGradient(
        colors: [Color.skyPrimary.opacity(0.16), Color.skyAccent.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Create a semantic gradient from any color (14% → 4% opacity).
    static func semanticGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.14), color.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
