# FunctionHelpModifier Implementation

Create `/Users/ajung/src/RULYX/Sources/Shared/Components/FunctionHelpModifier.swift` with the following content:

```swift
import SwiftUI

// MARK: - Public Extension

extension View {
    @ViewBuilder
    func functionHelp(title: String, text: String, autoDismiss: Double = 5.0) -> some View {
        modifier(FunctionHelpModifier(title: title, text: text, autoDismiss: autoDismiss, interactive: false))
    }

    @ViewBuilder
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
                            .onTapGesture { }
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
        if interactive {
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    showingHelp.toggle()
                }
        } else {
            TapGesture()
                .onEnded {
                    showingHelp.toggle()
                }
        }
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
                .foregroundStyle(.surfacePrimary)
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
```

## What it does

| Feature | Detail |
|---|---|
| **Indicator** | Faint dotted underline (`.secondary.opacity(0.25)`) on any view |
| **Gesture** | `TapGesture` for static labels, `LongPressGesture(0.4s)` for buttons/controls |
| **Tooltip** | Glass card with up-arrow, title + description, max 280pt width |
| **Dismiss** | Tap source again, or auto-dismiss after 5s configurable timer |
| **Haptic** | Light impact on appear |
| **Accessibility** | Uses appFont, glassBackground, appTransition — consistent with existing codebase |

## Usage

```swift
// Static label (section title, etc.)
Text(verbatim: loc("list.compare.title"))
    .functionHelp(title: loc("list.compare.help_title"),
                  text: loc("list.compare.help_text"))

// Interactive element (button, DisclosureGroup)
Button { ... } label: { ... }
    .functionHelpInteractive(title: loc("list.compare.help_title"),
                             text: loc("list.compare.help_text"))
```

## Testing

Run `xcodegen generate && xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` to verify compilation.
