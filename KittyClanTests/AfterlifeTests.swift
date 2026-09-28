import XCTest
@testable import KittyClan

final class AfterlifeTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }
    private var text: AfterlifeText { Self.assets.afterlifeText }

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

    private func assertResolved(_ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        for text in lines {
            for token in ["{", "}", "m_c", "r_c", "c_n", "[virtue]", "[life_num]"] where text.contains(token) {
                XCTFail("unresolved \(token): \(text)", file: file, line: line)
            }
        }
    }

    func testFoundingCreatesGuideAndCeremony() throws {
        let (clan, _) = clan(seed: 1)
        let guide = try XCTUnwrap(clan[clan.guide])
        XCTAssertTrue(guide.isDead)
        XCTAssertEqual(guide.afterlife, .starClan)
        XCTAssertTrue((20...200).contains(guide.deadFor))
        XCTAssertNotNil(text.backstory(of: guide, in: clan))
        XCTAssertEqual(clan.residents(of: .starClan).first?.id, guide.id)

        let leader = try XCTUnwrap(clan[clan.leader])
        let ceremony = leader.leaderCeremony
        XCTAssertEqual(ceremony.filter { $0.giver == guide.id && $0.virtue != nil }.count, 1, "the guide gives one life")
        XCTAssertEqual(ceremony.compactMap(\.extraLives), [8], "an unknown blessing gives the other eight")
        let paragraphs = text.ceremony(of: leader, in: clan)
        XCTAssertGreaterThanOrEqual(paragraphs.count, 3)
        assertResolved(paragraphs)
        XCTAssertTrue(paragraphs.joined().contains(leader.name.prefix + "star"))
    }

    func testOpacityAndFadeStages() {
        var rng = SeededRNG(seed: 1)
        var cat = Self.assets.factory.make(rank: .warrior, using: &rng)
        cat.isDead = true
        let expected = [0: 100, 50: 99, 97: 97, 120: 94, 150: 81, 152: 80, 180: 55, 187: 45, 200: 23, 202: 20]
        for (deadFor, opacity) in expected {
            cat.deadFor = deadFor
            XCTAssertEqual(cat.opacity, opacity, "dead for \(deadFor)")
        }
        cat.deadFor = 96
        XCTAssertNil(cat.fadeStage)
        cat.deadFor = 97
        XCTAssertEqual(cat.fadeStage, 0)
        cat.deadFor = 152
        XCTAssertEqual(cat.fadeStage, 1)
        cat.deadFor = 187
        XCTAssertEqual(cat.fadeStage, 2)
    }

    func testNegativeAffinityCanBeRejected() {
        var rng = SeededRNG(seed: 3)
        var murderer = Self.assets.factory.make(rank: .warrior, using: &rng)
        murderer.starClanAffinity = -100
        murderer.enterAfterlife(.starClan, moon: 5, using: &rng)
        XCTAssertEqual(murderer.afterlife, .darkForest)
        XCTAssertTrue(murderer.afterlifeAcceptance?.hasPrefix("starclan_rejected_") == true)

        var kit = Self.assets.factory.make(rank: .kitten, using: &rng)
        kit.starClanAffinity = -100
        kit.enterAfterlife(.starClan, moon: 5, using: &rng)
        XCTAssertEqual(kit.afterlife, .starClan, "kits are always accepted")
    }

    func testDeadAgeAndFade() throws {
        var (clan, rng) = clan(seed: 2)
        let victim = try XCTUnwrap(clan.living.first { $0.id != clan.leader })
        _ = engine.loseLifeOrDie(victim.id, cause: .misfortune, history: "m_c fell from a tree.", in: &clan, using: &rng)
        let dead = try XCTUnwrap(clan[victim.id])
        XCTAssertEqual(dead.afterlife, .starClan)
        XCTAssertEqual(text.deaths(of: dead, in: clan), ["\(Self.assets.displayName(dead)) fell from a tree. (moon 0)"])
        XCTAssertNotNil(text.acceptance(of: dead, in: clan))

        engine.advance(&clan, using: &rng)
        XCTAssertEqual(clan[victim.id]?.deadFor, 1)

        let i = try XCTUnwrap(clan.index(of: victim.id))
        clan.cats[i].deadFor = Afterlife.ageToFade
        let guideAge = clan[clan.guide]?.deadFor
        engine.advance(&clan, using: &rng)
        XCTAssertNil(clan[victim.id], "faded cats leave the Clan")
        XCTAssertEqual(clan.faded.map(\.id), [victim.id])
        XCTAssertNotNil(clan[clan.guide], "the guide never fades")
        XCTAssertEqual(clan[clan.guide]?.deadFor, guideAge.map { $0 + 1 })
    }

    func testLeaderLivesAreNumbered() throws {
        var (clan, rng) = clan(seed: 5)
        let leader = try XCTUnwrap(clan.leader)
        _ = engine.loseLifeOrDie(leader, cause: .misfortune, history: "m_c was struck by lightning.", in: &clan, using: &rng)
        let lines = text.deaths(of: try XCTUnwrap(clan[leader]), in: clan)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("First life: "), lines[0])
    }

    func testLongRunKeepsAfterlifeConsistent() {
        var (clan, rng) = clan(seed: 7)
        for _ in 0..<150 { engine.advance(&clan, using: &rng) }
        let dead = clan.afterlifeCats
        XCTAssertFalse(dead.isEmpty)
        for cat in dead {
            XCTAssertNotNil(cat.afterlife)
            if cat.id != clan.guide, clan.cats.contains(where: { $0.id == cat.id }) {
                XCTAssertFalse(cat.deaths.isEmpty, "\(cat.name) has a death record")
                assertResolved(text.deaths(of: cat, in: clan))
            }
            XCTAssertNotNil(Self.assets.sprite(for: cat))
        }
        if let leader = clan[clan.leader] {
            XCTAssertFalse(leader.leaderCeremony.isEmpty)
            assertResolved(text.ceremony(of: leader, in: clan))
        }
    }

    func testGhostSpritesDiffer() throws {
        var rng = SeededRNG(seed: 9)
        let cat = Self.assets.factory.make(rank: .warrior, using: &rng)
        let renderer = Self.assets.renderer
        let alive = try renderer.render(cat.appearance, age: cat.age)
        var sprites = [alive]
        for afterlife in Afterlife.allCases {
            sprites.append(try renderer.render(cat.appearance, age: cat.age, ghost: .init(afterlife: afterlife)))
            sprites.append(try renderer.render(cat.appearance, age: cat.age, ghost: .init(afterlife: afterlife, fadeStage: 2)))
            _ = try renderer.renderFaded(age: .adult, afterlife: afterlife)
        }
        XCTAssertEqual(Set(sprites.map(\.bytes)).count, sprites.count)
    }
}
