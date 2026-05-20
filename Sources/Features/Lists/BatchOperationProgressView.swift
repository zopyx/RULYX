import SwiftUI

struct PendingLikerTarget: Identifiable {
    let did: String
    let handle: String?

    var id: String {
        did
    }
}

struct BatchOperationConfig: Identifiable {
    let id = UUID()
    let targets: [PendingLikerTarget]
    let mode: Mode

    enum Mode {
        case block(account: AppAccount, appPassword: String)
        case addToList(list: BlueskyList, account: AppAccount, appPassword: String)
    }
}

@MainActor
struct BatchOperationProgressView: View {
    let config: BatchOperationConfig

    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    @State private var checkedCount = 0
    @State private var skippedCount = 0
    @State private var completedCount = 0
    @State private var failedCount = 0
    @State private var currentHandle: String?
    @State private var targetsToProcess: [PendingLikerTarget] = []

    @State private var isCheckComplete = false
    @State private var isExecuteComplete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    phaseHeader(
                        title: loc("post.block_likers.checking_title"),
                        isComplete: isCheckComplete
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: isCheckComplete ? Double(config.targets.count) : Double(checkedCount),
                            total: Double(config.targets.count)
                        )
                        .progressViewStyle(.linear)

                        Text(
                            verbatim: checkProgressText
                                .replacingOccurrences(of: "{done}", with: "\(checkedCount)")
                                .replacingOccurrences(of: "{total}", with: "\(config.targets.count)")
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        if skippedCount > 0 {
                            Text(
                                verbatim: loc("post.block_likers.already_blocked")
                                    .replacingOccurrences(of: "{count}", with: "\(skippedCount)")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 28)
                }
                .opacity(isExecuteComplete ? 0.5 : 1)

                if isCheckComplete || isExecuteComplete {
                    VStack(alignment: .leading, spacing: 16) {
                        phaseHeader(
                            title: executionTitle,
                            isComplete: isExecuteComplete
                        )

                        if !targetsToProcess.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(
                                    value: Double(completedCount + failedCount),
                                    total: Double(targetsToProcess.count)
                                )
                                .progressViewStyle(.linear)

                                HStack(spacing: 16) {
                                    Text(
                                        verbatim: loc("post.block_likers.blocked_now")
                                            .replacingOccurrences(of: "{count}", with: "\(completedCount)")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    if failedCount > 0 {
                                        Text("failures: \(failedCount)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }

                                if let handle = currentHandle {
                                    Text(verbatim: handle)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.leading, 28)
                        } else {
                            Text(loc("post.block_likers.no_likers"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if isExecuteComplete {
                    VStack(spacing: 20) {
                        completionSummary
                            .transition(.opacity)

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityLabel(loc("actions.done"))
                    }
                }
            }
            .padding(.horizontal, 24)
            .navigationTitle(navTitle)
            .toolbarTitleDisplayMode(.inline)
            .animation(.default, value: isCheckComplete)
            .animation(.default, value: isExecuteComplete)
            .interactiveDismissDisabled(!isExecuteComplete)
        }
        .presentationDetents([.medium, .large])
        .task {
            await runOperation()
        }
    }

    private var navTitle: String {
        switch config.mode {
        case .block:
            loc("post.block_likers")
        case .addToList:
            loc("post.add_likers_to_list")
        }
    }

    private var checkProgressText: String {
        switch config.mode {
        case .block:
            loc("post.block_likers.check_progress")
        case .addToList:
            loc("post.add_likers.check_progress")
        }
    }

    private var executionTitle: String {
        switch config.mode {
        case .block:
            loc("post.block_likers.blocking_title")
        case .addToList:
            loc("post.add_likers.adding_title")
        }
    }

    private func phaseHeader(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var completionSummary: some View {
        let blockedCount = completedCount
        let alreadyBlockedCount = skippedCount + (config.targets.count - checkedCount)
        let failureCount = failedCount

        VStack(spacing: 8) {
            switch config.mode {
            case .block:
                if blockedCount > 0 {
                    Label(
                        loc("post.block_likers.done")
                            .replacingOccurrences(of: "{count}", with: "\(blockedCount)"),
                        systemImage: "hand.raised.fill"
                    )
                    .foregroundStyle(.primary)
                }
                if alreadyBlockedCount > 0 {
                    Label(
                        loc("post.block_likers.already_blocked")
                            .replacingOccurrences(of: "{count}", with: "\(alreadyBlockedCount)"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                }
            case let .addToList(list, _, _):
                if blockedCount > 0 {
                    Label(
                        loc("post.add_likers.done")
                            .replacingOccurrences(of: "{count}", with: "\(blockedCount)")
                            .replacingOccurrences(of: "{list}", with: list.name),
                        systemImage: "text.badge.plus"
                    )
                    .foregroundStyle(.primary)
                }
                if alreadyBlockedCount > 0 {
                    Label(
                        "Already in list: \(alreadyBlockedCount)",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            if failureCount > 0 {
                Label(
                    "\(failureCount) failed",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(Color.warningOrange)
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
    }

    private func runOperation() async {
        switch config.mode {
        case let .block(account, appPassword):
            await runBlock(account: account, appPassword: appPassword)
        case let .addToList(list, account, appPassword):
            await runAddToList(list: list, account: account, appPassword: appPassword)
        }
    }

    private func runBlock(account: AppAccount, appPassword: String) async {
        let blockedDIDs: Set<String>
        do {
            let blockedResult = try await blueskyClient.fetchBlockedActors(account: account, appPassword: appPassword)
            blockedDIDs = Set(blockedResult.actors.map(\.did))
        } catch {
            blockedDIDs = []
            AppLogger.moderation.error("Failed to fetch blocked actors: \(error.localizedDescription, privacy: .public)")
        }

        var toProcess: [PendingLikerTarget] = []
        var skips = 0
        for target in config.targets {
            if blockedDIDs.contains(target.did) {
                skips += 1
            } else {
                toProcess.append(target)
            }
            checkedCount += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        skippedCount = skips
        targetsToProcess = toProcess
        isCheckComplete = true

        guard !toProcess.isEmpty else {
            isExecuteComplete = true
            return
        }

        for target in toProcess {
            currentHandle = displayHandle(for: target)
            do {
                try await blueskyClient.blockActor(did: target.did, account: account, appPassword: appPassword)
                completedCount += 1
            } catch {
                failedCount += 1
                AppLogger.moderation.error("Failed to block \(target.did): \(error.localizedDescription, privacy: .public)")
            }
            await Task.yield()
        }
        currentHandle = nil
        isExecuteComplete = true
    }

    private func runAddToList(list: BlueskyList, account: AppAccount, appPassword: String) async {
        let memberDIDs: Set<String>
        do {
            let members = try await blueskyClient.fetchListMembers(list: list, account: account, appPassword: appPassword)
            memberDIDs = Set(members.map(\.actor.did))
        } catch {
            memberDIDs = []
            AppLogger.moderation.error("Failed to fetch list members: \(error.localizedDescription, privacy: .public)")
        }

        var toProcess: [PendingLikerTarget] = []
        var skips = 0
        for target in config.targets {
            if memberDIDs.contains(target.did) {
                skips += 1
            } else {
                toProcess.append(target)
            }
            checkedCount += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        skippedCount = skips
        targetsToProcess = toProcess
        isCheckComplete = true

        guard !toProcess.isEmpty else {
            isExecuteComplete = true
            return
        }

        for target in toProcess {
            currentHandle = displayHandle(for: target)
            do {
                _ = try await blueskyClient.addActor(did: target.did, to: list, account: account, appPassword: appPassword)
                completedCount += 1
            } catch {
                failedCount += 1
                AppLogger.moderation.error("Failed to add \(target.did) to \(list.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            await Task.yield()
        }
        currentHandle = nil
        isExecuteComplete = true
    }

    private func displayHandle(for target: PendingLikerTarget) -> String {
        if let handle = target.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return target.did
    }
}
