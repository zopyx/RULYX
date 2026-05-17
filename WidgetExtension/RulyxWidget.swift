import WidgetKit
import SwiftUI

struct ListCountEntry: TimelineEntry {
    let date: Date
    let listCounts: [(name: String, count: Int)]
    let isPlaceholder: Bool
}

struct ListCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListCountEntry {
        ListCountEntry(date: .now, listCounts: [("Spam Watch", 42), ("Trusted Sources", 18)], isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ListCountEntry) -> Void) {
        let entry = ListCountEntry(date: .now, listCounts: loadCounts(), isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ListCountEntry>) -> Void) {
        let entry = ListCountEntry(date: .now, listCounts: loadCounts(), isPlaceholder: false)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadCounts() -> [(name: String, count: Int)] {
        guard let data = UserDefaults.standard.data(forKey: "widgetListCounts"),
              let counts = try? JSONDecoder().decode([WidgetListCount].self, from: data) else {
            return [("Add accounts in Rulyx", 0)]
        }
        return counts.map { ($0.name, $0.count) }
    }
}

struct WidgetListCount: Codable {
    let name: String
    let count: Int
}

struct RulyxWidgetEntryView: View {
    var entry: ListCountProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(.blue)
                Text("Rulyx").font(.headline)
            }
            Divider()
            ForEach(entry.listCounts.prefix(5), id: \.name) { item in
                HStack {
                    Text(item.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text("\(item.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct RulyxWidget: Widget {
    let kind = "com.ajung.BlueskyModeration.RulyxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListCountProvider()) { entry in
            RulyxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("List Counts")
        .description("Shows your moderation list member counts.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct RulyxWidgetBundle: WidgetBundle {
    var body: some Widget {
        RulyxWidget()
    }
}
