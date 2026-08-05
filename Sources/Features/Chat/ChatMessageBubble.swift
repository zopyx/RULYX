import SwiftUI

// MARK: - ChatMessageBubble

/// A single chat message bubble with mention link detection, reactions,
/// and a tail shape that flips for outgoing vs. incoming messages.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let isOutgoing: Bool
    var currentUserDID: String?
    var onOpenProfile: ((String) -> Void)?
    var onRetry: (() -> Void)?
    var onReact: ((String) -> Void)?
    /// Whether this bubble's reaction picker popup is currently shown.
    var isReactionPickerPresented = false
    /// Long-press handler asking the parent to show/hide this bubble's picker.
    var onToggleReactionPicker: (() -> Void)?
    /// Dismisses the picker after an action (react/copy) was taken.
    var onDismissReactionPicker: (() -> Void)?

    /// Quick-pick emojis offered in the reaction picker popup.
    private static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    private var isPending: Bool {
        message.id.hasPrefix("pending-")
    }

    private var hasFailed: Bool {
        message.rev == "failed"
    }

    /// Shared time-only formatter for timestamps.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
        return f
    }()

    /// Formatted time string for the message timestamp.
    private var timeString: String {
        Self.timeFormatter.string(from: message.sentAt)
    }

    // MARK: - Body

    var body: some View {
        HStack {
            if isOutgoing {
                Spacer(minLength: 60)
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(mentionAttributedString(from: message.text, isOutgoing: isOutgoing))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "mention", let handle = url.host {
                            onOpenProfile?(handle)
                            return .handled
                        }
                        return .systemAction
                    })

                HStack(spacing: 4) {
                    if isPending {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(isOutgoing ? .white.opacity(0.9) : Color(.secondaryLabel))
                    }

                    if hasFailed {
                        Button {
                            onRetry?()
                        } label: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.errorRed)
                        }
                    }

                    if !message.reactions.isEmpty {
                        let grouped = Dictionary(grouping: message.reactions, by: { $0.value })
                        ForEach(Array(grouped.keys.sorted()), id: \.self) { emoji in
                            HStack(spacing: 2) {
                                Text(emoji)
                                    .font(.caption2)
                                if grouped[emoji]!.count > 1 {
                                    Text("\(grouped[emoji]!.count)")
                                        .font(.caption2.weight(.semibold))
                                }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.ultraThinMaterial))
                        }
                    }

                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(isOutgoing ? .white.opacity(0.9) : Color(.secondaryLabel))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOutgoing ? Color.chatBubbleOutgoing : Color(.systemGray5))
            .opacity(isPending ? 0.6 : 1.0)
            .clipShape(BubbleShape(isOutgoing: isOutgoing))
            .contentShape(BubbleShape(isOutgoing: isOutgoing))
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !isPending, !hasFailed, onReact != nil else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleReactionPicker?()
            }

            if !isOutgoing {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .overlay {
            if isReactionPickerPresented {
                reactionPickerPopup
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    /// Compact two-row popup: quick-pick emoji row plus a copy row.
    private var reactionPickerPopup: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(Self.quickReactions, id: \.self) { emoji in
                    Button {
                        onReact?(emoji)
                        onDismissReactionPicker?()
                    } label: {
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background {
                                if hasReacted(emoji) {
                                    Circle().fill(Color.skyPrimary.opacity(0.25))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
                .padding(.vertical, 4)

            Button {
                UIPasteboard.general.string = message.text
                onDismissReactionPicker?()
            } label: {
                Label(loc("post.copy"), systemImage: "doc.on.doc")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.skyPrimary)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    /// Whether the current account already reacted to this message with `emoji`.
    private func hasReacted(_ emoji: String) -> Bool {
        guard let currentUserDID else { return false }
        return message.reactions.contains { $0.value == emoji && $0.senderDID == currentUserDID }
    }

    /// Converts @mentions in the text to tappable links with a custom mention:// scheme.
    private func mentionAttributedString(from text: String, isOutgoing: Bool) -> AttributedString {
        var attributed = AttributedString(text)
        guard let regex = try? NSRegularExpression(pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?")
        else { return attributed }
        let nsRange = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: nsRange).reversed() {
            guard let range = Range(match.range, in: text),
                  let attrRange = Range(match.range, in: attributed) else { continue }
            let handle = String(text[range].dropFirst())
            attributed[attrRange].link = URL(string: "mention://\(handle)")
            attributed[attrRange].foregroundColor = isOutgoing ? Color.white : Color.skyPrimary
            attributed[attrRange].underlineStyle = .single
        }
        return attributed
    }
}

// MARK: - BubbleShape

/// Chat bubble shape with a tail on the bottom corner — tail position
/// flips based on whether the message is outgoing (right) or incoming (left).
struct BubbleShape: Shape {
    let isOutgoing: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        var path = Path()

        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        let cornerRadius: CGFloat = isOutgoing ? radius : radius
        let tailSize: CGFloat = 6

        if isOutgoing {
            path.move(to: CGPoint(x: topLeft.x + cornerRadius, y: topLeft.y))
            path.addLine(to: CGPoint(x: topRight.x - cornerRadius, y: topRight.y))
            path.addQuadCurve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadius), control: topRight)
            path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadius - tailSize))
            path.addQuadCurve(to: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y - tailSize), control: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y - tailSize))
            path.addLine(to: CGPoint(x: rect.midX + tailSize, y: bottomRight.y - tailSize))
            path.addLine(to: CGPoint(x: rect.midX, y: bottomRight.y))
            path.addLine(to: CGPoint(x: rect.midX - tailSize, y: bottomRight.y - tailSize))
            path.addLine(to: CGPoint(x: bottomLeft.x + cornerRadius, y: bottomLeft.y - tailSize))
            path.addQuadCurve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadius - tailSize), control: bottomLeft)
            path.addLine(to: CGPoint(x: bottomLeft.x, y: topLeft.y + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: topLeft.x + cornerRadius, y: topLeft.y), control: topLeft)
        } else {
            path.move(to: CGPoint(x: topLeft.x + cornerRadius + tailSize, y: topLeft.y))
            path.addLine(to: CGPoint(x: topRight.x - cornerRadius, y: topRight.y))
            path.addQuadCurve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadius), control: topRight)
            path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: bottomRight.x - cornerRadius, y: bottomRight.y), control: bottomRight)
            path.addLine(to: CGPoint(x: bottomLeft.x + cornerRadius, y: bottomLeft.y))
            path.addQuadCurve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadius), control: bottomLeft)
            path.addLine(to: CGPoint(x: bottomLeft.x, y: topLeft.y + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: topLeft.x + cornerRadius + tailSize, y: topLeft.y), control: topLeft)
        }

        path.closeSubpath()
        return path
    }
}
