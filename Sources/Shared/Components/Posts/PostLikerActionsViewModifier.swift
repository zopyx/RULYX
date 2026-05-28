import SwiftUI

// MARK: - PostLikerActionsViewModifier

/// ViewModifier that wires up all the sheets, alerts, and progress views
/// driven by `PostLikerActionsManager`. Apply this at the feed/timeline level
/// so that any post row can trigger bulk liker actions.
///
/// Manages:
/// - AI classification sheet (`postToClassify`)
/// - Report sheet (`postToReport`) with `SimplifiedReportSheet`
/// - Batch operation progress (`batchOperationConfig`) via `BatchOperationProgressView`
/// - Block-likers confirmation alert
/// - Block errors alert
struct PostLikerActionsViewModifier: ViewModifier {
    /// The manager driving liker actions state.
    @ObservedObject var manager: PostLikerActionsManager
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var aiService: LiveAIService
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - ViewModifier

    func body(content: Content) -> some View {
        content
            .sheet(item: $manager.postToClassify) { entry in
                NavigationStack {
                    PostClassificationView(entry: entry)
                        .environmentObject(aiService)
                        .environmentObject(localizationManager)
                }
            }
            .sheet(item: $manager.postToReport) { entry in
                SimplifiedReportSheet(
                    title: loc("post.report"),
                    selectedReason: $manager.reportReason,
                    evidenceText: $manager.reportEvidence,
                    isSubmitting: manager.isSubmittingReport,
                    makeSupportDraft: { manager.makeReportDraft(for: entry) },
                    onCancel: {
                        manager.postToReport = nil
                        manager.reportEvidence = ""
                        manager.reportReason = .simplifiedDefault
                    },
                    onSubmit: {
                        guard let account = accountStore.activeAccount,
                              let appPassword = accountStore.appPassword(for: account) else { return }
                        Task { await manager.submitPostReport(using: blueskyClient, account: account, appPassword: appPassword) }
                    }
                )
            }
            .sheet(item: $manager.batchOperationConfig) { config in
                BatchOperationProgressView(config: config)
                    .environmentObject(blueskyClient)
            }
            .alert(
                loc("post.block_likers.confirm_title")
                    .replacingOccurrences(of: "{count}", with: "\(manager.pendingLikerTargets.count)"),
                isPresented: $manager.showBlockLikersConfirmation
            ) {
                Button(loc("post.block_likers.confirm_block"), role: .destructive) {
                    if let account = accountStore.activeAccount,
                       let appPassword = accountStore.appPassword(for: account) {
                        manager.confirmBlockLikers(activeAccount: account, activePassword: appPassword)
                    }
                }
                Button(loc("actions.cancel"), role: .cancel) {
                    manager.resetPendingLikerTargets()
                }
            } message: {
                let targets = manager.pendingLikerTargets
                let handles = targets.prefix(5).map { target in
                    if let handle = target.handle, !handle.isEmpty {
                        return "@\(handle)"
                    }
                    return target.did
                }.joined(separator: "\n")
                let remainder = targets.count > 5
                    ? "\n…and \(targets.count - 5) more"
                    : ""
                Text(
                    verbatim: loc("post.block_likers.confirm_message")
                        .replacingOccurrences(of: "{count}", with: "\(targets.count)")
                        + "\n\n" + handles + remainder
                )
            }
            .alert(loc("list.detail.alert_title"), isPresented: .init(
                get: { manager.blockError != nil },
                set: { if !$0 { manager.blockError = nil } }
            )) {
                Button(loc("actions.ok")) { manager.blockError = nil }
            } message: {
                if let error = manager.blockError {
                    Text(error)
                }
            }
    }
}

extension View {
    /// Apply all liker-action sheets and alerts driven by the given manager.
    func postLikerActions(manager: PostLikerActionsManager) -> some View {
        modifier(PostLikerActionsViewModifier(manager: manager))
    }
}
