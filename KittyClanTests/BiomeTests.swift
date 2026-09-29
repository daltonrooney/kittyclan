import XCTest
@testable import KittyClan

final class BiomeTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }

    private func clan(_ biome: Biome, camp: Int = 1, seed: UInt64) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), preyAndHerbs: true, biome: biome, camp: camp, engine: engine, using: &rng
        )
        return (clan, rng)
    }

    func testLocationFilterMatchesClangen() {
        XCTAssertTrue(Constraint.locationAllows(["forest"], biome: .forest, camp: 1))
        XCTAssertFalse(Constraint.locationAllows(["forest:camp2"], biome: .forest, camp: 1))
        XCTAssertTrue(Constraint.locationAllows(["forest:camp1_camp2"], biome: .forest, camp: 2))
        XCTAssertTrue(Constraint.locationAllows(["-desert"], biome: .beach, camp: 1))
        XCTAssertFalse(Constraint.locationAllows(["-plains:camp3"], biome: .plains, camp: 3))
        XCTAssertTrue(Constraint.locationAllows(["-plains:camp3"], biome: .plains, camp: 1))
        XCTAssertFalse(Constraint.locationAllows(["forest", "plains", "-plains:camp3"], biome: .forest, camp: 1), "Clangen treats mixed lists as exclusions")
        XCTAssertTrue(Constraint.locationAllows(["any"], biome: .mountainous, camp: 4))
        XCTAssertTrue(Constraint.locationAllows(nil, biome: .mountainous, camp: 4))
    }

    func testOldSavesAreForest() throws {
        let (clan, _) = clan(.beach, seed: 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clan)) as! [String: Any]
        json["biome"] = nil
        let decoded = try JSONDecoder().decode(Clan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.biome, .forest)
    }

    func testEveryBiomeHasPatrolsCampsAndHerbs() throws {
        let patrols = Self.assets.patrols.library
        let herbs = try XCTUnwrap(engine.herbLibrary)
        for biome in Biome.allCases {
            for season in Season.allCases {
                for type in PatrolType.allCases {
                    XCTAssertFalse(patrols.patrols(for: type, season: season, biome: biome).isEmpty, "\(biome) \(season) \(type)")
                }
                XCTAssertTrue(herbs.herbs.contains { $0.rarity(in: biome, season) > 0 }, "\(biome) \(season) herbs")
                for camp in 1...4 {
                    for dark in [false, true] {
                        let url = Self.assets.camps.background(biome: biome, camp: camp, season: season, dark: dark)
                        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
                    }
                }
            }
            for camp in 1...4 { XCTAssertNotNil(Self.assets.camps.layout(biome: biome, camp: camp)) }
        }
    }

    func testBiomeEventsStayInTheirBiome() {
        let forestOnly = ["forest"]
        XCTAssertTrue(Constraint.locationAllows(forestOnly, biome: .forest, camp: 3))
        for biome in Biome.allCases where biome != .forest {
            XCTAssertFalse(Constraint.locationAllows(forestOnly, biome: biome, camp: 1))
        }
    }

    func testEachBiomeRunsWithPatrolsAndResolvedText() throws {
        for (index, biome) in Biome.allCases.enumerated() {
            var (clan, rng) = clan(biome, camp: index + 1, seed: UInt64(10 + index))
            for moon in 0..<30 {
                if moon % 2 == 0 {
                    let cats = PatrolEngine.eligible(in: clan).prefix(3).map(\.id)
                    if let session = Self.assets.patrols.start(Array(cats), type: .hunting, in: &clan, using: &rng) {
                        let result = Self.assets.patrols.finish(session, choice: .proceed, in: &clan, using: &rng)
                        for line in [session.intro, result.text] {
                            XCTAssertNil(line.range(of: #"[bdfmpw]_(tp|mp|bp)"#, options: .regularExpression), "\(biome): \(line)")
                        }
                    }
                }
                engine.advance(&clan, using: &rng)
            }
            for entry in clan.history.flatMap(\.entries) {
                XCTAssertFalse(entry.text.contains("{") || entry.text.contains("m_c") || entry.text.contains("r_c"), "\(biome): \(entry.text)")
            }
        }
    }
}
