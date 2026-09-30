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

    func testEveryBiomeLoadsItsOwnEvents() throws {
        let library = try XCTUnwrap(engine.library)
        let text = try XCTUnwrap(Bundle.main.url(forResource: "Text", withExtension: nil))
        for biome in Biome.allCases {
            for type in ["death", "injury", "misc", "new_cat"] {
                let data = try Data(contentsOf: text.appending(path: "\(type)/\(biome.key).json"))
                let ids = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []).compactMap { $0["event_id"] as? String }
                let loaded = ids.filter(library.eventIDs.contains)
                XCTAssertFalse(loaded.isEmpty, "\(biome) \(type)")
                print("\(biome) \(type): \(loaded.count) of \(ids.count) events load")
            }
        }
    }

    func testWetlandsAndDesertBorrowCampArt() {
        let camps = Self.assets.camps
        let pairs: [(Biome, Int, Biome, Int)] = [
            (.wetlands, 1, .plains, 3), (.wetlands, 2, .beach, 1), (.wetlands, 3, .forest, 4), (.wetlands, 4, .mountainous, 3),
            (.desert, 1, .mountainous, 1), (.desert, 2, .plains, 2), (.desert, 3, .mountainous, 4), (.desert, 4, .plains, 4),
        ]
        for (biome, camp, source, sourceCamp) in pairs {
            XCTAssertEqual(
                camps.background(biome: biome, camp: camp, season: .leafFall, dark: true),
                camps.background(biome: source, camp: sourceCamp, season: .leafFall, dark: true)
            )
            XCTAssertEqual(camps.layout(biome: biome, camp: camp)?.labels, camps.layout(biome: source, camp: sourceCamp)?.labels)
        }
        XCTAssertEqual(Biome.wetlands.campNames.count, 4)
        XCTAssertEqual(Biome.desert.campNames.count, 4)
        XCTAssertEqual(Biome(rawValue: "Wetlands"), .wetlands)
        XCTAssertEqual(Biome(rawValue: "Desert"), .desert)
    }

    func testUntaggedDesertPatrolsStayInTheDesert() throws {
        let patrols = Self.assets.patrols.library
        let folder = try XCTUnwrap(Bundle.main.url(forResource: "Text", withExtension: nil)).appending(path: "patrols/desert")
        var untagged: Set<String> = []
        for case let url as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)! where url.pathExtension == "json" {
            let list = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] ?? []
            untagged.formUnion(list.filter { ($0["location"] as? [String] ?? []).isEmpty }.compactMap { $0["event_id"] as? String })
        }
        XCTAssertEqual(untagged.count, 7)
        var seen: Set<String> = []
        for type in PatrolType.allCases {
            for season in Season.allCases {
                for biome in Biome.allCases {
                    let found = patrols.patrols(for: type, season: season, biome: biome).filter { untagged.contains($0.id) }
                    if biome == .desert {
                        seen.formUnion(found.map(\.id))
                        for patrol in found { XCTAssertEqual(patrol.location, ["desert"], patrol.id) }
                    } else {
                        XCTAssertTrue(found.isEmpty, "\(biome): \(found.map(\.id))")
                    }
                }
            }
        }
        XCTAssertFalse(seen.isEmpty)
    }

    func testBorrowedHerbsPlatformsAndPrey() throws {
        let herbs = try XCTUnwrap(engine.herbLibrary)
        for herb in herbs.herbs {
            for season in Season.allCases {
                XCTAssertEqual(herb.rarity(in: .wetlands, season), herb.rarity(in: .beach, season))
                XCTAssertEqual(herb.rarity(in: .desert, season), herb.rarity(in: .plains, season))
            }
        }
        for biome in Biome.allCases {
            _ = ProfilePlatform(biome: biome, season: .greenleaf, nest: false, afterlife: nil, dark: false)
        }
        let prey = Self.assets.patrols.library.prey
        for abbr in ["w_tp_dl_s", "w_mp_dl_p", "w_mp_a_p", "d_tp_s", "d_mp_p", "d_bp_p"] {
            XCTAssertFalse(prey[abbr, default: []].isEmpty, abbr)
        }
        XCTAssertNotEqual(prey["w_mp_dl_p"], prey["w_mp_dl_s"], "the plural list is plural")
        let audio = AudioLibrary.bundled
        XCTAssertEqual(audio.campOverlays(biome: .wetlands, camp: 3), audio.campOverlays(biome: .forest, camp: 4))
        XCTAssertEqual(audio.ambienceBase(for: .clan(biome: .desert, camp: 1, season: .newleaf)), audio.ambienceBase(for: .clan(biome: .plains, camp: 1, season: .newleaf)))
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
            var (clan, rng) = clan(biome, camp: index % 4 + 1, seed: UInt64(10 + index))
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
