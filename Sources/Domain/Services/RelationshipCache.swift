import Foundation

enum RelationshipCache {
    private static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.ajung.BlueskyModeration")
    }

    private static func fileURL(forKey key: String) -> URL {
        cachesDirectory.appendingPathComponent("\(key).json")
    }

    static func load(forKey key: String) -> [BlueskyActor] {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url),
              let actors = try? JSONDecoder().decode([BlueskyActor].self, from: data)
        else {
            return []
        }
        return actors
    }

    static func save(_ actors: [BlueskyActor], forKey key: String) {
        let url = fileURL(forKey: key)
        try? FileManager.default.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(actors) else { return }
        try? data.write(to: url)
    }

    static func clear(forKey key: String) {
        let url = fileURL(forKey: key)
        try? FileManager.default.removeItem(at: url)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: cachesDirectory)
    }
}
