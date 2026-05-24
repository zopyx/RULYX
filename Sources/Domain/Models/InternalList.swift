import SwiftUI

struct InternalList: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: InternalListColor
    var members: [InternalListMember]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: InternalListColor,
        members: [InternalListMember] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.members = members
        self.createdAt = createdAt
    }

    var memberCount: Int { members.count }
}

struct InternalListMember: Identifiable, Codable, Hashable {
    let id: String
    let handle: String
    let displayName: String?
    let avatarURL: String?
    let addedAt: Date

    init(
        did: String,
        handle: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.addedAt = addedAt
    }
}

enum InternalListColor: String, Codable, CaseIterable, Hashable {
    case red
    case green
    case blue
    case orange
    case purple
    case yellow

    var symbolName: String {
        switch self {
        case .red: return "circle.fill"
        case .green: return "circle.fill"
        case .blue: return "circle.fill"
        case .orange: return "circle.fill"
        case .purple: return "circle.fill"
        case .yellow: return "circle.fill"
        }
    }
}

extension InternalListColor {
    var colorValue: Color {
        switch self {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .orange: return .orange
        case .purple: return .purple
        case .yellow: return .yellow
        }
    }
}
