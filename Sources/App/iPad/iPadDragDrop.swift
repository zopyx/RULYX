import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let blueskyActor = UTType(exportedAs: "com.ajung.rulyx.bluesky-actor")
    static let blueskyList = UTType(exportedAs: "com.ajung.rulyx.bluesky-list")
}

struct TransferableActor: Codable, Transferable {
    let did: String
    let handle: String
    let displayName: String?

    init(actor: BlueskyActor) {
        did = actor.did
        handle = actor.handle
        displayName = actor.displayName
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .blueskyActor)
        ProxyRepresentation(exporting: \.handle)
        ProxyRepresentation(exporting: \.did)
    }
}

struct TransferableList: Codable, Transferable {
    let uri: String
    let name: String
    let purpose: String

    init(list: BlueskyList) {
        uri = list.id
        name = list.name
        purpose = list.kind.rawValue
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .blueskyList)
    }
}

struct ActorDragSource: ViewModifier {
    let actor: BlueskyActor

    func body(content: Content) -> some View {
        content
            .draggable(TransferableActor(actor: actor)) {
                dragPreview
            }
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            AsyncImage(url: actor.avatarURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            Text(actor.title)
                .font(.caption.weight(.semibold))
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func actorDragSource(_ actor: BlueskyActor) -> some View {
        modifier(ActorDragSource(actor: actor))
    }
}
