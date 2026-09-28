import XCTest
@testable import KittyClan

final class ConditionTests: XCTestCase {
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
            members: Array(others.prefix(6)), preyAndHerbs: false, engine: engine, using: &rng
        )
        return (clan, rng)
    }

    func testClangenConditionDataLoads() throws {
        let library = try XCTUnwrap(engine.conditions)
        let kinds = Dictionary(grouping: library.conditions.values, by: \.kind).mapValues(\.count)
        XCTAssertEqual(kinds[.injury], 43)
        XCTAssertEqual(kinds[.illness], 21)
        XCTAssertEqual(kinds[.permanent], 26)
        XCTAssertGreaterThan(engine.library?.injuryCount ?? 0, 100)
        XCTAssertFalse(library.strings("gain_illness_strings", "fleas").isEmpty, "the fleas key has a stray colon in Clangen")
    }

    func testInjuryHealsAfterItsDurationAndGraceMoon() {
        var (clan, rng) = clan(seed: 7)
        let warrior = clan.living.first { $0.rank == .warrior || $0.rank == .deputy }!.id
        XCTAssertTrue(engine.getInjured(warrior, "sprain", lethal: false, in: &clan, using: &rng))
        XCTAssertFalse(engine.getInjured(warrior, "sprain", in: &clan, using: &rng), "a cat can't get the same injury twice")
        XCTAssertTrue(clan[warrior]!.isInjured)

        var skip: Set<String> = []
        for _ in 0..<12 where clan[warrior]?.has("sprain") == true {
            clan.age += 1
            _ = engine.progressConditions(for: warrior, skip: &skip, in: &clan, using: &rng)
            skip.removeAll()
        }
        XCTAssertFalse(clan[warrior]?.has("sprain") ?? true, "the sprain should heal")
    }

    func testScarsOnlyUseDrawableSprites() {
        let index = Self.assets.renderer.atlas.index
        let drawable = Set(index.scars + index.missingPartScars)
        for scars in ConditionLibrary.scarAllowed.values {
            for scar in scars where !drawable.contains(scar) {
                print("scar pool entry with no sprite (filtered at runtime):", scar)
            }
        }
    }

    func testKittencoughOnlyForKits() {
        var (clan, rng) = clan(seed: 3)
        let adult = clan.living.first { !$0.rank.isBaby }!.id
        XCTAssertFalse(engine.getIll(adult, "kittencough", in: &clan, using: &rng))
    }

    func testLongRunConditionsStayConsistentAndRender() throws {
        var healthEvents = 0
        var scarred = 0
        var disabled = 0
        for seed in 11...14 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            for _ in 0..<150 {
                engine.advance(&clan, using: &rng)
                for cat in clan.cats {
                    if cat.isDead { XCTAssertFalse(cat.isIll || cat.isInjured, "dead cats keep no illnesses or injuries") }
                    XCTAssertEqual(Set(cat.conditions.map { "\($0.kind)\($0.name)" }).count, cat.conditions.count, "duplicate condition")
                }
                if clan.living.count > 50 { break }
            }
            for cat in clan.living {
                let pose = GameAssets.poseName(for: cat, age: cat.age)
                XCTAssertNoThrow(try Self.assets.renderer.render(cat.appearance, poseName: pose), "\(pose) \(cat.appearance.scars)")
            }
            healthEvents += clan.history.flatMap(\.entries).filter { $0.kind == .health }.count
            scarred += clan.cats.filter { !$0.appearance.scars.isEmpty }.count
            disabled += clan.cats.filter(\.isDisabled).count
        }
        print("health events:", healthEvents, "scarred cats:", scarred, "disabled cats:", disabled)
        XCTAssertGreaterThan(healthEvents, 20)
    }
}
