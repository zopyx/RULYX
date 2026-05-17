import SwiftUI

// MARK: - Brand Palette

extension Color {
    static let skyPrimary = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.65, blue: 1.00, alpha: 1.0)
            : UIColor(red: 0.07, green: 0.53, blue: 0.98, alpha: 1.0)
    })

    static let skyAccent = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.88, blue: 0.92, alpha: 1.0)
            : UIColor(red: 0.02, green: 0.78, blue: 0.82, alpha: 1.0)
    })

    static let skyOrange = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.60, blue: 0.18, alpha: 1.0)
    })

    static let skyPurple = Color(uiColor: UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.75, green: 0.45, blue: 0.95, alpha: 1.0)
            : UIColor(red: 0.70, green: 0.35, blue: 0.90, alpha: 1.0)
    })
}

// MARK: - Semantic Colors

extension Color {
    static let successGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.78, blue: 0.35, alpha: 1.0)
            : UIColor(red: 0.18, green: 0.67, blue: 0.28, alpha: 1.0)
    })

    static let warningOrange = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0)
            : UIColor(red: 0.85, green: 0.50, blue: 0.08, alpha: 1.0)
    })

    static let errorRed = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
            : UIColor(red: 0.80, green: 0.20, blue: 0.15, alpha: 1.0)
    })

    static let infoBlue = Color.skyPrimary
}

// MARK: - Surface Colors

extension Color {
    static let surfacePrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    })

    static let surfaceSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
    })

    static let surfaceTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            : UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
    })
}

// MARK: - Semantic Surface Helpers

extension Color {
    static func surface(for style: AppCardStyle.AppCardStyleLevel) -> Color {
        switch style {
        case .standard: .surfacePrimary
        case .subtle: .surfaceSecondary
        }
    }

    static func tint(for color: Color) -> Color {
        color.opacity(0.12)
    }
}

// MARK: - Gradients

extension LinearGradient {
    static let skyPrimaryGradient = LinearGradient(
        colors: [Color.skyPrimary, Color.skyAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let skySubtleGradient = LinearGradient(
        colors: [Color.skyPrimary.opacity(0.14), Color.skyAccent.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardHighlight = LinearGradient(
        colors: [Color.skyPrimary.opacity(0.10), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardSurfaceGradient = LinearGradient(
        colors: [Color.surfacePrimary, Color.skyPrimary.opacity(0.07)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardAccentGradient = LinearGradient(
        colors: [Color.skyPrimary.opacity(0.16), Color.skyAccent.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func semanticGradient(for color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.14), color.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
