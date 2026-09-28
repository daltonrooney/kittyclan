import XCTest
@testable import KittyClan

final class RelationshipTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()

    func testTiersMatchClangenIntervals() {
        XCTAssertEqual(RelationshipValue.like.tier(for: -70), "loathes")
        XCTAssertEqual(RelationshipValue.like.tier(for: -69), "hates")
        XCTAssertEqual(RelationshipValue.like.tier(for: -6), "dislikes")
        XCTAssertEqual(RelationshipValue.like.tier(for: 5), "knows_of")
        XCTAssertEqual(RelationshipValue.like.tier(for: 24), "likes")
        XCTAssertEqual(RelationshipValue.like.tier(for: 69), "enjoys")
        XCTAssertEqual(RelationshipValue.like.tier(for: 70), "cherishes")
        XCTAssertEqual(RelationshipValue.romance.tier(for: 0), "uninterested")
        XCTAssertEqual(RelationshipValue.romance.tier(for: 80), "loves")
    }

    func testTierFilters() {
        var r = Relationship()
        r.set(.like, 50)
        r.set(.trust, -30)
        XCTAssertTrue(r.satisfies(tier: "likes"), "stronger positive feelings pass")
        XCTAssertTrue(r.satisfies(tier: "enjoys"))
        XCTAssertFalse(r.satisfies(tier: "cherishes"))
        XCTAssertFalse(r.satisfies(tier: "likes_only"))
        XCTAssertTrue(r.satisfies(tier: "enjoys_only"))
        XCTAssertTrue(r.satisfies(tier: "doubts"), "worse negative feelings pass")
        XCTAssertFalse(r.satisfies(tier: "discredits"))
        XCTAssertTrue(r.satisfies(tier: "acknowledges"), "neutral tiers are exact")
    }

    func testValuesNeverReturnToNeutral() {
        var r = Relationship()
        r.set(.like, 20)
        r.set(.like, 2)
        XCTAssertEqual(r[.like], 6)
        r.set(.like, -3)
        XCTAssertEqual(r[.like], -7)
        r.set(.romance, 500)
        XCTAssertEqual(r[.romance], 100)
    }

    func testInteractionTextLoads() {
        let counts = Self.assets.engine.relationships!.library.counts
        print("interactions:", counts)
        XCTAssertGreaterThan(counts.normal, 150)
        XCTAssertGreaterThan(counts.group, 20)
        XCTAssertGreaterThan(counts.joining, 10)
    }

    func testMatesFormNaturallyAndNeverBetweenRelatives() {
        var formed = 0
        var breakups = 0
        for seed in 1...4 as ClosedRange<UInt64> {
            var rng = SeededRNG(seed: seed)
            let founding = Self.assets.founding
            let candidates = founding.candidates(using: &rng)
            let adults = candidates.filter(ClanFounding.canLead)
            let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
            var clan = founding.found(
                prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
                members: Array(others.prefix(6)), preyAndHerbs: false, engine: Self.assets.engine, using: &rng
            )
            XCTAssertEqual(clan.relationships.count, clan.cats.count, "every founder has feelings about the others")

            for _ in 0..<150 {
                Self.assets.engine.advance(&clan, using: &rng)
                if clan.living.count > 50 { break }
            }
            for cat in clan.cats {
                for mate in cat.mates {
                    XCTAssertFalse(clan.areRelated(cat.id, mate), "relatives became mates")
                    XCTAssertTrue(clan[mate]?.mates.contains(cat.id) == true, "mates are mutual")
                }
            }
            for (_, row) in clan.relationships {
                for (_, r) in row {
                    for value in RelationshipValue.allCases { XCTAssertTrue(value.range.contains(r[value])) }
                }
            }
            let entries = clan.history.flatMap(\.entries)
            formed += entries.filter { $0.kind == .relationship && $0.text.contains("mates") }.count
            breakups += clan.cats.filter { !$0.previousMates.isEmpty }.count
            XCTAssertGreaterThan(entries.filter { $0.kind == .interaction }.count, 100)
        }
        print("mates formed:", formed, "cats with exes:", breakups)
        XCTAssertGreaterThan(formed, 0)
    }
}
