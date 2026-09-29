import XCTest
@testable import KittyClan

final class BackstoryTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }
    private var backstories: Backstories { .bundled }

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

    func testLoadCounts() throws {
        let library = try XCTUnwrap(engine.library)
        let patrols = Self.assets.patrols.library
        let newCat = patrols.newCatPatrols.values.reduce(0) { $0 + $1.count }
        let otherClan = patrols.otherClanPatrols.values.reduce(0) { $0 + $1.count }
        print("LOADCOUNTS ceremonies:", library.ceremonyCounts.values.reduce(0, +), "deaths:", library.deathCount, "murder:", library.murderCount,
              "misc:", library.miscCount, "injury:", library.injuryCount, "newCat:", library.newCatCount,
              "patrols:", patrols.count, "newCatPatrols:", newCat, "otherClanPatrols:", otherClan,
              "thoughts:", engine.thoughts?.blockCount ?? 0)
        XCTAssertGreaterThanOrEqual(library.newCatCount, 95, "new-cat events with Clan backstories and other-Clan cats load")
        XCTAssertGreaterThanOrEqual(newCat, 85, "new-cat patrols with backstories, parents and mates load")
        XCTAssertGreaterThanOrEqual(otherClan, 40)
        XCTAssertGreaterThan(engine.thoughts?.blockCount ?? 0, 980, "thoughts with backstory lists load")
    }

    func testCatalogExpandsCategories() throws {
        let loners = try XCTUnwrap(backstories.expand(["loner_backstories"]))
        XCTAssertTrue(loners.isSuperset(of: ["loner1", "refugee2", "stolenkit4"]))
        XCTAssertEqual(backstories.expand(["clanborn", "otherclan1"]), ["clanborn", "otherclan1"])
        XCTAssertNil(backstories.expand(["not_a_backstory"]))
        XCTAssertEqual(backstories.category(of: "medicine_cat"), "former_clancat_backstories")
        XCTAssertEqual(backstories.category(of: "halfclan1"), "half_clan_backstories")
        XCTAssertEqual(backstories.social(of: "otherclan2"), .clancat)
        XCTAssertEqual(backstories.social(of: "refugee3"), .kittypet)
        XCTAssertEqual(backstories.conversion["otherclan"], "otherclan1")
    }

    func testConstraintsCheckBackstories() throws {
        var (clan, _) = clan(seed: 3)
        var cat = clan.living[0]
        cat.backstory = "kittypet2"
        let kittypets = try XCTUnwrap(Constraint(["backstory": ["kittypet_backstories"]]))
        XCTAssertTrue(kittypets.matches(cat))
        let notKittypets = try XCTUnwrap(Constraint(["backstory": ["-kittypet_backstories", "-clanborn"]]))
        XCTAssertFalse(notKittypets.matches(cat))
        cat.backstory = "clan_founder"
        XCTAssertFalse(kittypets.matches(cat))
        XCTAssertTrue(notKittypets.matches(cat))
        XCTAssertNil(Constraint(["backstory": ["made_up"]]))

        let filter = try XCTUnwrap(ThoughtCatFilter(["backstory": ["clan_founder", "clanborn"]]), "inclusive thought lists load")
        clan.cats[0] = cat
        XCTAssertTrue(filter.matches(cat, main: nil, in: ThoughtContext(clan: clan)))
        cat.backstory = "loner1"
        XCTAssertFalse(filter.matches(cat, main: nil, in: ThoughtContext(clan: clan)))
    }

    func testFoundersGuideAndKitsGetBackstories() {
        var births = 0
        for seed in 0..<6 as Range<UInt64> {
            var (clan, rng) = clan(seed: seed)
            let founders = Set(clan.cats.map(\.id)).subtracting([clan.guide].compactMap(\.self))
            for id in founders { XCTAssertEqual(clan[id]?.backstory, "clan_founder") }
            XCTAssertTrue(clan[clan.guide]?.backstory?.hasPrefix("clan_guide") ?? false)
            for _ in 0..<60 { engine.advance(&clan, using: &rng) }
            for cat in clan.cats + clan.outsiders {
                let story = cat.backstory ?? "none"
                XCTAssertTrue(backstories.all.contains(story), "\(cat.name.prefix) has backstory \(story)")
                if !founders.contains(cat.id), cat.origin == .clanborn, cat.adoptiveParents.isEmpty, !cat.parents.isEmpty,
                   cat.parents.allSatisfy({ parent in clan.cats.contains { $0.id == parent } }) {
                    XCTAssertEqual(story, "clanborn")
                    births += 1
                }
            }
        }
        XCTAssertGreaterThan(births, 0, "some kits are born over 60 moons")
    }

    func testNewCatBlocksFollowClangen() throws {
        var (clan, rng) = clan(seed: 11)
        let other = try XCTUnwrap(clan.otherClans.first)
        var counts: [UUID: Int] = [:]

        var pick = StoryPick(template: "m_c meets n_c:0.", cats: ["m_c": clan.living[0].id])
        pick.otherClan = other.id
        pick.newCats = [["clancat", "meeting", "age:adult"]]
        XCTAssertEqual(engine.addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng), false)
        let met = try XCTUnwrap(clan[pick.cats["n_c:0"]])
        XCTAssertTrue(clan.outsiders.contains { $0.id == met.id })
        XCTAssertTrue(met.belongsToOtherClan)
        XCTAssertEqual(met.otherClan, other.id)
        XCTAssertTrue(backstories.contains(met.backstory ?? "", in: "former_clancat_backstories"))
        XCTAssertFalse(MoonEngine.denOutsiders(in: clan).contains { $0.id == met.id }, "other Clans' cats aren't the leader's to invite")
        XCTAssertEqual(Self.assets.afterlifeText.profileBackstory(of: met, in: clan).contains(other.name), true)

        var join = StoryPick(template: "n_c:0 joins.", cats: ["m_c": clan.living[0].id])
        join.otherClan = other.id
        join.newCats = [["clancat", "status:warrior", "backstory:otherclan1,otherclan2"]]
        XCTAssertEqual(engine.addNewCats(to: &join, in: &clan, counts: &counts, using: &rng), true)
        let joined = try XCTUnwrap(clan[join.cats["n_c:0"]])
        XCTAssertTrue(clan.isAlive(joined.id))
        XCTAssertTrue(["otherclan1", "otherclan2"].contains(joined.backstory ?? ""))
        XCTAssertEqual(joined.otherClan, other.id)
        XCTAssertTrue(joined.leftOtherClan)

        var former = StoryPick(template: "m_c meets n_c:0.", cats: ["m_c": clan.living[0].id])
        former.newCats = [["former clancat", "meeting"]]
        engine.addNewCats(to: &former, in: &clan, counts: &counts, using: &rng)
        let loner = try XCTUnwrap(clan[former.cats["n_c:0"]])
        XCTAssertNotNil(loner.otherClan)
        XCTAssertFalse(loner.belongsToOtherClan)
        XCTAssertTrue([.loner, .rogue, .kittypet].contains(loner.origin))

        var kits = StoryPick(template: "m_c finds n_c:0.", cats: ["m_c": clan.living[0].id])
        kits.newCats = [["litter"]]
        engine.addNewCats(to: &kits, in: &clan, counts: &counts, using: &rng)
        for id in kits.groupCats["n_c:0"] ?? [] {
            XCTAssertTrue(backstories.contains(clan[id]?.backstory ?? "", in: "abandoned_backstories"))
        }
    }

    func testOtherClanCatsGrowUpAndDie() throws {
        var (clan, rng) = clan(seed: 5)
        var cat = engine.factory.make(rank: .kitten, moons: 5, origin: .clanborn, using: &rng)
        cat.otherClan = clan.otherClans[0].id
        clan.outsiders.append(cat)
        for _ in 0..<8 { _ = engine.outsiderMoon(in: &clan, skipping: nil, using: &rng) }
        let grown = try XCTUnwrap(clan[cat.id])
        if grown.isAlive { XCTAssertEqual(grown.rank, .warrior) }
        XCTAssertEqual(ThoughtContext(clan: clan).group(of: grown), grown.isAlive ? "other_clan" : grown.afterlife?.rawValue ?? "")
    }

    func testPatrolsCreateOtherClanCatsAndBackstories() throws {
        let patrols = Self.assets.patrols
        var otherClanCats = 0, backstoried = 0
        for seed in 0..<40 as Range<UInt64> {
            var (clan, rng) = clan(seed: 200 + seed)
            for _ in 0..<30 {
                for type in [PatrolType.hunting, .border, .training] {
                    let eligible = PatrolEngine.eligible(in: clan).filter { ![.medicineCat, .medicineApprentice].contains($0.rank) }
                    guard !eligible.isEmpty else { continue }
                    let chosen = Array(eligible.shuffled(using: &rng).prefix(Int.random(in: 1...3, using: &rng))).map(\.id)
                    guard let session = patrols.start(chosen, type: type, in: &clan, using: &rng) else { continue }
                    let result = patrols.finish(session, choice: .proceed, in: &clan, using: &rng)
                    for token in ["{", "n_c", "o_c_n"] { XCTAssertFalse(result.text.contains(token), result.text) }
                }
                clan.patrolledThisMoon = []
                engine.advance(&clan, using: &rng)
            }
            otherClanCats += clan.outsiders.filter(\.belongsToOtherClan).count
            backstoried += (clan.cats + clan.outsiders).filter { $0.backstory != nil }.count
            XCTAssertTrue((clan.cats + clan.outsiders).allSatisfy { $0.backstory != nil })
        }
        print("other-Clan cats met on patrols:", otherClanCats)
        XCTAssertGreaterThan(otherClanCats, 0)
        XCTAssertGreaterThan(backstoried, 0)
    }

    func testOldSavesGetBackstories() throws {
        var (clan, rng) = clan(seed: 7)
        let parent = clan.living[0].id
        var kit = engine.factory.make(rank: .kitten, moons: 3, origin: .clanborn, using: &rng)
        kit.parents = [parent]
        var joiner = engine.factory.makeJoiner(origin: .rogue, using: &rng)
        var pet = engine.factory.make(rank: .warrior, origin: .kittypet, using: &rng)
        clan.cats += [kit, joiner]
        clan.outsiders.append(pet)
        for i in clan.cats.indices where clan.cats[i].id != clan.guide { clan.cats[i].backstory = nil }
        clan.outsiders[clan.outsiders.count - 1].backstory = nil
        let data = try JSONEncoder().encode(clan)
        clan = try JSONDecoder().decode(Clan.self, from: data)

        MoonEngine.fillMissingBackstories(in: &clan, using: &rng)
        XCTAssertEqual(clan[parent]?.backstory, "clan_founder")
        XCTAssertEqual(clan[kit.id]?.backstory, "clanborn")
        joiner = try XCTUnwrap(clan[joiner.id])
        XCTAssertTrue(backstories.contains(joiner.backstory ?? "", in: "rogue_backstories"))
        pet = try XCTUnwrap(clan[pet.id])
        XCTAssertTrue(backstories.contains(pet.backstory ?? "", in: "kittypet_backstories"))
        XCTAssertTrue(clan[clan.guide]?.backstory?.hasPrefix("clan_guide") ?? false)
    }
}
