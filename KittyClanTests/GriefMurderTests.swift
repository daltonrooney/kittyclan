import XCTest
@testable import KittyClan

final class GriefMurderTests: XCTestCase {
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

    private func assertResolved(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for token in ["{", "}", "m_c", "r_c", "mur_c", "c_n", "multi_cat"] where text.contains(token) {
            XCTFail("unresolved \(token): \(text)", file: file, line: line)
        }
    }

    func testLovedOnesGrieve() throws {
        var grieved = 0
        for seed in 1...8 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            let victim = try XCTUnwrap(clan.living.first { $0.id != clan.leader })
            for cat in clan.living where cat.id != victim.id {
                clan.updateRelationship(from: cat.id, to: victim.id) {
                    $0.set(.like, 90)
                    $0.set(.comfort, 80)
                }
            }
            let events = engine.loseLifeOrDie(victim.id, cause: .misfortune, in: &clan, using: &rng)
            let stricken = clan.living.filter { $0.has("grief stricken") }
            let thinking = clan.living.filter { $0.nextThought == .onGriefTowardBody && $0.nextThoughtAbout == victim.id }
            grieved += stricken.count + thinking.count
            XCTAssertGreaterThanOrEqual(events.count - 1, stricken.count, "each grief-stricken cat gets a reaction line")
            for event in events {
                assertResolved(engine.narrator.text(for: event, in: clan, using: &rng))
            }
            XCTAssertEqual(clan.diedThisMoon, [victim.id])
            engine.advance(&clan, using: &rng)
            XCTAssertTrue(clan.history.last!.entries.contains { $0.text.contains("mourns") }, "the moon ends with mourning")
            XCTAssertTrue(clan.diedThisMoon.isEmpty)
        }
        XCTAssertGreaterThan(grieved, 20)
    }

    func testMurderIsRecordedAndCanComeToLight() throws {
        var murdered = false
        for seed in 1...10 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            let cats = clan.living.filter { $0.id != clan.leader && $0.moons >= 12 }
            let murderer = cats[0].id, victim = cats[1].id
            var counts: [UUID: Int] = [:]
            let events = engine.murder(victim, by: murderer, in: &clan, counts: &counts, using: &rng)
            guard !events.isEmpty else { continue }
            murdered = true
            XCTAssertFalse(clan.isAlive(victim))
            XCTAssertEqual(clan[murderer]?.murders.first?.victim, victim)
            XCTAssertEqual(clan[victim]?.murders.first?.murderer, murderer)
            XCTAssertLessThan(clan[murderer]?.starClanAffinity ?? 0, 0)
            let text = Self.assets.afterlifeText
            XCTAssertTrue(text.murders(by: clan[murderer]!, in: clan).first?.contains("The Clan is unaware.") == true)
            XCTAssertTrue(text.deaths(of: clan[victim]!, in: clan).first?.contains("The Clan is unaware.") == true)

            for i in clan.pendingEvents.indices { clan.pendingEvents[i].moonsLeft = 1 }
            let hadReveal = !clan.pendingEvents.isEmpty
            for _ in 0..<13 where clan.isAlive(murderer) { engine.advance(&clan, using: &rng) }
            if hadReveal, clan.isAlive(murderer), let record = clan[murderer]?.murders.first {
                XCTAssertTrue(record.revealedToClan || !record.aware.isEmpty, "the murder came to light")
            }
            for entry in clan.history.flatMap(\.entries) { assertResolved(entry.text) }
        }
        XCTAssertTrue(murdered, "some murder story fits")
    }

    func testMurderCanBeTurnedOff() throws {
        var (clan, rng) = clan(seed: 3)
        clan.allowMurder = false
        let cat = try XCTUnwrap(clan.living.first)
        var counts: [UUID: Int] = [:]
        for _ in 0..<200 {
            XCTAssertTrue(engine.handleMurder(by: cat.id, in: &clan, counts: &counts, using: &rng).isEmpty)
        }
    }

    func testLongRunStaysResolved() {
        var (clan, rng) = clan(seed: 9)
        for _ in 0..<120 { engine.advance(&clan, using: &rng) }
        for entry in clan.history.flatMap(\.entries) { assertResolved(entry.text) }
    }
}
