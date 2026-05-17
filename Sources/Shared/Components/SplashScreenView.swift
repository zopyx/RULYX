import SwiftUI

struct SplashScreenView: View {
    @Binding var isActive: Bool
    var showDismissButton = false
    var dismissAutomatically = true

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    @State private var phase = 0
    @State private var logoScale: CGFloat = 1
    @State private var logoGlow: CGFloat = 0
    @State private var logoBreathing: CGFloat = 1
    @State private var taglineOpacity: CGFloat = 0
    @State private var taglineOffset: CGFloat = 24
    @State private var subtaglineOpacity: CGFloat = 0
    @State private var subtaglineOffset: CGFloat = 16
    @State private var footerOpacity: CGFloat = 0
    @State private var showParticles = false

    private var buildDate: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let url = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.modificationDate] as? Date
        {
            return formatter.string(from: date)
        }
        return "Unknown"
    }

    var body: some View {
        ZStack {
            SplashBackground()
                .ignoresSafeArea()

            StarField()
                .opacity(showParticles ? 0.8 : 0)

            VStack(spacing: 0) {
                if showDismissButton {
                    HStack {
                        Spacer()
                        Button {
                            isActive = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(16)
                        .opacity(phase >= 2 ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.5), value: phase)
                    }
                }

                Spacer()

                Image("RulyxLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 240)
                    .scaleEffect(logoScale * logoBreathing)
                    .shadow(color: .blue.opacity(logoGlow * 0.5), radius: logoGlow * 50)
                    .shadow(color: .purple.opacity(logoGlow * 0.25), radius: logoGlow * 70)
                    .shadow(color: .cyan.opacity(logoGlow * 0.15), radius: logoGlow * 90)

                Spacer().frame(height: 16)

                Text(verbatim: loc("splash.tagline"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: taglineOffset)
                    .opacity(taglineOpacity)

                Spacer().frame(height: 16)

                Text(verbatim: loc("splash.subtagline"))
                    .font(.caption.weight(.regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .offset(y: subtaglineOffset)
                    .opacity(subtaglineOpacity)

                Spacer()

                Text(verbatim: "Build: \(buildDate)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .opacity(footerOpacity)
                    .padding(.bottom, 44)
            }
            .padding()
        }
        .task {
            if reduceMotion {
                isActive = false
                return
            }
            await animate()
        }
    }

    private func animate() async {
        withAnimation(.easeOut(duration: 0.8)) {
            showParticles = true
        }

        try? await Task.sleep(for: .seconds(0.3))

        withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
            logoGlow = 1
        }

        try? await Task.sleep(for: .seconds(1.2))

        withAnimation(.easeOut(duration: 0.6)) {
            taglineOffset = 0
            taglineOpacity = 1
        }

        try? await Task.sleep(for: .seconds(0.2))

        withAnimation(.easeOut(duration: 0.5)) {
            subtaglineOffset = 0
            subtaglineOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            footerOpacity = 1
        }

        phase = 2

        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(1.0)) {
            logoBreathing = 1.03
        }

        if dismissAutomatically {
            try? await Task.sleep(for: .seconds(3.0))

            withAnimation(.easeOut(duration: 0.3)) {
                isActive = false
            }
        }
    }
}

// MARK: - Animated Background

private struct SplashBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                Color(red: 0.02, green: 0.06, blue: 0.22)

                let t = timeline.date.timeIntervalSince1970

                SplashOrb(
                    color: Color(red: 0.1, green: 0.4, blue: 0.95).opacity(0.5),
                    position: CGPoint(
                        x: cos(t * 0.2) * 0.35 + 0.5,
                        y: sin(t * 0.25) * 0.35 + 0.5
                    ),
                    size: 300
                )

                SplashOrb(
                    color: Color(red: 0.05, green: 0.65, blue: 0.7).opacity(0.35),
                    position: CGPoint(
                        x: cos(t * 0.3 + 2.5) * 0.35 + 0.5,
                        y: sin(t * 0.2 + 1.2) * 0.35 + 0.5
                    ),
                    size: 250
                )

                SplashOrb(
                    color: Color(red: 0.5, green: 0.15, blue: 0.85).opacity(0.3),
                    position: CGPoint(
                        x: cos(t * 0.15 + 4.8) * 0.35 + 0.5,
                        y: sin(t * 0.35 + 3.1) * 0.35 + 0.5
                    ),
                    size: 220
                )

                SplashOrb(
                    color: Color(red: 0.9, green: 0.3, blue: 0.4).opacity(0.12),
                    position: CGPoint(
                        x: cos(t * 0.22 + 1.7) * 0.3 + 0.5,
                        y: sin(t * 0.28 + 0.8) * 0.3 + 0.5
                    ),
                    size: 180
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct SplashOrb: View {
    let color: Color
    let position: CGPoint
    let size: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .blur(radius: 80)
                .position(
                    x: position.x * geometry.size.width,
                    y: position.y * geometry.size.height
                )
        }
    }
}

// MARK: - Star Particles

private struct StarField: View {
    private let stars: [Star] = (0 ..< 60).map { _ in
        Star(
            x: Double.random(in: 0 ... 1),
            y: Double.random(in: 0 ... 1),
            size: Double.random(in: 1.0 ... 3.5),
            speed: Double.random(in: 0.02 ... 0.08),
            twinkleSpeed: Double.random(in: 0.5 ... 2.5),
            twinklePhase: Double.random(in: 0 ... 6.28),
            baseOpacity: Double.random(in: 0.2 ... 0.8)
        )
    }

    private struct Star {
        let x: Double
        let y: Double
        let size: Double
        let speed: Double
        let twinkleSpeed: Double
        let twinklePhase: Double
        let baseOpacity: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince1970

                for star in stars {
                    let driftY = star.y + sin(t * star.speed + star.twinklePhase) * 0.04
                    let normalizedY = driftY.truncatingRemainder(dividingBy: 1.0)
                    let xPos = star.x * size.width
                    let yPos = normalizedY * size.height

                    let twinkle = (sin(t * star.twinkleSpeed + star.twinklePhase) + 1) * 0.5
                    let alpha = star.baseOpacity * (0.3 + twinkle * 0.7)

                    let dotSize = star.size * (0.8 + twinkle * 0.4)
                    let rect = CGRect(
                        x: xPos - dotSize / 2,
                        y: yPos - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )

                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}
