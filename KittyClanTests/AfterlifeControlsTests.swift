import XCTest
@testable import KittyClan

final class AfterlifeControlsTests: XCTestCase {
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

    func testDeadCatCyclesThroughAfterlives() throws {
        var (clan, rng) = clan(seed: 1)
        let id = try XCTUnwrap(clan.living.first { $0.rank == .warrior }?.id)
        clan.sendToAfterlife(id, history: nil, using: &rng)
        XCTAssertEqual(clan[id]?.afterlife, .starClan)
        var seen: [Afterlife] = []
        for _ in 0..<3 {
            seen.append(try XCTUnwrap(engine.moveToNextAfterlife(id, in: &clan, using: &rng)))
            XCTAssertNotNil(clan[id]?.thought, "a thought about the move")
            XCTAssertNil(clan[id]?.nextThought)
        }
        XCTAssertEqual(seen, [.darkForest, .unknownResidence, .starClan])
        XCTAssertEqual(clan.guideAfterlife, .starClan, "other ghosts don't move the Clan's dead")
        XCTAssertNil(engine.moveToNextAfterlife(clan.leader!, in: &clan, using: &rng), "the living stay put")
    }

    func testAfterlifeChangeThoughtsLoad() throws {
        let (clan, _) = clan(seed: 2)
        var ghost = try XCTUnwrap(clan[clan.guide])
        let context = ThoughtContext(clan: clan)
        for afterlife in Afterlife.allCases {
            ghost.afterlife = afterlife
            XCTAssertFalse(engine.thoughts!.pool(.onAfterlifeChange, for: ghost, in: context).isEmpty, afterlife.rawValue)
        }
    }

    func testMovingTheGuideMovesTheClansDead() throws {
        var (clan, rng) = clan(seed: 3)
        let guide = try XCTUnwrap(clan.guide)
        XCTAssertEqual(engine.moveToNextAfterlife(guide, in: &clan, using: &rng), .darkForest)
        XCTAssertEqual(clan.guideAfterlife, .darkForest)
        XCTAssertNotNil(clan[guide]?.thought)

        let warrior = try XCTUnwrap(clan.living.first { $0.rank == .warrior }?.id)
        clan.sendToAfterlife(warrior, history: nil, using: &rng)
        XCTAssertEqual(clan[warrior]?.afterlife, .darkForest, "the Clan's dead follow the guide")

        let deputy = try XCTUnwrap(clan.deputy)
        let lines = MoonEngine.leaderCeremony(for: deputy, in: clan, library: Self.assets.engine.ceremonies!, using: &rng)
        let intro = try XCTUnwrap(lines.first?.text)
        XCTAssertTrue(engine.ceremonies!.darkForest.intros.flatMap(\.texts).contains(intro), "a Dark Forest guide means a Dark Forest ceremony")

        XCTAssertEqual(engine.moveToNextAfterlife(guide, in: &clan, using: &rng), .starClan, "the guide only moves between StarClan and the Dark Forest")
        XCTAssertEqual(clan.guideAfterlife, .starClan)
    }

    func testDeathReasonIsSanitised() {
        XCTAssertEqual(MoonEngine.sanitizedDeathReason("Fell off\na cliff! 🐈 <b>é</b>"), "Fell offa cliff!  <b></b>")
        XCTAssertEqual(MoonEngine.sanitizedDeathReason("the cat\u{2019}s end"), "the cat's end")
        XCTAssertEqual(MoonEngine.sanitizedDeathReason("|&#(ok)*?,_-/."), "|&#(ok)*?,_-/.")
    }

    func testKillingAWarrior() throws {
        var (clan, rng) = clan(seed: 4)
        let victim = try XCTUnwrap(clan.living.first { $0.rank == .warrior })
        for cat in clan.living where cat.id != victim.id {
            clan.updateRelationship(from: cat.id, to: victim.id) {
                $0.set(.like, 90)
                $0.set(.comfort, 80)
            }
        }
        let logged = clan.history.last?.entries.count ?? 0
        XCTAssertTrue(engine.killCat(victim.id, reason: "m_c was lost to the river\u{2019}s flood.", allLives: false, in: &clan, using: &rng))
        let dead = try XCTUnwrap(clan[victim.id])
        XCTAssertTrue(dead.isDead)
        XCTAssertEqual(dead.afterlife, .starClan)
        XCTAssertEqual(dead.deaths.map(\.text), ["m_c was lost to the river's flood."])
        XCTAssertNotNil(dead.thought)
        XCTAssertEqual(clan.diedThisMoon, [victim.id], "mourned at the end of the next moon")
        let grieving = clan.living.filter { $0.has("grief stricken") }
        XCTAssertEqual((clan.history.last?.entries.count ?? 0) - logged, grieving.count, "each grief-stricken cat's reaction is logged")
        XCTAssertTrue(clan.living.allSatisfy { $0.nextThought == nil })
        XCTAssertFalse(engine.killCat(victim.id, reason: "", allLives: false, in: &clan, using: &rng), "the dead can't die again")

        let other = try XCTUnwrap(clan.living.first { $0.id != clan.leader })
        engine.killCat(other.id, reason: "", allLives: false, in: &clan, using: &rng)
        XCTAssertEqual(clan[other.id]?.deaths.map(\.text), [MoonEngine.defaultKillReason])
    }

    func testKillingTheLeader() throws {
        var (clan, rng) = clan(seed: 5)
        let leader = try XCTUnwrap(clan.leader)
        engine.killCat(leader, reason: "m_c fell.", allLives: false, in: &clan, using: &rng)
        XCTAssertTrue(clan.isAlive(leader))
        XCTAssertEqual(clan.leaderLives, 8)
        XCTAssertEqual(clan[leader]?.deaths.count, 1)

        engine.killCat(leader, reason: "m_c fell again.", allLives: true, in: &clan, using: &rng)
        XCTAssertFalse(clan.isAlive(leader))
        XCTAssertEqual(clan.leaderLives, 0)
        XCTAssertEqual(clan[leader]?.deaths.map(\.text), ["m_c fell."] + Array(repeating: "m_c fell again.", count: 8))
        let history = Self.assets.afterlifeText.deaths(of: clan[leader]!, in: clan)
        XCTAssertTrue(history.joined().contains("Ninth life") || history.joined().contains("ninth"), history.joined(separator: "\n"))
    }

    func testRemovingAccessories() throws {
        var (clan, _) = clan(seed: 6)
        let id = try XCTUnwrap(clan.living.first?.id)
        let i = try XCTUnwrap(clan.index(of: id))
        clan.cats[i].appearance.accessories = ["MAPLE LEAF", "CRIMSON"]
        clan.removeAccessories(from: id)
        XCTAssertEqual(clan[id]?.appearance.accessories, [])
    }
}
