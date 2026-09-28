import XCTest
@testable import KittyClan

final class ThoughtTests: XCTestCase {
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
        for token in ["{", "}", "m_c", "r_c", "c_n"] where text.contains(token) {
            XCTFail("unresolved \(token): \(text)", file: file, line: line)
        }
    }

    func testLibraryLoadsMostBlocks() throws {
        let library = try XCTUnwrap(engine.thoughts)
        XCTAssertGreaterThan(library.blockCount, 750)
    }

    func testFoundersAndGuideHaveThoughts() throws {
        let (clan, _) = clan(seed: 1)
        for cat in clan.cats {
            let text = try XCTUnwrap(Self.assets.thought(of: cat, in: clan), "\(cat.name.prefix) \(cat.rank)")
            assertResolved(text)
        }
    }

    func testThoughtsStayResolvedOverManyMoons() {
        var (clan, rng) = clan(seed: 2)
        var seen = 0, missing = 0
        for _ in 0..<60 {
            engine.advance(&clan, using: &rng)
            for cat in clan.cats + clan.outsiders {
                if let text = Self.assets.thought(of: cat, in: clan) {
                    assertResolved(text)
                    seen += 1
                } else {
                    missing += 1
                }
            }
        }
        XCTAssertGreaterThan(seen, 500)
        XCTAssertLessThan(Double(missing), Double(seen) * 0.05, "almost every cat has a thought")
    }

    func testMentorThoughtsOnlyForTheirApprentice() throws {
        var (clan, rng) = clan(seed: 3)
        let library = try XCTUnwrap(engine.thoughts)
        for _ in 0..<12 { engine.advance(&clan, using: &rng) }
        let context = ThoughtContext(clan: clan)
        for cat in clan.living {
            for block in library.pool(.whileAlive, for: cat, in: context) where block.relationships.contains(where: { $0.constraints == ["app/mentor"] }) {
                for other in clan.living where block.fits(cat, about: other, in: context) {
                    XCTAssertEqual(cat.mentor, other.id, block.id)
                }
            }
        }
    }

    func testLowercaseVerbTagsResolve() throws {
        let (clan, _) = clan(seed: 4)
        let cat = try XCTUnwrap(clan[clan.leader])
        let text = Self.assets.afterlifeText.template.resolve("m_c {verb/m_c/have/has} a plan", cats: ["m_c": cat], clan: clan)
        assertResolved(text)
        XCTAssertTrue(text.contains(" ha"))
    }
}
