import SwiftUI

struct ScreenableActor: Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let description: String?
}

struct ActorScreenResult: Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let scores: [String: Double]

    var topLabel: String {
        let sorted = scores.filter { $0.key != "safe" }.sorted { $0.value > $1.value }
        if let top = sorted.first, top.value > 0.3 {
            return "\(top.key) \(Int(top.value * 100))%"
        }
        return ""
    }

    var isRisky: Bool {
        scores["toxic"] ?? 0 > 0.3 || scores["harassment"] ?? 0 > 0.3 || scores["spam"] ?? 0 > 0.3
    }

    var isSpam: Bool {
        (scores["spam"] ?? 0) > 0.5
    }

    var isToxic: Bool {
        (scores["toxic"] ?? 0) > 0.5 || (scores["harassment"] ?? 0) > 0.5
    }

    var badgeColor: Color {
        if isToxic {
            .red
        } else if isSpam {
            .orange
        } else {
            .green
        }
    }

    var badgeIcon: String {
        if isToxic {
            "exclamationmark.triangle.fill"
        } else if isSpam {
            "ladybug.fill"
        } else {
            "checkmark.circle.fill"
        }
    }
}

struct AIBatchScreenView: View {
    let actors: [ScreenableActor]
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    @State private var results: [ActorScreenResult] = []
    @State private var isRunning = true

    var body: some View {
        NavigationStack {
            Group {
                if isRunning {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(loc("ai.screen.running"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        summarySection
                        ForEach(results) { result in
                            actorResultRow(result)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .pageTitle(loc("ai.screen.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.close")) { dismiss() }
                }
            }
            .task {
                await run()
            }
        }
    }

    private var summarySection: some View {
        let total = results.count
        let toxic = results.filter(\.isToxic).count
        let spam = results.filter(\.isSpam).count
        let safe = total - toxic - spam
        return Section {
            HStack {
                summaryBadge(color: .red, icon: "exclamationmark.triangle.fill", count: toxic, label: loc("ai.screen.toxic"))
                Spacer()
                summaryBadge(color: .orange, icon: "ladybug.fill", count: spam, label: loc("ai.screen.spam"))
                Spacer()
                summaryBadge(color: .green, icon: "checkmark.circle.fill", count: safe, label: loc("ai.screen.safe"))
            }
            .padding(.vertical, 4)
        } header: {
            Text(loc("ai.screen.summary").replacingOccurrences(of: "{total}", with: "\(total)"))
        }
    }

    private func summaryBadge(color: Color, icon: String, count: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func actorResultRow(_ result: ActorScreenResult) -> some View {
        let label = if result.isToxic {
            loc("ai.screen.toxic")
        } else if result.isSpam {
            loc("ai.screen.spam")
        } else {
            loc("ai.screen.safe")
        }
        return HStack(spacing: 10) {
            Image(systemName: result.badgeIcon)
                .font(.title3)
                .foregroundStyle(result.badgeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("@\(result.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(result.badgeColor)
        }
        .padding(.vertical, 2)
    }

    private func run() async {
        let engine = InferenceEngine()
        var output: [ActorScreenResult] = []
        for actor in actors {
            let profileText = [actor.displayName, actor.handle, actor.description].compactMap(\.self).joined(separator: " ")
            let scores = engine.classify(text: profileText)
            output.append(ActorScreenResult(
                id: actor.id,
                displayName: actor.displayName,
                handle: actor.handle,
                scores: scores
            ))
        }
        results = output.sorted { $0.isRisky && !$1.isRisky }
        isRunning = false
    }
}

#Preview {
    AIBatchScreenView(actors: [
        ScreenableActor(id: "1", displayName: "Test User", handle: "test.bsky.social", description: nil),
        ScreenableActor(id: "2", displayName: "Spammer", handle: "spam.bsky.social", description: "Buy crypto now!"),
    ])
    .environmentObject(LocalizationManager.shared)
}
