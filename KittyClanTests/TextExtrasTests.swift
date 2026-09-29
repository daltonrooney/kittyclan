import XCTest
@testable import KittyClan

final class TextExtrasTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }
    private var template: TextTemplate { Self.assets.patrols.template }
    private var library: EventLibrary { engine.library! }

    private func clan(seed: UInt64, biome: Biome = .forest) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), preyAndHerbs: false, biome: biome, engine: engine, using: &rng
        )
        return (clan, rng)
    }

    private func assertResolved(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for token in ["{", "}", "_list", "POI", "cat_tag", "m_c", "r_c", "c_n"] where text.contains(token) {
            XCTFail("unresolved \(token): \(text)", file: file, line: line)
        }
    }

    func testLoadedCounts() throws {
        let patrols = Self.assets.patrols.library
        let events = library.ceremonyCounts.values.reduce(0, +) + library.deathCount + library.miscCount
            + library.accessoryEventCount + library.injuryCount + library.newCatCount
        let patrolCount = patrols.count + patrols.newCatPatrols.values.reduce(0) { $0 + $1.count }
            + patrols.otherClanPatrols.values.reduce(0) { $0 + $1.count }
        let thoughts = try XCTUnwrap(engine.thoughts).blockCount
        let thoughtLines = try XCTUnwrap(engine.thoughts).stringCount
        print("COUNTS events:", events, "ceremonies:", library.ceremonyCounts.values.reduce(0, +), "deaths:", library.deathCount,
              "misc:", library.miscCount, "accessory:", library.accessoryEventCount, "injury:", library.injuryCount,
              "newCat:", library.newCatCount, "patrols:", patrolCount, "thoughts:", thoughts, "thought lines:", thoughtLines, "transitions:", library.transitions.count)
        XCTAssertGreaterThan(events, 1083)
        XCTAssertGreaterThan(patrolCount, 1093)
        XCTAssertGreaterThanOrEqual(thoughts, 958)
        XCTAssertTrue(try XCTUnwrap(engine.thoughts).pool(.whileAlive, for: clan(seed: 1).0.living[0], in: ThoughtContext(clan: clan(seed: 1).0))
            .contains { $0.strings.contains { $0.contains("dream_list") } })
    }

    // MARK: - Snippets

    func testFindsSpecialListTokens() throws {
        let token = try XCTUnwrap(SnippetCollections.token(in: "It was an omen: omen_list_sight_sound/m_c. Truly."))
        XCTAssertEqual(token.text, "omen_list_sight_sound/m_c")
        XCTAssertEqual(token.type, "omen_list")
        XCTAssertEqual(token.senses, ["sight", "sound"])
        XCTAssertEqual(token.cat, "m_c")
        let dream = try XCTUnwrap(SnippetCollections.token(in: "Has a dream full of dream_list"))
        XCTAssertEqual(dream.type, "dream_list")
        XCTAssertNil(dream.cat)
        XCTAssertNil(SnippetCollections.token(in: "No lists here."))
    }

    func testSnippetListsResolve() throws {
        let (clan, _) = clan(seed: 1)
        let cat = clan.living[0]
        var rng = SeededRNG(seed: 2)
        let lines = [
            "m_c saw omen_list_touch/m_c.", "Wonders about prophecy_list_sound.", "Has a dream full of dream_list",
            "Suddenly thinks of clair_list_emotional/m_c", "m_c tells the kits story_list.", "An omen: omen_list/m_c.",
        ]
        for line in lines {
            for _ in 0..<40 {
                let text = template.resolve(line, cats: ["m_c": cat], clan: clan, using: &rng)
                assertResolved(text)
            }
        }
    }

    func testSnippetsFollowTheBiome() throws {
        let snippets = try XCTUnwrap(template.snippets)
        let token = try XCTUnwrap(SnippetCollections.token(in: "story_list"))
        var rng = SeededRNG(seed: 3)
        let beach = Set((0..<300).map { _ in snippets.snippets(for: token, biome: .beach, using: &rng) })
        let forest = Set((0..<300).map { _ in snippets.snippets(for: token, biome: .forest, using: &rng) })
        XCTAssertTrue(beach.contains { $0.contains("Seagull") || $0.contains("Tide") || $0.contains("Shell") || $0.contains("Fish") } || beach != forest)
        for text in beach.union(forest) {
            let count = text.components(separatedBy: " and ").count
            XCTAssertLessThanOrEqual(count, 3)
        }
    }

    func testThoughtsExpandListsWhenChosen() {
        var (clan, rng) = clan(seed: 4)
        for _ in 0..<40 {
            engine.advance(&clan, using: &rng)
            for cat in clan.cats + clan.outsiders {
                if let raw = cat.thought?.text { XCTAssertFalse(raw.contains("_list"), raw) }
                if let text = Self.assets.thought(of: cat, in: clan) { assertResolved(text) }
            }
        }
    }

    // MARK: - Points of interest

    func testNewClansKnowPointsOfInterest() {
        let places = library.places
        for biome in Biome.allCases {
            let (clan, _) = clan(seed: 5, biome: biome)
            let categories = clan.pointsOfInterest.compactMap { places.places[$0]?.category }
            XCTAssertEqual(categories.sorted(), ["gathering", "moonplace", "terrain", "terrain", "terrain"])
            XCTAssertEqual(Set(clan.pointsOfInterest).count, 5)
            for id in clan.pointsOfInterest {
                XCTAssertFalse(Set(places.places[id]!.biomes).isDisjoint(with: ["any", biome.key]), "\(id) in \(biome)")
            }
        }
    }

    func testPointOfInterestMatching() throws {
        let places = library.places
        let known = ["moon_pool", "terrain_lake", "terrain_sunningrocks", "gather_island"]
        XCTAssertEqual(places.matches(try XCTUnwrap(PoiRequirement(["tags": ["water"]])), known: known).sorted(), ["gather_island", "moon_pool", "terrain_lake"])
        XCTAssertEqual(places.matches(try XCTUnwrap(PoiRequirement(["tags": ["water:still"], "category": "terrain"])), known: known), ["terrain_lake"])
        XCTAssertEqual(places.matches(try XCTUnwrap(PoiRequirement(["name": ["terrain_horseplace"]])), known: known), [])
        XCTAssertNil(PoiRequirement(["tags": []]))
        XCTAssertEqual(places.name("moon_pool"), "the Moonpool")
    }

    func testOldSavesGainPointsOfInterest() throws {
        var (clan, rng) = clan(seed: 6)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clan)) as? [String: Any])
        for key in ["pointsOfInterest", "customPronouns", "theyThemDefault"] { object[key] = nil }
        clan = try JSONDecoder().decode(Clan.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(clan.pointsOfInterest.isEmpty)
        XCTAssertFalse(clan.theyThemDefault)
        XCTAssertTrue(clan.customPronouns.isEmpty)
        engine.advance(&clan, using: &rng)
        XCTAssertEqual(clan.pointsOfInterest.count, 5)
    }

    func testEventsAndPatrolsNamePlaces() {
        var (clan, rng) = clan(seed: 7)
        var sawPlace = false
        let names = Set(clan.pointsOfInterest.map(library.places.name))
        for moon in 0..<120 {
            engine.advance(&clan, using: &rng)
            for entry in clan.history.last?.entries ?? [] {
                assertResolved(entry.text)
                if names.contains(where: entry.text.contains) { sawPlace = true }
            }
            let cats = PatrolEngine.eligible(in: clan).prefix(3 + moon % 3).map(\.id)
            guard !cats.isEmpty, let session = Self.assets.patrols.start(Array(cats), type: nil, in: &clan, using: &rng) else { continue }
            let result = Self.assets.patrols.finish(session, choice: .proceed, in: &clan, using: &rng)
            for text in [session.intro, result.text] {
                assertResolved(text)
                if names.contains(where: text.contains) { sawPlace = true }
            }
        }
        XCTAssertTrue(sawPlace, "some event or patrol names one of the Clan's places")
    }

    // MARK: - Pronouns

    func testLegacyPronounsDecode() throws {
        let (clan, _) = clan(seed: 8)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clan.living[0])) as? [String: Any])
        object["pronouns"] = "2"
        XCTAssertEqual(try JSONDecoder().decode(Cat.self, from: JSONSerialization.data(withJSONObject: object)).pronouns, [.she])
        object["pronouns"] = "0"
        XCTAssertEqual(try JSONDecoder().decode(Cat.self, from: JSONSerialization.data(withJSONObject: object)).pronouns, [.they])
        let round = try JSONDecoder().decode(Cat.self, from: JSONEncoder().encode(clan.living[0]))
        XCTAssertEqual(round.pronouns, clan.living[0].pronouns)
    }

    func testSeveralSetsStayConsistentWithinOneText() {
        let (clan, _) = clan(seed: 9)
        var cat = clan.living[0]
        cat.pronouns = [.she, .they]
        var rng = SeededRNG(seed: 10)
        var seen: Set<String> = []
        for _ in 0..<60 {
            let text = template.resolve("{PRONOUN/m_c/subject} {VERB/m_c/are/is} {PRONOUN/m_c/self}", cats: ["m_c": cat], clan: clan, using: &rng)
            XCTAssertTrue(["she is herself", "they are themself"].contains(text), text)
            seen.insert(text)
        }
        XCTAssertEqual(seen.count, 2, "both sets get used")
        let line = "{PRONOUN/m_c/subject/CAP} naps."
        XCTAssertEqual(template.resolve(line, cats: ["m_c": cat], clan: clan), template.resolve(line, cats: ["m_c": cat], clan: clan))
    }

    func testCustomSetResolves() {
        var (clan, _) = clan(seed: 11)
        let xe = PronounSet(subject: "xe", object: "xem", poss: "xyr", inposs: "xyrs", reflexive: "xemself", conju: 2, gender: 0)
        XCTAssertTrue(clan.addCustomPronouns(xe))
        XCTAssertFalse(clan.addCustomPronouns(xe), "no duplicates")
        XCTAssertFalse(clan.addCustomPronouns(.he), "built-in sets aren't custom")
        var blank = xe
        blank.reflexive = " "
        XCTAssertFalse(clan.addCustomPronouns(blank))
        XCTAssertEqual(clan.customPronouns, [xe])

        let id = clan.living[0].id
        XCTAssertTrue(clan.setGender(id, genderAlign: .nonbinary, pronouns: [xe, xe, .they]))
        XCTAssertEqual(clan[id]?.pronouns, [xe, .they])
        XCTAssertFalse(clan.setGender(id, genderAlign: .nonbinary, pronouns: []))
        var cat = clan[id]!
        cat.pronouns = [xe]
        let text = template.resolve("{PRONOUN/m_c/subject/CAP} {VERB/m_c/are/is} a {ADJ/m_c/cat/tom/she-cat}; that is {PRONOUN/m_c/inposs}.", cats: ["m_c": cat], clan: clan)
        XCTAssertEqual(text, "Xe is a cat; that is xyrs.")
    }

    func testTheyThemDefault() {
        var (clan, rng) = clan(seed: 12)
        XCTAssertEqual(clan.newPronouns(for: .transMale), [.he])
        clan.theyThemDefault = true
        XCTAssertEqual(clan.newPronouns(for: .transMale), [.they])
        let factory = Self.assets.factory
        for _ in 0..<50 {
            XCTAssertEqual(factory.make(rank: .warrior, theyThem: true, using: &rng).pronouns, [.they])
            XCTAssertEqual(factory.makeJoiner(origin: .loner, theyThem: true, using: &rng).pronouns, [.they])
        }
        let before = Set(clan.cats.map(\.id))
        for _ in 0..<60 { engine.advance(&clan, using: &rng) }
        let newcomers = (clan.cats + clan.outsiders).filter { !before.contains($0.id) }
        XCTAssertFalse(newcomers.isEmpty)
        for cat in newcomers where cat.isCis {
            XCTAssertEqual(cat.pronouns, [.they], "\(cat.name.prefix)")
        }
    }

    // MARK: - Coming out

    func testComingOutOdds() {
        XCTAssertEqual(MoonEngine.comingOutChance(for: .kitten), 128)
        XCTAssertEqual(MoonEngine.comingOutChance(for: .youngAdult), 256)
        XCTAssertEqual(MoonEngine.comingOutChance(for: .senior), 512)
        XCTAssertGreaterThan(library.transitions.count, 40)
    }

    func testCatsComeOut() throws {
        let (start, _) = clan(seed: 13)
        var rng = SeededRNG(seed: 14)
        var cameOut = 0
        for _ in 0..<3000 {
            var clan = start
            guard let cat = clan.living.filter({ $0.moons >= 3 && $0.isCis }).randomElement(using: &rng) else { continue }
            let events = engine.attemptComingOut(cat.id, in: &clan, using: &rng)
            guard let event = events.first else {
                XCTAssertEqual(clan[cat.id]?.genderAlign, cat.genderAlign)
                continue
            }
            cameOut += 1
            let after = try XCTUnwrap(clan[cat.id])
            XCTAssertFalse(after.isCis)
            XCTAssertEqual(after.pronouns, clan.newPronouns(for: after.genderAlign))
            assertResolved(engine.narrator.entry(event, in: clan, using: &rng).text)
        }
        XCTAssertGreaterThan(cameOut, 3)
        XCTAssertLessThan(cameOut, 60)

        var clan = start
        let id = clan.living[0].id
        clan.cats[clan.index(of: id)!].genderAlign = .nonbinary
        for _ in 0..<2000 { XCTAssertTrue(engine.attemptComingOut(id, in: &clan, using: &rng).isEmpty) }
    }

    func testDeadParentWatchesFromStarClan() throws {
        var (clan, rng) = clan(seed: 15)
        let parent = clan.living.first { $0.rank == .warrior }!
        var child = Self.assets.factory.make(rank: .warrior, moons: 20, sex: .female, using: &rng)
        child.genderAlign = .female
        child.parents = [parent.id]
        clan.cats.append(child)
        let i = clan.index(of: parent.id)!
        clan.cats[i].isDead = true
        clan.cats[i].afterlife = .starClan

        let event = try XCTUnwrap(library.transitions.first { $0.id == "gen_misc_transition_deadparent_to_male" })
        let cats = try XCTUnwrap(event.fill(main: child, in: ThoughtContext(clan: clan), using: &rng))
        XCTAssertEqual(cats["r_c0"], parent.id)

        clan.cats[i].afterlife = .darkForest
        XCTAssertNil(event.fill(main: child, in: ThoughtContext(clan: clan), using: &rng))
    }
}
