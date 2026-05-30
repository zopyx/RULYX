import SwiftUI

struct iPadSidebar: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarSection.moderationItems, id: \.self) { item in
                    sidebarLabel(for: item)
                        .tag(item)
                }
            } header: {
                Text(sectionLabel(.moderation))
            }

            Section {
                ForEach(SidebarSection.searchItems, id: \.self) { item in
                    sidebarLabel(for: item)
                        .tag(item)
                }
            } header: {
                Text(sectionLabel(.searchProfiles))
            }

            Section {
                ForEach(SidebarSection.socialItems, id: \.self) { item in
                    sidebarLabel(for: item)
                        .tag(item)
                }
            } header: {
                Text(sectionLabel(.social))
            }

            Section {
                ForEach(SidebarSection.systemItems, id: \.self) { item in
                    sidebarLabel(for: item)
                        .tag(item)
                }
            } header: {
                Text(sectionLabel(.system))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("RULYX")
        .toolbarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .accessibilityLabel(loc("sidebar.edit"))
            }
        }
    }

    private func sidebarLabel(for item: SidebarItem) -> some View {
        Label {
            Text(sidebarTitle(item))
        } icon: {
            Image(systemName: sidebarIcon(item))
        }
    }

    private func sidebarTitle(_ item: SidebarItem) -> String {
        switch item {
        case .allLists: loc("sidebar.all_lists")
        case .templates: loc("sidebar.templates")
        case .rules: loc("sidebar.rules")
        case .dashboard: loc("sidebar.dashboard")
        case .relationships: loc("sidebar.relationships")
        case .customSearch: loc("sidebar.custom_search")
        case .mentionsSearch: loc("sidebar.mentions_search")
        case .bulkLookup: loc("sidebar.bulk_lookup")
        case .networkGraph: loc("sidebar.network_graph")
        case .timeline: loc("sidebar.timeline")
        case .notifications: loc("sidebar.notifications")
        case .chat: loc("sidebar.chat")
        case .settings: loc("sidebar.settings")
        case .accounts: loc("sidebar.accounts")
        case .info: loc("sidebar.info")
        }
    }

    private func sidebarIcon(_ item: SidebarItem) -> String {
        switch item {
        case .allLists: "checklist.checked"
        case .templates: "doc.on.doc"
        case .rules: "shield.checkered"
        case .dashboard: "chart.bar.xaxis"
        case .relationships: "arrow.left.arrow.right"
        case .customSearch: "magnifyingglass"
        case .mentionsSearch: "at"
        case .bulkLookup: "person.2.fill"
        case .networkGraph: "point.3.connected.trianglepath.dotted"
        case .timeline: "clock.arrow.circlepath"
        case .notifications: "bell"
        case .chat: "bubble.left.and.bubble.right"
        case .settings: "gearshape"
        case .accounts: "person.circle"
        case .info: "sparkles.rectangle.stack"
        }
    }

    private func sectionLabel(_ section: SidebarSection) -> String {
        switch section {
        case .moderation: loc("sidebar.section.moderation")
        case .searchProfiles: loc("sidebar.section.search_profiles")
        case .social: loc("sidebar.section.social")
        case .system: ""
        }
    }
}

extension SidebarSection {
    static let moderationItems: [SidebarItem] = [.allLists, .templates, .rules, .dashboard, .relationships]
    static let searchItems: [SidebarItem] = [.customSearch, .mentionsSearch, .bulkLookup, .networkGraph]
    static let socialItems: [SidebarItem] = [.timeline, .notifications, .chat]
    static let systemItems: [SidebarItem] = [.settings, .accounts, .info]
}
