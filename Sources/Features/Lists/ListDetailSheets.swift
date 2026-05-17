import SwiftUI

struct ImportHandlesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rawInput = ""
    let importAction: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $rawInput)
                        .frame(minHeight: 180)
                } header: {
                    Text(verbatim: loc("list.import.paste_section"))
                }

                Section {
                    HelpSection(
                        title: loc("list.import.help_title"),
                        bulletPoints: [
                            loc("list.import.help_1"),
                            loc("list.import.help_2"),
                            loc("list.import.help_3"),
                            loc("list.import.help_4"),
                            loc("list.import.help_5"),
                        ]
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(loc("list.import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                    }
                    .accessibilityHint(loc("list.import.dismiss.hint"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("list.import.review")) {
                        importAction(rawInput)
                        dismiss()
                    }
                    .disabled(rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint(loc("list.import.review.hint"))
                }
            }
        }
    }
}

struct ImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    let isImporting: Bool
    let dismissAction: () -> Void
    let importAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(preview.sourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        verbatim: loc("list.import_preview.summary_text")
                            .replacingOccurrences(of: "{ready}", with: "\(preview.readyItems.count)")
                            .replacingOccurrences(of: "{already}", with: "\(preview.alreadyPresentItems.count)")
                            .replacingOccurrences(of: "{duplicates}", with: "\(preview.duplicateItems.count)")
                            .replacingOccurrences(of: "{unresolved}", with: "\(preview.unresolvedItems.count)")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(verbatim: loc("list.import_preview.skip_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(verbatim: loc("list.import_preview.summary"))
                }

                previewSection(loc("list.import_preview.ready"), items: preview.readyItems)
                previewSection(loc("list.import_preview.already"), items: preview.alreadyPresentItems)
                previewSection(loc("list.import_preview.duplicate"), items: preview.duplicateItems)
                previewSection(loc("list.import_preview.unresolved"), items: preview.unresolvedItems)

                if !isImporting {
                    Section {
                        HelpSection(
                            title: loc("list.import_preview.help_title"),
                            bulletPoints: [
                                loc("list.import_preview.help_ready"),
                                loc("list.import_preview.help_already"),
                                loc("list.import_preview.help_duplicate"),
                                loc("list.import_preview.help_unresolved"),
                                loc("list.import_preview.help_write"),
                            ]
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle(loc("list.import_preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.close")) {
                        dismissAction()
                        dismiss()
                    }
                    .disabled(isImporting)
                    .accessibilityHint(loc("list.import.close_preview.hint"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? loc("list.import_preview.importing") : loc("list.import_preview.import_button")) {
                        importAction()
                    }
                    .disabled(isImporting || preview.readyItems.isEmpty)
                    .accessibilityHint(loc("list.import.import_items.hint"))
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ title: String, items: [ImportPreviewItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayHandle)
                        if let actor = item.actor, let displayName = actor.displayName, !displayName.isEmpty {
                            Text(displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let message = item.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct ListMetadataSheet: View {
    @Environment(\.dismiss) private var dismiss

    enum Mode: Equatable {
        case create(kind: BlueskyList.Kind)
        case edit(list: BlueskyList, isSaving: Bool)
    }

    let mode: Mode
    let onConfirm: (_ title: String, _ description: String, _ kind: BlueskyList.Kind) -> Void

    private static let maxTitleLength = 64
    private static let maxDescriptionLength = 300

    @State private var title: String
    @State private var description: String
    @State private var kind: BlueskyList.Kind

    init(mode: Mode, onConfirm: @escaping (_ title: String, _ description: String, _ kind: BlueskyList.Kind) -> Void) {
        self.mode = mode
        self.onConfirm = onConfirm
        switch mode {
        case .create(let k):
            _title = State(initialValue: "")
            _description = State(initialValue: "")
            _kind = State(initialValue: k)
        case .edit(let list, _):
            _title = State(initialValue: list.name)
            _description = State(initialValue: list.description)
            _kind = State(initialValue: list.kind)
        }
    }

    private var isSaving: Bool {
        if case .edit(_, let saving) = mode { return saving }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(loc("list.edit.name_placeholder"), text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > Self.maxTitleLength {
                                title = String(newValue.prefix(Self.maxTitleLength))
                            }
                        }
                    counterBadge(count: title.count, max: Self.maxTitleLength)
                        .font(.caption)
                } header: {
                    Text(verbatim: loc("list.edit.name_label"))
                }

                Section {
                    TextField(loc("list.edit.desc_placeholder"), text: $description, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .onChange(of: description) { _, newValue in
                            if newValue.count > Self.maxDescriptionLength {
                                description = String(newValue.prefix(Self.maxDescriptionLength))
                            }
                        }
                    counterBadge(count: description.count, max: Self.maxDescriptionLength)
                        .font(.caption)
                } header: {
                    Text(verbatim: loc("list.edit.desc_label"))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                    .accessibilityHint(isCreating ? loc("list.create.discard.hint") : loc("list.edit.discard.hint"))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? loc("list.create.create") : loc("actions.save")) {
                        onConfirm(title, description, kind)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityHint(isCreating ? loc("list.create.create.hint") : loc("list.edit.save.hint"))
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create(let k):
            return k == .moderation ? loc("list.create.moderation_title") : loc("list.create.title")
        case .edit:
            return loc("list.edit.title")
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private func counterBadge(count: Int, max: Int) -> some View {
        HStack {
            Spacer()
            Text("\(count)/\(max)")
                .foregroundStyle(count > max ? .red : count > max - 10 ? .orange : .secondary)
                .monospacedDigit()
        }
    }
}
