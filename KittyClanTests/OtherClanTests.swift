import XCTest
@testable import KittyClan

final class OtherClanTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }

    private func clan(seed: UInt64) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), preyAndHerbs: false, engine: engine, using: &rng
        )
        return (clan, rng)
    }

    private func assertResolved(_ clan: Clan, file: StaticString = #filePath, line: UInt = #line) {
        for entry in clan.history.flatMap(\.entries) {
            for token in ["{", "m_c", "r_c", "o_c_n", "n_c", "c_n", "cat_from", "multi_cat"] where entry.text.contains(token) {
                XCTFail("unresolved \(token): \(entry.text)", file: file, line: line)
            }
        }
    }

    func testFoundingCreatesNeighbours() {
        let (clan, _) = clan(seed: 1)
        XCTAssertTrue((3...5).contains(clan.otherClans.count))
        XCTAssertEqual(Set(clan.otherClans.map(\.prefix)).count, clan.otherClans.count, "names are unique")
        XCTAssertEqual(Set(clan.otherClans.flatMap(\.temperament)).count, clan.otherClans.count * 2, "temperaments are unique")
        XCTAssertTrue(clan.otherClans.allSatisfy { $0.standing == .neutral })
        XCTAssertFalse(clan.otherClans.contains { $0.prefix == "Thunder" || $0.prefix == "River" })
    }

    func testStandingThresholds() {
        var other = OtherClan(prefix: "Pine", relations: 7, temperament: ["wary", "eager"])
        XCTAssertEqual(other.standing, .hostile)
        other.setRelations(17)
        XCTAssertEqual(other.standing, .neutral)
        other.setRelations(45)
        XCTAssertEqual(other.relations, 30, "relations are capped at 30")
        XCTAssertEqual(other.standing, .ally)
    }

    func testHostileNeighboursGoToWarAndMakePeace() {
        var (clan, rng) = clan(seed: 4)
        for i in clan.otherClans.indices { clan.otherClans[i].setRelations(1) }
        var sawWar = false
        var sawPeace = false
        for _ in 0..<60 {
            engine.advance(&clan, using: &rng)
            if clan.war.atWar { sawWar = true } else if sawWar { sawPeace = true }
        }
        XCTAssertTrue(sawWar)
        XCTAssertTrue(sawPeace)
        XCTAssertTrue(clan.history.flatMap(\.entries).contains { $0.kind == .clans })
        assertResolved(clan)
    }

    func testLeaderDenChangesRelationsNextMoon() {
        var (clan, rng) = clan(seed: 6)
        var outcomes = 0
        for _ in 0..<20 {
            let target = clan.otherClans[0]
            let (_, friendly) = MoonEngine.leaderDenActions(for: target.standing)
            engine.planLeaderDen(friendly, target: .clan(target.id), in: &clan, using: &rng)
            XCTAssertNotNil(clan.leaderDenPlan)
            engine.advance(&clan, using: &rng)
            XCTAssertNil(clan.leaderDenPlan)
            outcomes += clan.history.last!.entries.filter { $0.kind == .clans && $0.text.contains("relations") }.count
        }
        XCTAssertGreaterThan(outcomes, 10)
        assertResolved(clan)
    }

    func testLostCatsFindTheirWayHome() {
        var (clan, rng) = clan(seed: 9)
        let warrior = clan.living.first { $0.rank == .warrior }!.id
        engine.loseCat(warrior, in: &clan, using: &rng)
        XCTAssertFalse(clan.isAlive(warrior))
        XCTAssertTrue(clan.outsiders.contains { $0.id == warrior && $0.isLost })
        for _ in 0..<120 where !clan.isAlive(warrior) {
            engine.advance(&clan, using: &rng)
            if clan.outsiders.first(where: { $0.id == warrior })?.isDead == true { return }
        }
        XCTAssertTrue(clan.isAlive(warrior), "a lost cat returns 1 moon in 20")
        XCTAssertEqual(clan[warrior]?.rank, .warrior, "and gets its rank back")
    }

    func testExiledCatsStayOut() {
        var (clan, rng) = clan(seed: 10)
        let deputy = clan.deputy!
        engine.exileCat(deputy, in: &clan, using: &rng)
        XCTAssertNil(clan.deputy)
        XCTAssertTrue(clan.outsiders.first { $0.id == deputy }?.isExiled == true)
        for _ in 0..<40 { engine.advance(&clan, using: &rng) }
        XCTAssertFalse(clan.isAlive(deputy))
        XCTAssertNotNil(clan.deputy, "a new deputy is chosen")
    }

    func testNewCatsArriveThroughClangenStories() {
        var joins = 0
        var met = 0
        for seed in 20...25 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            for _ in 0..<100 {
                engine.advance(&clan, using: &rng)
                if clan.living.count > 40 { break }
            }
            joins += clan.history.flatMap(\.entries).filter { $0.kind == .join }.count
            met += clan.outsiders.count
            assertResolved(clan)
        }
        print("joins:", joins, "outsiders known:", met, "new cat events:", engine.library!.newCatCount)
        XCTAssertGreaterThan(joins, 5)
        XCTAssertGreaterThan(engine.library!.newCatCount, 40)
    }

    func testMoreContentLoads() {
        let library = engine.library!
        print("misc:", library.miscCount, "deaths:", library.deathCount, "injury:", library.injuryCount)
        XCTAssertGreaterThan(library.miscCount, 200)
        XCTAssertGreaterThan(Self.assets.patrols.library.otherClanPatrols.values.reduce(0) { $0 + $1.count }, 25)
    }
}
