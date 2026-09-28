import XCTest
@testable import KittyClan

final class SupplyTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }

    private func clan(seed: UInt64, preyAndHerbs: Bool = true, canStarve: Bool = false) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), preyAndHerbs: preyAndHerbs, canStarve: canStarve, engine: engine, using: &rng
        )
        return (clan, rng)
    }

    func testOlderSavesStillLoad() throws {
        let (clan, _) = clan(seed: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clan)) as? [String: Any])
        for key in ["preyAndHerbs", "canStarve", "freshKill", "nutrition", "herbs", "outsiders", "patrolledThisMoon", "relationships"] {
            json[key] = nil
        }
        json["cats"] = (json["cats"] as? [[String: Any]])?.map { cat in
            var cat = cat
            for key in ["skills", "conditions", "previousMates"] { cat[key] = nil }
            return cat
        }
        let decoded = try JSONDecoder().decode(Clan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.cats.count, clan.cats.count)
        XCTAssertFalse(decoded.preyAndHerbs, "old Clans keep Clangen's classic rules")
    }

    func testPileSpoilsOldestFirst() {
        var pile = FreshKillPile()
        pile.add(10)
        _ = pile.age()
        pile.add(5)
        XCTAssertEqual(pile.take(12), 12)
        XCTAssertEqual(pile.total, 3, accuracy: 0.001)
        XCTAssertEqual(pile.expiresIn3, 3, accuracy: 0.001, "the older prey was eaten first")
        _ = pile.age()
        _ = pile.age()
        XCTAssertEqual(pile.age(), 3, accuracy: 0.001, "prey spoils after three moons")
    }

    func testFoundingStocksTheClan() {
        let (expanded, _) = clan(seed: 2)
        XCTAssertEqual(expanded.freshKill.total, FreshKillPile.startingAmount)
        XCTAssertEqual(expanded.nutrition.count, expanded.living.count)
        let (classic, _) = clan(seed: 2, preyAndHerbs: false)
        XCTAssertEqual(classic.freshKill.total, 0)
    }

    private func starve(canStarve: Bool) -> (deaths: Int, starving: Int) {
        var (clan, rng) = clan(seed: 5, canStarve: canStarve)
        var starving = 0
        for _ in 0..<12 {
            clan.freshKill = FreshKillPile()
            engine.advance(&clan, using: &rng)
            clan.freshKill = FreshKillPile()
            starving = max(starving, clan.living.filter { $0.has("starving") || $0.has("malnourished") }.count)
        }
        let deaths = clan.history.flatMap(\.entries).filter { $0.kind == .death && $0.text.lowercased().contains("starv") }.count
        return (deaths, starving)
    }

    func testStarvationOnlyKillsWhenEnabled() {
        let gentle = starve(canStarve: false)
        XCTAssertEqual(gentle.deaths, 0, "hungry cats don't die when starvation is off")
        XCTAssertGreaterThan(gentle.starving, 0, "cats still get hungry")
        let harsh = starve(canStarve: true)
        XCTAssertGreaterThan(harsh.deaths, 0)
    }

    func testLongRunWithPreyAndHerbs() {
        var herbsUsed = 0
        var hungry = 0
        var catMoons = 0
        for seed in 20...23 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            for _ in 0..<120 {
                engine.advance(&clan, using: &rng)
                XCTAssertGreaterThanOrEqual(clan.freshKill.total, 0)
                XCTAssertEqual(Set(clan.nutrition.keys), Set(clan.living.map(\.id)))
                for (herb, batches) in clan.herbs.storage {
                    XCTAssertTrue(batches.allSatisfy { $0 >= 0 }, herb)
                }
                herbsUsed += clan.herbs.log.filter { $0.contains("was given") }.count
                catMoons += clan.living.count
                hungry += clan.living.filter { $0.has("malnourished") || $0.has("starving") }.count
                for entry in clan.history.last?.entries ?? [] {
                    XCTAssertFalse(entry.text.contains("{") || entry.text.contains("m_c"), entry.text)
                }
                if clan.living.count > 50 { break }
            }
        }
        print("herb treatments:", herbsUsed, "hungry cat-moons:", hungry, "of", catMoons)
        XCTAssertGreaterThan(herbsUsed, 0)
    }

    func testHuntingAddsPrey() throws {
        var (clan, rng) = clan(seed: 8)
        var gained = 0.0
        for _ in 0..<10 {
            clan.patrolledThisMoon = []
            let hunters = PatrolEngine.eligible(in: clan).filter { $0.rank == .warrior || $0.rank == .deputy }.prefix(3).map(\.id)
            guard !hunters.isEmpty, let session = Self.assets.patrols.start(Array(hunters), type: .hunting, in: &clan, using: &rng) else { continue }
            let before = clan.freshKill.total
            _ = Self.assets.patrols.finish(session, choice: .proceed, in: &clan, using: &rng)
            gained += clan.freshKill.total - before
        }
        XCTAssertGreaterThan(gained, 0)
    }
}
