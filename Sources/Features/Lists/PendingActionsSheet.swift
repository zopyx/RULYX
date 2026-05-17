import SwiftUI

struct PendingActionsSheet: View {
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if workspaceStore.queuedActions.isEmpty {
                    ContentUnavailableView(loc("pending.empty.title"), systemImage: "tray", description: Text(loc("pending.empty.desc")))
                } else {
                    ForEach(workspaceStore.queuedActions) { action in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(action.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                statusBadge(action.status)
                            }

                            switch action.status {
                            case .pending:
                                Text(loc("pending.waiting"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case let .running(done, total, handle):
                                ProgressView(value: Double(done), total: Double(total))
                                Text("\(done) of \(total)\(handle.map { " \u{2014} \($0)" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case let .completed(succeeded, failed):
                                if failed > 0 {
                                    Text("\(succeeded) succeeded, \(failed) failed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(succeeded) completed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if case .pending = action.status {
                                Button(loc("pending.cancel_button"), role: .destructive) {
                                    workspaceStore.actionQueue.cancel(action.id)
                                }
                                .font(.caption)
                                .accessibilityHint(loc("action_queue.cancel.hint"))
                            }
                            if case .completed = action.status {
                                Button(loc("pending.retry_button")) {
                                    workspaceStore.actionQueue.retry(action.id)
                                }
                                .font(.caption)
                                .accessibilityHint(loc("action_queue.retry.hint"))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            workspaceStore.actionQueue.cancel(workspaceStore.queuedActions[index].id)
                        }
                    }
                }
            }
            .navigationTitle(loc("pending.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc("pending.done_button")) { isPresented = false }
                        .accessibilityHint(loc("action_queue.close.hint"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func statusBadge(_ status: QueuedActionStatus) -> some View {
        switch status {
        case .pending:
            Text(loc("pending.status.pending"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(.regular, in: .rect(cornerRadius: .infinity))
                    } else {
                        Color.clear.background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
        case .running:
            Text(loc("pending.badge_running"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(.regular.tint(.skyPrimary), in: .rect(cornerRadius: .infinity))
                    } else {
                        Color.clear.background(Color.skyPrimary.opacity(0.12), in: Capsule())
                    }
                }
                .foregroundStyle(Color.skyPrimary)
        case let .completed(succeeded, failed):
            if failed > 0 {
                Text("\(succeeded)/\(succeeded + failed)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        if #available(iOS 26, *) {
                            Color.clear.glassEffect(.regular.tint(.orange), in: .rect(cornerRadius: .infinity))
                        } else {
                            Color.clear.background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                    .foregroundStyle(.orange)
            } else {
                Text(loc("pending.status.done"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        if #available(iOS 26, *) {
                            Color.clear.glassEffect(.regular.tint(.green), in: .rect(cornerRadius: .infinity))
                        } else {
                            Color.clear.background(Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                    .foregroundStyle(.green)
            }
        }
    }
}
