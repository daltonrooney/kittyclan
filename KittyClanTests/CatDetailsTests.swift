import XCTest
@testable import KittyClan

final class CatDetailsTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }
    private var factory: CatFactory { Self.assets.factory }

    private func clan(seed: UInt64) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        var clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(7)), preyAndHerbs: false, engine: engine, using: &rng
        )
        clan.allowMurder = false
        return (clan, rng)
    }

    private func adult(_ moons: Int, _ sex: Cat.Sex? = nil, using rng: inout SeededRNG) -> Cat {
        var cat = factory.make(rank: .warrior, moons: moons, sex: sex, using: &rng)
        cat.conditions = []
        return cat
    }

    private func personality(_ value: Int) -> Personality {
        Personality(lawfulness: value, sociability: value, aggression: value, stability: value, trait: "calm", isKit: false)
    }

    // MARK: - No kits

    func testNoKitsCatNeverHasKits() throws {
        var pregnancies = [false: 0, true: 0]
        for noKits in [false, true] {
            for seed in 1...40 as ClosedRange<UInt64> {
                var (clan, rng) = clan(seed: seed)
                var she = adult(30, .female, using: &rng), he = adult(30, .male, using: &rng)
                she.mates = [he.id]; he.mates = [she.id]
                if seed.isMultiple(of: 2) { she.noKits = noKits } else { he.noKits = noKits }
                clan.cats += [she, he]
                for (a, b) in [(she.id, he.id), (he.id, she.id)] {
                    clan.updateRelationship(from: a, to: b) { $0.set(.romance, 90); $0.set(.comfort, 90); $0.set(.trust, 90) }
                }
                if noKits { XCTAssertFalse(engine.canHaveKits(clan[she.id], in: clan) && engine.canHaveKits(clan[he.id], in: clan)) }
                for _ in 0..<10 {
                    _ = engine.pregnancy(for: she.id, in: &clan, using: &rng)
                    _ = engine.pregnancy(for: he.id, in: &clan, using: &rng)
                }
                if clan.pregnancies[she.id] != nil || clan.pregnancies[he.id] != nil || clan.cats.contains(where: { $0.allParents.contains(she.id) }) {
                    pregnancies[noKits, default: 0] += 1
                }
            }
        }
        XCTAssertGreaterThan(pregnancies[false]!, 0)
        XCTAssertEqual(pregnancies[true], 0)
    }

    func testNoKitsBlocksAdoptionEvents() throws {
        var (clan, rng) = clan(seed: 3)
        var cat = adult(30, using: &rng), mate = adult(30, using: &rng)
        cat.mates = [mate.id]; mate.mates = [cat.id]
        clan.cats += [cat, mate]
        XCTAssertTrue(Constraint.tagsAllow(["adoption"], in: clan, cat: cat))
        cat.noKits = true
        XCTAssertFalse(Constraint.tagsAllow(["adoption"], in: clan, cat: cat))
        cat.noKits = false
        clan.cats[clan.index(of: mate.id)!].noKits = true
        XCTAssertFalse(Constraint.tagsAllow(["adoption"], in: clan, cat: cat), "a mate who wants no kits stops the adoption too")
    }

    // MARK: - No retirement

    func testNoRetireCatStaysAWarriorInOldAge() throws {
        for noRetire in [false, true] {
            var (clan, rng) = clan(seed: 5)
            var old = adult(141, using: &rng)
            old.noRetire = noRetire
            clan.cats.append(old)
            engine.advance(&clan, using: &rng)
            XCTAssertEqual(clan[old.id]?.rank, noRetire ? .warrior : .elder)
        }
    }

    func testNoRetireCatIgnoresConditionRetirement() throws {
        let library = try XCTUnwrap(engine.conditions)
        let severe = try XCTUnwrap(library.conditions.filter {
            $0.value.kind == .permanent && $0.value.severity == "severe"
        }.map(\.key).sorted().first)
        for noRetire in [false, true] {
            var retired = 0
            for seed in 1...8 as ClosedRange<UInt64> {
                var (clan, rng) = clan(seed: seed)
                var warrior = adult(60, .male, using: &rng)
                warrior.noRetire = noRetire
                clan.cats.append(warrior)
                engine.getPermanent(warrior.id, severe, in: &clan, using: &rng)
                for _ in 0..<20 where clan[warrior.id]?.rank == .warrior && clan.isAlive(warrior.id) {
                    var skip: Set<String> = []
                    _ = engine.progressDisabilities(for: warrior.id, skip: &skip, in: &clan, using: &rng)
                }
                if clan[warrior.id]?.rank == .elder { retired += 1 }
            }
            if noRetire { XCTAssertEqual(retired, 0) } else { XCTAssertGreaterThan(retired, 0) }
        }
    }

    func testTogglesSaveAndOldSavesDefaultOff() throws {
        var rng = SeededRNG(seed: 7)
        var cat = adult(30, using: &rng)
        cat.noKits = true
        cat.noRetire = true
        let round = try JSONDecoder().decode(Cat.self, from: JSONEncoder().encode(cat))
        XCTAssertTrue(round.noKits)
        XCTAssertTrue(round.noRetire)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cat)) as? [String: Any])
        object["noKits"] = nil
        object["noRetire"] = nil
        object["beginning"] = nil
        let old = try JSONDecoder().decode(Cat.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.noKits)
        XCTAssertFalse(old.noRetire)
        XCTAssertNil(old.beginning)
    }

    // MARK: - Afterlife temperament

    func testEmptyAfterlifeIsMiddling() {
        let temper = AfterlifeTemper(influencers: [])
        XCTAssertEqual(temper, AfterlifeTemper(influencers: [personality(8)]))
        XCTAssertEqual(temper.words, ["stoic", "observant"])
    }

    func testTemperAveragesAndWords() {
        let temper = AfterlifeTemper(influencers: [personality(12), personality(15)])
        XCTAssertEqual(temper.lawfulness, 13, "integer average, as Clangen's total // n")
        XCTAssertEqual(temper.words, ["logical", "steadfast"])
        XCTAssertEqual(AfterlifeTemper(influencers: [personality(2), personality(3)]).words, ["cunning", "chaotic"])
    }

    func testInfluencersAreTheGuideAndHighRanks() throws {
        var (clan, rng) = clan(seed: 9)
        var leader = adult(80, using: &rng), warrior = adult(80, using: &rng), darkMedic = adult(80, using: &rng), foreign = adult(80, using: &rng)
        leader.rank = .leader
        darkMedic.rank = .medicineCat
        foreign.rank = .deputy
        for (i, place) in [(0, Afterlife.starClan), (1, .starClan), (2, .darkForest), (3, .unknownResidence)] {
            var cat = [leader, warrior, darkMedic, foreign][i]
            cat.isDead = true
            cat.afterlife = place
            clan.cats.append(cat)
        }
        let starClan = Set(clan.influencers(of: .starClan).map(\.id))
        XCTAssertEqual(starClan, [leader.id, try XCTUnwrap(clan.guide)])
        XCTAssertEqual(clan.influencers(of: .darkForest).map(\.id), [darkMedic.id])
        XCTAssertTrue(clan.influencers(of: .unknownResidence).isEmpty)
    }

    func testCompatibilityScalesMurderAffinity() throws {
        var rng = SeededRNG(seed: 10)
        var cat = adult(40, using: &rng)
        cat.personality = personality(8)
        let close = AfterlifeTemper(influencers: [personality(8)])
        let far = AfterlifeTemper(influencers: [personality(16)])
        let middling = AfterlifeTemper(influencers: [Personality(lawfulness: 8, sociability: 8, aggression: 16, stability: 16, trait: "calm", isKit: false)])
        XCTAssertEqual(close.compatibility(with: cat), .positive)
        XCTAssertEqual(far.compatibility(with: cat), .negative)
        XCTAssertEqual(middling.compatibility(with: cat), .neutral)
        XCTAssertEqual(close.scaled(-40, for: cat), -60)
        XCTAssertEqual(far.scaled(-40, for: cat), -20)
        XCTAssertEqual(middling.scaled(-40, for: cat), -40)
        XCTAssertEqual(close.scaled(20, for: cat), 30)
        XCTAssertEqual(far.scaled(20, for: cat), 10)
    }

    func testChangeAffinityUsesEachAfterlife() throws {
        var (clan, rng) = clan(seed: 11)
        let guide = try XCTUnwrap(clan.guide)
        clan.cats[clan.index(of: guide)!].personality = personality(8)
        var murderer = adult(40, using: &rng), darkLeader = adult(80, using: &rng)
        murderer.personality = personality(8)
        darkLeader.personality = Personality(lawfulness: 8, sociability: 8, aggression: 16, stability: 16, trait: "calm", isKit: false)
        darkLeader.rank = .leader
        darkLeader.isDead = true
        darkLeader.afterlife = .darkForest
        clan.cats += [murderer, darkLeader]
        clan.changeAffinity(of: murderer.id, starClan: -40, darkForest: 20)
        XCTAssertEqual(clan[murderer.id]?.starClanAffinity, -60, "StarClan's guide is just like the murderer")
        XCTAssertEqual(clan[murderer.id]?.darkForestAffinity, 20, "the Dark Forest's leader is only half like the murderer")
    }

    func testMurderAffinityIsOneOfTheScaledValues() throws {
        var murdered = false
        for seed in 1...40 as ClosedRange<UInt64> where !murdered {
            var (clan, rng) = clan(seed: seed)
            clan.allowMurder = true
            let cats = clan.living.filter { $0.id != clan.leader && $0.moons >= 12 }
            var counts: [UUID: Int] = [:]
            guard !engine.murder(cats[1].id, by: cats[0].id, in: &clan, counts: &counts, using: &rng).isEmpty else { continue }
            murdered = true
            XCTAssertTrue([-60, -40, -20].contains(clan[cats[0].id]?.starClanAffinity ?? 0))
            XCTAssertTrue([30, 20, 10].contains(clan[cats[0].id]?.darkForestAffinity ?? 0))
        }
        XCTAssertTrue(murdered)
    }

    // MARK: - Kitting thoughts

    func testAbandonedLittersBloodParentIsGladTheKitsAreSafe() throws {
        var (clan, rng) = clan(seed: 12)
        let relationships = try XCTUnwrap(engine.relationships)
        let a = adult(40, .female, using: &rng), b = adult(40, .female, using: &rng)
        clan.cats += [a, b]
        relationships.setMates(a.id, b.id, in: &clan)
        let events = engine.adoptLitter(by: a.id, with: b.id, in: &clan, using: &rng)
        guard case .adopted(_, let kits)? = events.first else { return XCTFail("expected an adoption") }
        let bloodParent = try XCTUnwrap(clan[kits[0]]?.parents.first)
        engine.generateThoughts(in: &clan, using: &rng)
        let thought = try XCTUnwrap(clan[bloodParent]?.thought?.text)
        XCTAssertEqual(thought, kits.count == 1
                       ? "Is glad that {PRONOUN/m_c/poss} kit is safe"
                       : "Is glad that {PRONOUN/m_c/poss} kits are safe")
        XCTAssertNotNil(clan[a.id]?.thought)
    }

    // MARK: - Beginnings

    func testFoundersAndBirthsRecordTheirBeginning() throws {
        var (clan, rng) = clan(seed: 13)
        for cat in clan.living {
            XCTAssertEqual(cat.beginning, Beginning(kind: .founded, moon: 0, age: cat.moons))
        }
        XCTAssertNil(clan[clan.guide]?.beginning)
        let founderID = try XCTUnwrap(clan.leader)

        for _ in 0..<3 { engine.advance(&clan, using: &rng) }
        let mother = adult(30, .female, using: &rng)
        clan.cats.append(mother)
        let kits = engine.makeLitter(2, birthParent: mother, other: nil, backstory: nil, in: &clan, using: &rng)
        XCTAssertEqual(clan[kits[0]]?.beginning, Beginning(kind: .born, moon: 3, age: 0))

        let text = Self.assets.afterlifeText
        let kitStory = text.profileBackstory(of: try XCTUnwrap(clan[kits[0]]), in: clan)
        XCTAssertTrue(kitStory.contains("born on moon 3 during Greenleaf."), kitStory)
        let founder = try XCTUnwrap(clan[founderID])
        let founderStory = text.profileBackstory(of: founder, in: clan)
        XCTAssertTrue(founderStory.contains("helped found the Clan on moon 0 at the age of \(founder.beginning!.age) moons."), founderStory)
    }

    func testJoinersRecordWhenTheyJoined() throws {
        var (clan, rng) = clan(seed: 14)
        var loner = adult(20, using: &rng)
        loner.origin = .loner
        clan.outsiders.append(loner)
        clan.age = 9
        var counts: [UUID: Int] = [:]
        engine.welcomeBack(loner.id, in: &clan, counts: &counts, using: &rng)
        XCTAssertEqual(clan[loner.id]?.beginning, Beginning(kind: .joined, moon: 9, age: 20))
        let story = Self.assets.afterlifeText.profileBackstory(of: try XCTUnwrap(clan[loner.id]), in: clan)
        XCTAssertTrue(story.contains("joined the Clan on moon 9 at the age of 20 moons."), story)
    }

    func testEveryLivingClanCatHasABeginningAfterManyMoons() throws {
        for seed in 20...21 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            clan.singleParentage = true
            for _ in 0..<40 { engine.advance(&clan, using: &rng) }
            for cat in clan.living {
                XCTAssertNotNil(cat.beginning, "\(cat.name.prefix) (\(cat.origin)) has no beginning")
            }
        }
    }

    func testOldSavesDeriveBeginnings() throws {
        var (clan, rng) = clan(seed: 15)
        clan.age = 30
        var kit = adult(10, using: &rng)
        kit.origin = .clanborn
        var loner = adult(30, using: &rng)
        loner.origin = .loner
        let founder = try XCTUnwrap(clan.leader)
        clan.cats[clan.index(of: founder)!].moons += 30
        clan.cats += [kit, loner]

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clan)) as? [String: Any])
        var cats = try XCTUnwrap(object["cats"] as? [[String: Any]])
        for i in cats.indices { cats[i]["beginning"] = nil }
        object["cats"] = cats
        let old = try JSONDecoder().decode(Clan.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old[kit.id]?.beginning, Beginning(kind: .born, moon: 20, age: 0))
        XCTAssertNil(old[loner.id]?.beginning)
        XCTAssertEqual(old[founder]?.beginning, clan[founder]?.beginning)
        XCTAssertNil(old[old.guide]?.beginning)
    }
}
