import XCTest
@testable import KittyClan

final class SkillTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()

    func testRequirementsFollowClangen() {
        var skills = CatSkills(primary: Skill(path: .HUNTER, points: 15, interestOnly: false))
        XCTAssertEqual(skills.primary?.tier, 2)
        XCTAssertTrue(skills.satisfies(["HUNTER,1"]))
        XCTAssertTrue(skills.satisfies(["FIGHTER,1", "HUNTER,2"]), "any entry can be met")
        XCTAssertFalse(skills.satisfies(["HUNTER,3"]))
        XCTAssertFalse(skills.satisfies(["-HUNTER,1"]), "exclusion lists fail when a skill is met")
        XCTAssertTrue(skills.satisfies(["-FIGHTER,1", "-CLIMBER,2"]))
        XCTAssertTrue(skills.satisfies(["any"]))
        XCTAssertFalse(skills.satisfies(["ROGUE,1"]), "unknown paths are never met")
        XCTAssertEqual(skills.requirementTier(["HUNTER,1"]), 2)
        XCTAssertEqual(skills.requirementTier(["-FIGHTER,1"]), 2, "an unmet exclusion scores the primary tier")

        skills.primary?.interestOnly = true
        XCTAssertEqual(skills.primary?.tier, 0)
        XCTAssertTrue(skills.satisfies(["HUNTER,0"]))
        XCTAssertFalse(skills.satisfies(["HUNTER,1"]), "interests only meet tier 0")
    }

    func testTextDescribesTiers() {
        let text = Self.assets.skillText
        XCTAssertEqual(text.describe(Skill(path: .HUNTER, points: 25, interestOnly: false), adolescent: false), "renowned hunter")
        XCTAssertEqual(text.describe(Skill(path: .HUNTER, points: 3, interestOnly: true), adolescent: true), "fledgeling hunter")
        XCTAssertEqual(text.describe(Skill(path: .HUNTER, points: 0, interestOnly: true), adolescent: false), "moss ball hunter")
    }

    func testSkillsGrowAndRevealAtGraduation() {
        var rng = SeededRNG(seed: 9)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        var clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), engine: Self.assets.engine, using: &rng
        )
        XCTAssertTrue(clan.living.filter { !$0.rank.isBaby }.allSatisfy { $0.skills.primary != nil })
        for _ in 0..<120 {
            Self.assets.engine.advance(&clan, using: &rng)
            for cat in clan.living {
                if cat.rank.isBaby || cat.rank.isApprentice {
                    XCTAssertTrue(cat.skills.all.allSatisfy(\.interestOnly), "kits and apprentices only have interests")
                } else if cat.moons > 1 {
                    XCTAssertNotNil(cat.skills.primary)
                    XCTAssertTrue(cat.skills.all.allSatisfy { !$0.interestOnly }, "\(cat.rank) \(cat.moons) still has an interest")
                }
            }
        }
        let graduates = clan.cats.filter { $0.origin == .clanborn && !$0.rank.isBaby && !$0.rank.isApprentice }
        print("clanborn graduates:", graduates.count, "tiers:", graduates.compactMap { $0.skills.primary?.tier })
    }

    func testMoreContentLoadsWithSkills() {
        let library = Self.assets.engine.library!
        print("ceremonies:", library.ceremonyCounts, "deaths:", library.deathCount, "misc:", library.miscCount, "injury:", library.injuryCount)
        for type in PatrolType.allCases {
            print("\(type):", Self.assets.patrols.library.patrols(for: type, season: .greenleaf).count)
        }
        XCTAssertGreaterThan(library.miscCount, 120, "skill-gated misc events load")
    }
}
