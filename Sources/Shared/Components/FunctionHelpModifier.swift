import SwiftUI

// MARK: - Public Extension

extension View {
    func functionHelp(title: String, text: String, autoDismiss: Double = 5.0) -> some View {
        modifier(FunctionHelpModifier(title: title, text: text, autoDismiss: autoDismiss, interactive: false))
    }

    func functionHelpInteractive(title: String, text: String, autoDismiss: Double = 5.0) -> some View {
        modifier(FunctionHelpModifier(title: title, text: text, autoDismiss: autoDismiss, interactive: true))
    }
}

// MARK: - FunctionHelpModifier

struct FunctionHelpModifier: ViewModifier {
    let title: String
    let text: String
    let autoDismiss: Double
    let interactive: Bool

    @State private var showingHelp = false
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                DottedBottomBorder()
            }
            .overlay(alignment: .top) {
                if showingHelp {
                    GeometryReader { proxy in
                        HelpTooltipCard(title: title, text: text)
                            .offset(y: proxy.size.height + 8)
                            .onTapGesture {}
                    }
                    .frame(height: 0)
                }
            }
            .simultaneousGesture(helpGesture)
            .onChange(of: showingHelp) { _, newValue in
                if newValue {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    scheduleAutoDismiss()
                } else {
                    cancelAutoDismiss()
                }
            }
    }

    private var helpGesture: some Gesture {
        let duration: Double = interactive ? 0.4 : 0.0
        return LongPressGesture(minimumDuration: duration)
            .onEnded { _ in showingHelp.toggle() }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismiss * 1_000_000_000))
            showingHelp = false
        }
    }

    private func cancelAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}

// MARK: - Dotted Bottom Border

struct DottedBottomBorder: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(.clear)
            .overlay {
                Capsule()
                    .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(.secondary.opacity(0.25))
            }
    }
}

// MARK: - Help Tooltip Card

struct HelpTooltipCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.caption2)
                .foregroundStyle(Color.surfacePrimary)
                .offset(y: 6)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .appFont(.caption)
                    .foregroundStyle(.primary)
                Text(text)
                    .appFont(.captionSmall)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 280)
            .glassBackground()
        }
        .appTransition()
    }
}
