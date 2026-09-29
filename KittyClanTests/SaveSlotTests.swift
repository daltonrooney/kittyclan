import XCTest
@testable import KittyClan

final class SaveSlotTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()

    private func makeClan(_ prefix: String, seed: UInt64) -> Clan {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        return founding.found(prefix: prefix, leader: adults[0], deputy: adults[1], medicineCat: adults[2],
                              members: [], preyAndHerbs: false, engine: Self.assets.engine, using: &rng)
    }

    private func slots() throws -> SaveSlots {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return SaveSlots(directory: root.appending(path: "Clans"), legacy: root.appending(path: "clan.json"))
    }

    func testMigratesTheOldSingleSave() async throws {
        let slots = try slots()
        let clan = makeClan("Old", seed: 1)
        try await ClanStore(url: slots.legacy).save(clan)
        let id = try XCTUnwrap(slots.migrateLegacy())
        XCTAssertFalse(FileManager.default.fileExists(atPath: slots.legacy.path(percentEncoded: false)))
        XCTAssertEqual(slots.summaries().map(\.name), ["OldClan"])
        let loaded = try await slots.load(id)
        XCTAssertEqual(loaded?.prefix, "Old")
        XCTAssertNil(try slots.migrateLegacy())
    }

    func testSeveralClansAndDeleting() async throws {
        let slots = try slots()
        let a = UUID(), b = UUID()
        try await slots.save(makeClan("Ash", seed: 2), as: a)
        try await slots.save(makeClan("Birch", seed: 3), as: b)
        XCTAssertEqual(slots.summaries().first?.name, "BirchClan", "most recent first")
        XCTAssertEqual(Set(slots.summaries().map(\.id)), [a, b])
        try slots.delete(a)
        XCTAssertEqual(slots.summaries().map(\.id), [b])
    }
}
