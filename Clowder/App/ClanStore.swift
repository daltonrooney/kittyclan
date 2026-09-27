import Foundation

/// Reads and writes the saved Clan as JSON in Application Support.
struct ClanStore: Sendable {
    let url: URL

    static let standard = ClanStore(url: .applicationSupportDirectory.appending(path: "clan.json"))

    @concurrent
    func load() async throws -> Clan? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Clan.self, from: data)
    }

    @concurrent
    func save(_ clan: Clan) async throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(clan)
        try data.write(to: url, options: .atomic)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
