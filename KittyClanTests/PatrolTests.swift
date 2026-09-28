import XCTest
@testable import KittyClan

final class PatrolTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var patrols: PatrolEngine { Self.assets.patrols }

    private func grownClan(seed: UInt64, moons: Int = 30) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        var clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), engine: Self.assets.engine, using: &rng
        )
        for _ in 0..<moons { Self.assets.engine.advance(&clan, using: &rng) }
        return (clan, rng)
    }

    private func assertResolved(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let leftovers = ["{", "p_l", "r_c", "s_c", "n_c", "f_tp", "f_mp", "c_n", "cat_to", "cat_from"]
        for token in leftovers where text.contains(token) {
            XCTFail("unresolved \(token): \(text)", file: file, line: line)
        }
    }

    func testPatrolDataLoads() {
        let library = patrols.library
        for type in PatrolType.allCases {
            let count = Season.allCases.map { library.patrols(for: type, season: $0).count }.max() ?? 0
            print("\(type) patrols per season:", count)
            XCTAssertGreaterThan(count, 20, "\(type)")
        }
        XCTAssertNotNil(library.artURL("hunt_general_intro"))
        XCTAssertNotNil(library.artURL("HUNT_GENERAL_INTRO"), "art lookup ignores case")
    }

    func testManyPatrolsResolveCleanly() throws {
        var started = 0, missing = 0, succeeded = 0
        var results: [String: Int] = [:]
        for seed in 1...6 as ClosedRange<UInt64> {
            var (clan, rng) = grownClan(seed: seed)
            for _ in 0..<15 {
                clan.patrolledThisMoon = []
                for type in [PatrolType.hunting, .border, .training, nil] {
                    let eligible = PatrolEngine.eligible(in: clan).filter { ![.medicineCat, .medicineApprentice].contains($0.rank) }
                    guard !eligible.isEmpty else { continue }
                    let size = Int.random(in: 1...min(6, eligible.count), using: &rng)
                    let chosen = Array(eligible.shuffled(using: &rng).prefix(size)).map(\.id)
                    guard let session = patrols.start(chosen, type: type, in: &clan, using: &rng) else {
                        missing += 1
                        continue
                    }
                    started += 1
                    assertResolved(session.intro)
                    XCTAssertTrue(chosen.allSatisfy(clan.patrolledThisMoon.contains))
                    let choice: PatrolChoice = session.canAntagonize && Bool.random(using: &rng) ? .antagonize : .proceed
                    let result = patrols.finish(session, choice: choice, in: &clan, using: &rng)
                    assertResolved(result.text)
                    for line in result.results {
                        assertResolved(line)
                        let kind = line.components(separatedBy: " ").suffix(2).joined(separator: " ")
                        results[kind, default: 0] += 1
                    }
                    if result.succeeded { succeeded += 1 }
                }
                if let healer = PatrolEngine.eligible(in: clan).first(where: { $0.rank == .medicineCat }),
                   let session = patrols.start([healer.id], type: .hunting, in: &clan, using: &rng) {
                    XCTAssertEqual(session.type, .herbGathering, "a medicine cat always gathers herbs")
                    assertResolved(patrols.finish(session, choice: .proceed, in: &clan, using: &rng).text)
                }
                Self.assets.engine.advance(&clan, using: &rng)
            }
            for cat in clan.living {
                if let mentor = cat.mentor { XCTAssertEqual(clan[mentor]?.apprentices.contains(cat.id), true) }
            }
        }
        print("patrols started:", started, "none found:", missing, "succeeded:", succeeded, "result lines:", results)
        XCTAssertGreaterThan(started, 200)
        XCTAssertLessThan(Double(missing) / Double(started + missing), 0.1, "most patrols should find an event")
    }

    func testDeclineChangesNothing() throws {
        var (clan, rng) = grownClan(seed: 42)
        let cats = PatrolEngine.eligible(in: clan).filter { $0.rank == .warrior }.prefix(3).map(\.id)
        let session = try XCTUnwrap(patrols.start(Array(cats), type: .border, in: &clan, using: &rng))
        let before = clan.cats
        let result = patrols.finish(session, choice: .decline, in: &clan, using: &rng)
        XCTAssertEqual(clan.cats, before)
        assertResolved(result.text)
        XCTAssertTrue(PatrolEngine.eligible(in: clan).allSatisfy { !cats.contains($0.id) }, "declining still uses up the patrol")
    }
}
