import Foundation

/// A saved Clan as shown in the Clan chooser, without loading the whole save.
struct SaveSummary: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var moon: Int
    var living: Int
    var season: Season
    var leader: CatAppearance?
    var savedAt: Date

    init(id: UUID, clan: Clan, savedAt: Date = .now) {
        self.id = id
        name = clan.displayName
        moon = clan.age
        living = clan.living.count
        season = clan.season
        leader = clan[clan.leader].map(\.appearance)
        self.savedAt = savedAt
    }
}

/// Several saved Clans in Application Support/Clans: `<id>.json` holds the Clan and
/// `<id>.summary.json` what the chooser shows. The old single `clan.json` becomes the first slot.
struct SaveSlots: Sendable {
    let directory: URL
    let legacy: URL

    static let standard = SaveSlots(
        directory: .applicationSupportDirectory.appending(path: "Clans"),
        legacy: .applicationSupportDirectory.appending(path: "clan.json")
    )

    func store(for id: UUID) -> ClanStore {
        ClanStore(url: directory.appending(path: "\(id.uuidString).json"))
    }

    private func summaryURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).summary.json")
    }

    /// Moves a save from before slots existed into its own slot. Returns its id if there was one.
    @discardableResult
    func migrateLegacy() throws -> UUID? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return nil }
        let clan = try JSONDecoder().decode(Clan.self, from: Data(contentsOf: legacy))
        let id = UUID()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.moveItem(at: legacy, to: store(for: id).url)
        try writeSummary(SaveSummary(id: id, clan: clan))
        return id
    }

    /// Every saved Clan, most recently played first.
    func summaries() -> [SaveSummary] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(".summary.json") }
            .compactMap { try? JSONDecoder().decode(SaveSummary.self, from: Data(contentsOf: $0)) }
            .filter { fm.fileExists(atPath: store(for: $0.id).url.path(percentEncoded: false)) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func load(_ id: UUID) async throws -> Clan? {
        try await store(for: id).load()
    }

    func save(_ clan: Clan, as id: UUID) async throws {
        try await store(for: id).save(clan)
        try writeSummary(SaveSummary(id: id, clan: clan))
    }

    func delete(_ id: UUID) throws {
        try store(for: id).delete()
        let summary = summaryURL(for: id)
        if FileManager.default.fileExists(atPath: summary.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: summary)
        }
    }

    private func writeSummary(_ summary: SaveSummary) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(summary).write(to: summaryURL(for: summary.id), options: .atomic)
    }
}
