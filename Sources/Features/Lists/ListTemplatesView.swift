import SwiftUI

struct ListTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let kind: BlueskyList.Kind
    let presetDescription: String
}

private let templates: [ListTemplate] = [
    ListTemplate(id: "spam-watch", name: "Spam Watch", description: "Accounts frequently reported for spam patterns", kind: .moderation, presetDescription: "Track accounts reported for spam"),
    ListTemplate(id: "reply-guys", name: "Reply Guys", description: "Aggressive reply actors tracked for moderation review", kind: .moderation, presetDescription: "Monitor aggressive commenters"),
    ListTemplate(id: "trusted-sources", name: "Trusted Sources", description: "Accounts curated for signal over noise", kind: .regular, presetDescription: "Curate high-quality accounts"),
    ListTemplate(id: "community-core", name: "Community Core", description: "People to monitor for community health updates", kind: .regular, presetDescription: "Track engaged community members"),
    ListTemplate(id: "new-reports", name: "New Reports", description: "Freshly observed accounts pending deeper review", kind: .moderation, presetDescription: "Queue accounts for review"),
    ListTemplate(id: "emergency-block", name: "Emergency Block", description: "Urgent accounts requiring immediate blocking", kind: .moderation, presetDescription: "Quick-action block list"),
]

struct ListTemplatesView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    let onListCreated: (BlueskyList) -> Void
    @State private var isCreating = false

    var body: some View {
        List(templates) { template in
            Button {
                create(template)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(template.name).font(.headline)
                        Spacer()
                        StatusChip(text: template.kind.title, style: template.kind == .moderation ? .warning : .info)
                    }
                    Text(template.presetDescription).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .disabled(isCreating)
            .buttonStyle(.plain)
            .accessibilityHint(loc("list_templates.create.hint"))
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("list_templates.title"))
        .overlay {
            if isCreating { ProgressView(loc("list_templates.creating")) }
        }
    }

    private func create(_ template: ListTemplate) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        isCreating = true
        Task {
            do {
                let list = try await blueskyClient.createList(name: template.name, description: template.description, kind: template.kind, account: account, appPassword: appPassword)
                onListCreated(list)
                dismiss()
            } catch {}
            isCreating = false
        }
    }
}

#Preview {
    NavigationStack { ListTemplatesView(onListCreated: { _ in }) }
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
