import XCTest
@testable import KittyClan

final class PresentationTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var text: AppearanceText { Self.assets.appearanceText }

    private func cat(
        pattern: String = "Tabby", colour: String = "DARKBROWN", white: String? = nil, points: String? = nil,
        vitiligo: String? = nil, scars: [String] = [], length: PeltLength = .short,
        tortieBase: String? = nil, tortieColour: String? = nil, gender: GenderAlign = .female,
        rank: Rank = .warrior, moons: Int = 30
    ) -> Cat {
        var rng = SeededRNG(seed: 7)
        var cat = Self.assets.factory.make(rank: rank, moons: moons, using: &rng)
        cat.appearance.pattern = pattern
        cat.appearance.colour = colour
        cat.appearance.whitePatches = white
        cat.appearance.points = points
        cat.appearance.vitiligo = vitiligo
        cat.appearance.scars = scars
        cat.appearance.length = length
        cat.appearance.tortieBase = tortieBase
        cat.appearance.tortieColour = tortieColour
        cat.genderAlign = gender
        return cat
    }

    /// Expected text from Clangen's own `describe_appearance`, run on the same pelts.
    func testDescriptionsMatchClangen() {
        let cases: [(Cat, String, String)] = [
            (cat(), "brown tabby she-cat", "tabby she-cat"),
            (cat(pattern: "Tortie", tortieBase: "tabby", tortieColour: "GINGER"), "brown/ginger tortie tabby she-cat", "tortie she-cat"),
            (cat(pattern: "Calico", colour: "BLACK", white: "ANY", tortieBase: "single", tortieColour: "GINGER"), "black/ginger calico she-cat", "calico she-cat"),
            (cat(white: "FULLWHITE"), "white she-cat", "white she-cat"),
            (cat(white: "ANY"), "brown and white tabby she-cat", "tabby she-cat"),
            (cat(white: "VAN"), "white and brown tabby she-cat", "tabby she-cat"),
            (cat(vitiligo: "X", scars: ["NOPAW", "ONE", "TWO", "NOTAIL"], length: .long, gender: .male),
             "scarred, long-furred, brown tabby tom, with vitiligo and no tail and three legs", "tabby tom"),
            (cat(colour: "WHITE", white: "LITTLE"), "white tabby she-cat", "tabby she-cat"),
            (cat(pattern: "Tortie", colour: "BLACK", tortieBase: "single", tortieColour: "BROWN", gender: .nonbinary), "black/brown mottled cat", "mottled cat"),
        ]
        for (cat, long, short) in cases {
            XCTAssertEqual(text.describe(cat), long)
            XCTAssertEqual(text.describe(cat, short: true), short)
        }
        XCTAssertEqual(text.describeCat(cat()), "a brown tabby she-cat")
        XCTAssertEqual(text.describeCat(cat(pattern: "Bengal", colour: "GINGER")), "an unusually dappled ginger she-cat")
    }

    /// Clangen means "ginger point" to read "flame point" but discards the replacement.
    func testGingerPointReadsFlamePoint() {
        XCTAssertEqual(text.describe(cat(colour: "GINGER", points: "COLOURPOINT")), "flame point tabby she-cat")
    }

    func testAllegiancesListRanksAndQueens() {
        var rng = SeededRNG(seed: 3)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        var clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: [], preyAndHerbs: false, biome: .forest, camp: 1, engine: Self.assets.engine, using: &rng
        )
        var mother = cat(rank: .warrior)
        mother.sex = .female
        var father = cat(rank: .elder, moons: 130)
        father.sex = .male
        var kit = cat(rank: .kitten, moons: 2)
        kit.parents = [father.id, mother.id]
        let orphan = cat(rank: .kitten, moons: 3)
        var apprentice = cat(rank: .apprentice, moons: 7)
        apprentice.mentor = mother.id
        mother.apprentices = [apprentice.id]
        clan.cats += [mother, father, kit, orphan, apprentice]

        let allegiances = Self.assets.allegiances(of: clan)
        let titles = allegiances.sections.map(\.title)
        XCTAssertEqual(titles, ["LEADER", "DEPUTY", "MEDICINE CAT", "APPRENTICES", "QUEENS AND KITS", "ELDERS"])
        let queens = allegiances.sections.first { $0.title == "QUEENS AND KITS" }!
        XCTAssertEqual(queens.entries.map(\.id), [mother.id, orphan.id], "the she-cat parent cares for the kit")
        XCTAssertNotNil(queens.entries[0].caringFor)
        XCTAssertTrue(queens.entries[0].caringFor!.hasPrefix("(caring for "))
        XCTAssertEqual(queens.entries[0].apprenticeLine, "APPRENTICE: \(Self.assets.displayName(apprentice).uppercased())")
        XCTAssertFalse(allegiances.sections.contains { $0.title == "WARRIOR" || $0.title == "WARRIORS" }, "a queen leaves the warriors")
        let elders = allegiances.sections.first { $0.title == "ELDERS" }!
        XCTAssertEqual(elders.entries.map(\.id), [father.id])
        XCTAssertTrue(allegiances.text.hasPrefix("TestClan Allegiances"))
    }

    func testSymbolsFollowClangen() {
        let symbols = ClanSymbols.bundled
        XCTAssertEqual(symbols.all.count, 495)
        XCTAssertEqual(symbols.all.first?.id, "symbolADDER0")
        XCTAssertEqual(symbols.recommended(forPrefix: "Thunder"), "symbolTHUNDER0")
        XCTAssertNil(symbols.recommended(forPrefix: "Zzyzx"))
        var rng = SeededRNG(seed: 1)
        for _ in 0..<20 {
            XCTAssertTrue(["symbolCRANE0", "symbolCRANE1"].contains(symbols.fallback(forPrefix: "Crane", using: &rng)))
        }
        XCTAssertNotNil(symbols[symbols.fallback(forPrefix: "Zzyzx", using: &rng)])
        let cells = Set(symbols.all.map { [$0.column, $0.row] })
        XCTAssertEqual(cells.count, symbols.all.count, "every symbol has its own cell")
    }

    func testOldSavesGetASymbolForTheirPrefix() throws {
        var rng = SeededRNG(seed: 2)
        let founding = Self.assets.founding
        let adults = founding.candidates(using: &rng).filter(ClanFounding.canLead)
        let clan = founding.found(
            prefix: "Thunder", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: [], preyAndHerbs: false, biome: .forest, camp: 1, engine: Self.assets.engine, using: &rng
        )
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clan)) as! [String: Any]
        json["symbol"] = nil
        let decoded = try JSONDecoder().decode(Clan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.symbol, "symbolTHUNDER0")

        var chosen = clan
        chosen.symbol = "symbolCRANE1"
        let reloaded = try JSONDecoder().decode(Clan.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(reloaded.symbol, "symbolCRANE1")
    }

    func testProfilePlatformMatchesClangenSheet() {
        let greenleaf = ProfilePlatform(biome: .forest, season: .greenleaf, nest: false, afterlife: nil, dark: false)
        XCTAssertEqual(greenleaf.rect, CGRect(x: 80, y: 70, width: 80, height: 70))
        let bare = ProfilePlatform(biome: .beach, season: .leafBare, nest: false, afterlife: nil, dark: true)
        XCTAssertEqual(bare.rect.origin, CGPoint(x: 160, y: 0))
        let nest = ProfilePlatform(biome: .plains, season: .newleaf, nest: true, afterlife: nil, dark: false)
        XCTAssertEqual(nest.rect.origin, CGPoint(x: 560, y: 210))
        XCTAssertEqual(ProfilePlatform(biome: .plains, season: .newleaf, nest: false, afterlife: nil, dark: false).rect.origin, CGPoint(x: 560, y: 280))
        let starClan = ProfilePlatform(biome: .forest, season: .newleaf, nest: true, afterlife: .starClan, dark: false)
        XCTAssertEqual(starClan.rect.origin, CGPoint(x: 240, y: 350))
        let darkForest = ProfilePlatform(biome: .forest, season: .newleaf, nest: false, afterlife: .darkForest, dark: true)
        XCTAssertEqual(darkForest.rect.origin, CGPoint(x: 0, y: 350))
    }
}
