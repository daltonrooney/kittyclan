import XCTest
@testable import KittyClan

final class BalanceTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()

    private func meanLiving(afterMoons moons: Int, preyAndHerbs: Bool, seeds: ClosedRange<UInt64> = 1...6) -> Double {
        let total = seeds.map { seed in
            var rng = SeededRNG(seed: seed)
            let founding = Self.assets.founding
            let candidates = founding.candidates(using: &rng)
            let adults = candidates.filter(ClanFounding.canLead)
            let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
            var clan = founding.found(
                prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
                members: Array(others.prefix(7)), preyAndHerbs: preyAndHerbs, engine: Self.assets.engine, using: &rng
            )
            for _ in 0..<moons { Self.assets.engine.advance(&clan, using: &rng) }
            return clan.living.count
        }.reduce(0, +)
        return Double(total) / Double(seeds.count)
    }

    func testClanLeftAloneDoesNotDwindle() {
        XCTAssertGreaterThanOrEqual(meanLiving(afterMoons: 80, preyAndHerbs: false), 10)
    }

    func testPreyWithoutStarvationKeepsWorking() {
        XCTAssertGreaterThanOrEqual(meanLiving(afterMoons: 80, preyAndHerbs: true), 9)
    }

    func testBothMatesCanStartAPregnancy() throws {
        var rng = SeededRNG(seed: 2)
        let engine = Self.assets.engine
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        var clan = founding.found(prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
                                  members: [], preyAndHerbs: false, engine: engine, using: &rng)
        var she = Self.assets.factory.make(rank: .warrior, moons: 30, using: &rng)
        var he = Self.assets.factory.make(rank: .warrior, moons: 30, using: &rng)
        she.sex = .female; he.sex = .male
        she.mates = [he.id]; he.mates = [she.id]
        clan.cats += [she, he]
        let odds = engine.kitChance(he, she, in: clan)
        XCTAssertLessThanOrEqual(odds, 20, "a small Clan's pair has good odds")
        var pregnant = 0
        let trials = 300
        for _ in 0..<trials {
            var copy = clan
            engine.advance(&copy, using: &rng)
            if copy.pregnancies[she.id] != nil { pregnant += 1 }
        }
        let expected = Double(trials) * (1 - pow(1 - 1 / Double(odds), 2))
        XCTAssertGreaterThan(Double(pregnant), expected * 0.6, "both mates roll")
    }
}
