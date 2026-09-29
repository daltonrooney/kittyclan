import XCTest
@testable import KittyClan

final class MediatorTests: XCTestCase {
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

    private func mediator(in clan: inout Clan, using rng: inout SeededRNG) throws -> UUID {
        let warrior = try XCTUnwrap(clan.living.first { $0.rank == .warrior })
        XCTAssertTrue(engine.changeRank(.mediator, for: warrior.id, in: &clan, using: &rng))
        return warrior.id
    }

    func testMediatorCeremoniesLoad() {
        var (clan, rng) = clan(seed: 1)
        let mediator = try! mediator(in: &clan, using: &rng)
        let events = Self.assets.engine.library
        XCTAssertEqual(clan[mediator]?.pastRanks, [.warrior])
        XCTAssertNotNil(events?.ceremony(for: clan[mediator]!, in: clan, using: &rng), "the adult role-switch text fits")
    }

    func testOnlyMediatorsMentorMediatorApprentices() throws {
        var (clan, rng) = clan(seed: 2)
        let mediator = try mediator(in: &clan, using: &rng)
        let apprentice = try XCTUnwrap(clan.living.first { $0.rank == .warrior && $0.id != clan.deputy })
        engine.setRank(.mediatorApprentice, for: apprentice.id, in: &clan, using: &rng)
        XCTAssertEqual(clan[apprentice.id]?.mentor, mediator)
        XCTAssertEqual(MoonEngine.mentorCandidates(for: apprentice.id, in: clan).map(\.id), [mediator])
        XCTAssertEqual(Self.assets.displayName(clan[apprentice.id]!), clan[apprentice.id]!.name.prefix + "paw")
    }

    func testMediationOncePerMoonAndSymmetric() throws {
        var (clan, rng) = clan(seed: 3)
        let mediator = try mediator(in: &clan, using: &rng)
        let pair = clan.living.filter { $0.id != mediator }.prefix(2).map(\.id)
        let (a, b) = (pair[0], pair[1])
        let there = clan.relationship(from: a, to: b), back = clan.relationship(from: b, to: a)
        let lines = try XCTUnwrap(engine.mediate(mediator, a, b, sabotage: false, in: &clan, using: &rng))
        XCTAssertGreaterThanOrEqual(lines.filter { $0.hasSuffix("creased.") }.count, 2)
        for value in RelationshipValue.allCases where value != .romance {
            let forward = (clan.relationship(from: a, to: b)?[value] ?? 0) - (there?[value] ?? 0)
            let backward = (clan.relationship(from: b, to: a)?[value] ?? 0) - (back?[value] ?? 0)
            XCTAssertLessThanOrEqual(abs(forward), 10)
            if abs(forward) < 60, abs(backward) < 60 { XCTAssertEqual(forward, backward, "\(value) changes both ways") }
        }
        XCTAssertEqual(MoonEngine.mediationBlock(mediator, a, b, in: clan), .alreadyWorked)
        XCTAssertNil(engine.mediate(mediator, a, b, sabotage: false, in: &clan, using: &rng))
        engine.advance(&clan, using: &rng)
        if clan.isAlive(mediator), clan.isAlive(a), clan.isAlive(b), clan[mediator]?.isNotWorking == false {
            XCTAssertNil(MoonEngine.mediationBlock(mediator, a, b, in: clan), "resets each moon")
        }
    }

    func testAdultSwitchNeedsTheSetting() {
        var (clan, rng) = clan(seed: 4)
        for _ in 0..<60 { engine.advance(&clan, using: &rng) }
        XCTAssertFalse(clan.history.flatMap(\.entries).contains { $0.text.contains("chosen to become a mediator") })
    }
}
