import XCTest
@testable import KittyClan

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class MoonEngineTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()

    private func foundClan(seed: UInt64) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(6)), preyAndHerbs: false, engine: Self.assets.engine, using: &rng
        )
        return (clan, rng)
    }

    func testFoundingMatchesClangenRules() {
        for seed in 0..<50 as Range<UInt64> {
            var rng = SeededRNG(seed: seed)
            let candidates = Self.assets.founding.candidates(using: &rng)
            XCTAssertEqual(candidates.count, 12)
            XCTAssertGreaterThanOrEqual(candidates.filter { $0.rank == .warrior }.count, 3)
            XCTAssertTrue(candidates.allSatisfy { [.kitten, .apprentice, .warrior, .elder].contains($0.rank) })
        }
        let (clan, _) = foundClan(seed: 1)
        XCTAssertEqual(clan[clan.leader]?.rank, .leader)
        XCTAssertEqual(clan[clan.deputy]?.rank, .deputy)
        XCTAssertEqual(clan.living.filter { $0.rank == .medicineCat }.count, 1)
        XCTAssertEqual(clan.history.first?.entries.count, 1)
        for apprentice in clan.living where apprentice.rank.isApprentice {
            XCTAssertNotNil(apprentice.mentor)
        }
    }

    func testClangenTextLoads() throws {
        let text = try XCTUnwrap(Bundle.main.url(forResource: "Text", withExtension: nil))
        let library = try EventLibrary(directory: text)
        print("ceremonies:", library.ceremonyCounts, "deaths:", library.deathCount, "misc:", library.miscCount)
        for (file, count) in library.ceremonyCounts {
            XCTAssertGreaterThan(count, 0, "no usable \(file) ceremonies")
        }
        XCTAssertGreaterThan(library.deathCount, 50)
        XCTAssertGreaterThan(library.miscCount, 80)
    }

    func testNameValidation() {
        XCTAssertTrue(ClanFounding.validateName("Thunder"))
        XCTAssertFalse(ClanFounding.validateName(""))
        XCTAssertFalse(ClanFounding.validateName(" Thunder"))
        XCTAssertFalse(ClanFounding.validateName("Thunderstorms"))
        XCTAssertFalse(ClanFounding.validateName("Thun/der"))
    }

    func testThreeHundredMoonsKeepInvariants() throws {
        var totals = (births: 0, deaths: 0, graduations: 0, joins: 0, retirements: 0)
        for seed in 1...6 as ClosedRange<UInt64> {
            var (clan, rng) = foundClan(seed: seed)
            for _ in 0..<300 {
                Self.assets.engine.advance(&clan, using: &rng)
                try checkInvariants(clan)
                if clan.living.count > 60 { break }
            }
            for log in clan.history {
                for entry in log.entries {
                    XCTAssertFalse(entry.text.isEmpty)
                    XCTAssertFalse(entry.text.contains("{") || entry.text.contains("%{"), "unresolved template: \(entry.text)")
                    XCTAssertFalse(entry.text.contains("m_c") || entry.text.contains("r_c") || entry.text.contains("multi_cat") || entry.text.contains("cat_to"), "unresolved name: \(entry.text)")
                }
            }
            totals.births += clan.cats.filter { $0.origin == .clanborn }.count
            totals.deaths += clan.dead.count
            totals.graduations += clan.cats.filter { $0.formerMentors.count > 0 && !$0.rank.isApprentice }.count
            totals.joins += clan.cats.filter { [.loner, .kittypet, .rogue].contains($0.origin) }.count
            totals.retirements += clan.cats.filter { $0.rank == .elder && $0.origin != .founder }.count

            let data = try JSONEncoder().encode(clan)
            let decoded = try JSONDecoder().decode(Clan.self, from: data)
            XCTAssertEqual(decoded.cats, clan.cats)
            XCTAssertEqual(decoded.history, clan.history)
        }
        XCTAssertGreaterThan(totals.births, 0, "no kits were born")
        XCTAssertGreaterThan(totals.deaths, 0, "no cats died")
        XCTAssertGreaterThan(totals.graduations, 0, "no apprentices graduated")
        XCTAssertGreaterThan(totals.joins, 0, "no cats joined")
        print("300-moon totals:", totals)
    }

    private func checkInvariants(_ clan: Clan, file: StaticString = #filePath, line: UInt = #line) throws {
        let living = clan.living
        XCTAssertLessThanOrEqual(living.filter { $0.rank == .leader }.count, 1, file: file, line: line)
        XCTAssertLessThanOrEqual(living.filter { $0.rank == .deputy }.count, 1, file: file, line: line)
        if let leader = clan[clan.leader], leader.isAlive { XCTAssertEqual(leader.rank, .leader, file: file, line: line) }
        if let deputy = clan[clan.deputy], deputy.isAlive { XCTAssertEqual(deputy.rank, .deputy, file: file, line: line) }

        for cat in living {
            let maxMoons = cat.id == clan.leader ? 300 + Clan.maxLeaderLives : 300
            XCTAssertLessThanOrEqual(cat.moons, maxMoons, "\(cat.rank) at \(cat.moons) moons", file: file, line: line)
            if cat.rank.isBaby { XCTAssertLessThan(cat.moons, 7, "\(cat.rank) at \(cat.moons) moons", file: file, line: line) }
            if cat.rank == .newborn { XCTAssertEqual(cat.moons, 0, file: file, line: line) }
            if let mentorID = cat.mentor {
                let mentor = try XCTUnwrap(clan[mentorID])
                XCTAssertTrue(mentor.isAlive, file: file, line: line)
                XCTAssertTrue(mentor.apprentices.contains(cat.id), file: file, line: line)
                XCTAssertTrue(MoonEngine.canMentor(mentor, cat), "\(mentor.rank) mentoring \(cat.rank)", file: file, line: line)
            }
            for apprentice in cat.apprentices {
                XCTAssertEqual(clan[apprentice]?.mentor, cat.id, file: file, line: line)
            }
            if !cat.rank.isApprentice { XCTAssertNil(cat.mentor, file: file, line: line) }
        }
        for (mother, _) in clan.pregnancies {
            XCTAssertTrue(clan.isAlive(mother), file: file, line: line)
            XCTAssertEqual(clan[mother]?.sex, .female, file: file, line: line)
        }
    }
}
