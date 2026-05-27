import SwiftUI

private struct CommandEntry: Identifiable {
    let id = UUID()
    let item: SidebarItem
    let label: String
    let icon: String
}

struct iPadCommandPalette: View {
    @EnvironmentObject private var localizationManager: LocalizationManager

    @Binding var isPresented: Bool
    var onNavigate: (SidebarItem) -> Void

    @State private var searchText = ""

    private var allCommands: [CommandEntry] {
        [
            CommandEntry(item: .allLists, label: loc("sidebar.all_lists"), icon: "checklist.checked"),
            CommandEntry(item: .templates, label: loc("sidebar.templates"), icon: "doc.on.doc"),
            CommandEntry(item: .rules, label: loc("sidebar.rules"), icon: "shield.checkered"),
            CommandEntry(item: .dashboard, label: loc("sidebar.dashboard"), icon: "chart.bar.xaxis"),
            CommandEntry(item: .relationships, label: loc("sidebar.relationships"), icon: "arrow.left.arrow.right"),
            CommandEntry(item: .customSearch, label: loc("sidebar.custom_search"), icon: "magnifyingglass"),
            CommandEntry(item: .mentionsSearch, label: loc("sidebar.mentions_search"), icon: "at"),
            CommandEntry(item: .bulkLookup, label: loc("sidebar.bulk_lookup"), icon: "person.2.fill"),
            CommandEntry(item: .networkGraph, label: loc("sidebar.network_graph"), icon: "point.3.connected.trianglepath.dotted"),
            CommandEntry(item: .timeline, label: loc("sidebar.timeline"), icon: "clock.arrow.circlepath"),
            CommandEntry(item: .notifications, label: loc("sidebar.notifications"), icon: "bell"),
            CommandEntry(item: .chat, label: loc("sidebar.chat"), icon: "bubble.left.and.bubble.right"),
            CommandEntry(item: .settings, label: loc("sidebar.settings"), icon: "gearshape"),
            CommandEntry(item: .accounts, label: loc("sidebar.accounts"), icon: "person.circle"),
            CommandEntry(item: .info, label: loc("sidebar.info"), icon: "sparkles.rectangle.stack"),
        ]
    }

    private var filteredCommands: [CommandEntry] {
        if searchText.isEmpty {
            return allCommands
        }
        return allCommands.filter { entry in
            entry.label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(loc("command_palette.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            if filteredCommands.isEmpty {
                ContentUnavailableView(
                    loc("command_palette.no_results"),
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .padding(.vertical, 40)
            } else {
                List(filteredCommands) { entry in
                    Button {
                        onNavigate(entry.item)
                        isPresented = false
                    } label: {
                        Label(entry.label, systemImage: entry.icon)
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.secondary.opacity(0.2))
        }
    }
}
