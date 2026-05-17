import SwiftUI

struct ActionPresetsView: View {
    @StateObject private var store = ActionPresetStore()
    @State private var isCreating = false

    var body: some View {
        List {
            if store.presets.isEmpty {
                ContentUnavailableView(loc("presets.no_presets"), systemImage: "square.2.layers.3d", description: Text(loc("presets.no_presets_desc")))
            }

            ForEach(store.presets) { preset in
                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.name).font(.headline)
                    HStack(spacing: 4) {
                        if preset.shouldBlock { Tag("Block", color: .red) }
                        if preset.shouldMute { Tag("Mute", color: .orange) }
                        if preset.shouldReport { Tag("Report", color: .purple) }
                        if let list = preset.targetListName { Tag("Add to \(list)", color: .blue) }
                    }
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.delete(preset) } label: { Label(loc("actions.delete"), systemImage: "trash") }
                        .accessibilityHint(loc("action_preset.delete.hint"))
                }
                .swipeActions(edge: .leading) {
                    Button { store.duplicate(preset) } label: { Label(loc("presets.duplicate"), systemImage: "doc.on.doc") }
                        .accessibilityHint(loc("action_preset.duplicate.hint"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("presets.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityHint(loc("action_preset.create.hint"))
            }
        }
        .sheet(isPresented: $isCreating) {
            EditActionPresetView(store: store)
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 2)
            .background {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular.tint(color), in: .rect(cornerRadius: .infinity))
                } else {
                    Color.clear.background(color.opacity(0.12), in: Capsule())
                }
            }
    }
}

struct EditActionPresetView: View {
    @ObservedObject var store: ActionPresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var shouldBlock = false
    @State private var shouldMute = false
    @State private var shouldReport = false
    @State private var targetListName = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(loc("presets.name_placeholder"), text: $name)
                Section(loc("presets.actions_section")) {
                    Toggle(loc("presets.block"), isOn: $shouldBlock)
                        .accessibilityHint(loc("action_preset.block.hint"))
                    Toggle(loc("presets.mute"), isOn: $shouldMute)
                        .accessibilityHint(loc("action_preset.mute.hint"))
                    Toggle(loc("presets.report"), isOn: $shouldReport)
                        .accessibilityHint(loc("action_preset.report.hint"))
                }
                Section(loc("presets.add_to_list")) {
                    TextField(loc("presets.list_placeholder"), text: $targetListName)
                }
            }
            .navigationTitle(loc("presets.new_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc("actions.cancel")) { dismiss() }.accessibilityHint(loc("action_preset.discard.hint")) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.save")) {
                        store.save(ActionPreset(name: name, shouldBlock: shouldBlock, shouldMute: shouldMute, shouldReport: shouldReport, targetListName: targetListName.isEmpty ? nil : targetListName))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint(loc("action_preset.save.hint"))
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ActionPresetsView() }
}
