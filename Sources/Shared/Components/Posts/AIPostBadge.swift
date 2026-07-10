import SwiftUI

struct AIPostBadge: View {
    let scores: [String: Double]

    private var isToxic: Bool {
        (scores["toxic"] ?? 0) > 0.4 || (scores["harassment"] ?? 0) > 0.4
    }

    private var isSpam: Bool {
        (scores["spam"] ?? 0) > 0.4
    }

    private var label: String {
        if isToxic, isSpam { loc("ai.badge.toxic_and_spam") }
        else if isToxic { loc("ai.badge.toxic") }
        else if isSpam { loc("ai.badge.spam") }
        else { "" }
    }

    private var color: Color {
        if isToxic { .red }
        else if isSpam { .orange }
        else { .clear }
    }

    var body: some View {
        if !label.isEmpty {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
        }
    }
}
