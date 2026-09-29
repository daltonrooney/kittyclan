import XCTest
@testable import KittyClan

final class FocusTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }

    private func clan(seed: UInt64, preyAndHerbs: Bool = true) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), preyAndHerbs: preyAndHerbs, engine: engine, using: &rng
        )
        return (clan, rng)
    }

    func testCooldownAndGates() {
        var (clan, _) = clan(seed: 1)
        XCTAssertTrue(engine.setFocus(.hunting, in: &clan))
        XCTAssertFalse(engine.setFocus(.restAndRecover, in: &clan), "three moons between changes")
        clan.age += 3
        XCTAssertTrue(engine.setFocus(.restAndRecover, in: &clan))

        XCTAssertEqual(clan.focusBlock(.sabotageOtherClans), .needsMediator)
        clan.age += 3
        XCTAssertFalse(engine.setFocus(.raidOtherClans, in: &clan), "raids need a target")
        XCTAssertTrue(engine.setFocus(.raidOtherClans, targets: [clan.otherClans[0].id], in: &clan))

        var (classic, _) = self.clan(seed: 2, preyAndHerbs: false)
        XCTAssertEqual(classic.focusBlock(.hunting), .needsPreyAndHerbs)
        classic.deputy = nil
        XCTAssertEqual(classic.focusBlock(.seekOutsiders), .needsDeputy)
    }

    func testHuntingAddsItsCatchInsteadOfThePassiveOne() {
        var (clan, rng) = clan(seed: 3)
        engine.setFocus(.hunting, in: &clan)
        let expected = MoonEngine.huntingFocusCatch(in: clan)
        var herbLog: [String] = []
        let before = clan.freshKill.total
        let events = engine.focusMoon(in: &clan, herbLog: &herbLog, using: &rng)
        XCTAssertEqual(clan.freshKill.total - before, expected)
        XCTAssertEqual(events.count, 1)
    }

    func testOutsiderAndClanRelations() {
        var (clan, rng) = clan(seed: 4)
        var herbLog: [String] = []
        clan.focus = .seekOutsiders
        clan.reputation = 98
        _ = engine.focusMoon(in: &clan, herbLog: &herbLog, using: &rng)
        XCTAssertEqual(clan.reputation, 100)
        clan.focus = .threatenOutsiders
        _ = engine.focusMoon(in: &clan, herbLog: &herbLog, using: &rng)
        XCTAssertEqual(clan.reputation, 95)

        let target = clan.otherClans[0].id
        let relations = clan.otherClans[0].relations
        clan.focus = .raidOtherClans
        clan.focusTargets = [target]
        _ = engine.focusMoon(in: &clan, herbLog: &herbLog, using: &rng)
        XCTAssertEqual(clan.otherClan(target)?.relations, relations - 3)
    }

    func testRestAndRecoverHealsAMoonEarly() throws {
        var (clan, rng) = clan(seed: 5)
        let id = try XCTUnwrap(clan.living.first { $0.id != clan.leader }?.id)
        XCTAssertTrue(engine.getInjured(id, "bruises", lethal: false, in: &clan, using: &rng))
        let i = try XCTUnwrap(clan.index(of: id))
        let c = try XCTUnwrap(clan.cats[i].conditions.firstIndex { $0.name == "bruises" })
        clan.cats[i].conditions[c].duration = 3
        clan.cats[i].conditions[c].complication = nil
        clan.cats[i].conditions[c].risks = []
        clan.cats[i].conditions[c].mortality = 0
        clan.focus = .restAndRecover
        var skip: Set<String> = []
        for _ in 0..<2 {
            clan.age += 1
            _ = engine.progressConditions(for: id, skip: &skip, in: &clan, using: &rng)
        }
        XCTAssertFalse(clan[id]?.has("bruises") ?? true)
    }

    func testLongRunWithEachFocus() {
        for focus in ClanFocus.allCases {
            var (clan, rng) = clan(seed: 6)
            clan.focus = focus
            clan.focusTargets = focus.targetsOtherClans ? [clan.otherClans[0].id] : []
            for _ in 0..<24 { engine.advance(&clan, using: &rng) }
            for entry in clan.history.flatMap(\.entries) {
                XCTAssertFalse(entry.text.contains("{") || entry.text.contains("r_c"), "\(focus): \(entry.text)")
            }
        }
    }
}
