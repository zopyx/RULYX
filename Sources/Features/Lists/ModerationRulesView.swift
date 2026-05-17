import SwiftUI

struct ModerationRulesView: View {
    @StateObject private var store = ModerationRuleStore()
    @State private var isCreating = false

    var body: some View {
        List {
            if store.rules.isEmpty {
                ContentUnavailableView(loc("rules.no_rules"), systemImage: "wand.and.rays", description: Text(loc("rules.no_rules_desc")))
            }
            ForEach(store.rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name).font(.headline)
                        Text(loc("rules.rule_format").replacingOccurrences(of: "{trigger}", with: triggerLocalized(rule.trigger)).replacingOccurrences(of: "{action}", with: actionLocalized(rule.action))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { _ in store.toggle(rule) }))
                        .labelsHidden()
                        .accessibilityHint(rule.isEnabled ? loc("moderation_rule.disable.hint") : loc("moderation_rule.enable.hint"))
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.delete(rule) } label: { Label(loc("actions.delete"), systemImage: "trash") }
                        .accessibilityHint(loc("moderation_rule.delete.hint"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("rules.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { isCreating = true } label: { Image(systemName: "plus") }.accessibilityHint(loc("moderation_rule.create.hint")) }
        }
        .sheet(isPresented: $isCreating) { EditRuleView(store: store) }
    }
}

@MainActor
private func triggerLocalized(_ trigger: ModerationRule.Trigger) -> String {
    switch trigger {
    case .accountYoungerThan: loc("rules.trigger.account_younger_than")
    case .followerCountBelow: loc("rules.trigger.follower_count_below")
    case .followerCountAbove: loc("rules.trigger.follower_count_above")
    case .handleContains: loc("rules.trigger.handle_contains")
    case .hasLabel: loc("rules.trigger.has_label")
    }
}

@MainActor
private func actionLocalized(_ action: ModerationRule.Action) -> String {
    switch action {
    case .addToModList: loc("rules.action.add_to_mod_list")
    case .block: loc("rules.action.block")
    case .mute: loc("rules.action.mute")
    case .report: loc("rules.action.report")
    }
}

private struct EditRuleView: View {
    @ObservedObject var store: ModerationRuleStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var trigger: ModerationRule.Trigger = .handleContains
    @State private var triggerValue = ""
    @State private var action: ModerationRule.Action = .block

    var body: some View {
        NavigationStack {
            Form {
                TextField(loc("rules.name_placeholder"), text: $name)
                Picker(loc("rules.trigger"), selection: $trigger) {
                    ForEach(ModerationRule.Trigger.allCases) { t in Text(triggerLocalized(t)).tag(t) }
                }
                .accessibilityHint(loc("moderation_rule.condition.hint"))
                if trigger == .handleContains || trigger == .hasLabel {
                    TextField(loc("rules.value_placeholder"), text: $triggerValue)
                }
                Picker(loc("rules.action"), selection: $action) {
                    ForEach(ModerationRule.Action.allCases) { a in Text(actionLocalized(a)).tag(a) }
                }
                .accessibilityHint(loc("moderation_rule.action.hint"))
            }
            .navigationTitle(loc("rules.new_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc("actions.cancel")) { dismiss() }.accessibilityHint(loc("moderation_rule.discard.hint")) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.save")) {
                        store.save(ModerationRule(name: name, trigger: trigger, triggerValue: triggerValue, action: action))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint(loc("moderation_rule.save.hint"))
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ModerationRulesView() }
}
