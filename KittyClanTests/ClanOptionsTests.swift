import XCTest
@testable import KittyClan

final class ClanOptionsTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }
    private var factory: CatFactory { Self.assets.factory }

    private func clan(seed: UInt64, members: Int = 7, preyAndHerbs: Bool = false) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        var clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(members)), preyAndHerbs: preyAndHerbs, engine: engine, using: &rng
        )
        clan.allowMurder = false
        return (clan, rng)
    }

    private func adult(_ moons: Int, _ sex: Cat.Sex, using rng: inout SeededRNG) -> Cat {
        var cat = factory.make(rank: .warrior, moons: moons, sex: sex, using: &rng)
        cat.conditions = []
        return cat
    }

    /// A mated she-cat and tom who like each other, added to the Clan.
    private func pair(in clan: inout Clan, using rng: inout SeededRNG) -> (she: UUID, he: UUID) {
        var she = adult(30, .female, using: &rng), he = adult(30, .male, using: &rng)
        she.mates = [he.id]
        he.mates = [she.id]
        clan.cats += [she, he]
        for (a, b) in [(she.id, he.id), (he.id, she.id)] {
            clan.updateRelationship(from: a, to: b) { $0.set(.romance, 60); $0.set(.like, 50) }
        }
        return (she.id, he.id)
    }

    private func assertResolved(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for token in ["{", "}", "m_c", "r_c", "mc_mate", "rc_mate", "c_n", "multi_cat", "%{"] where text.contains(token) {
            XCTFail("unresolved \(token): \(text)", file: file, line: line)
        }
    }

    private func texts(_ events: [MoonEvent], in clan: Clan, using rng: inout SeededRNG) -> [String] {
        events.map { engine.narrator.text(for: $0, in: clan, using: &rng) }
    }

    // MARK: - Pregnancy and birth

    func testPregnancyRunAppliesAndClearsBirthConditions() throws {
        var births = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            let (she, he) = pair(in: &clan, using: &rng)
            let notice = engine.conceive(she, with: he, in: &clan, using: &rng)
            XCTAssertNotNil(clan.pregnancies[she])
            XCTAssertEqual(clan.pregnancies[she]?.otherParent, he)
            let pregnant = try XCTUnwrap(clan[she]?.condition("pregnant", .injury))
            XCTAssertTrue(["minor", "major"].contains(pregnant.severity))
            for text in texts(notice, in: clan, using: &rng) { assertResolved(text) }
            XCTAssertEqual(notice.first?.kind, .birth)

            engine.advance(&clan, using: &rng)
            XCTAssertEqual(clan[she]?.condition("pregnant", .injury)?.severity, "major", "a pregnancy is major by its second moon")
            XCTAssertGreaterThan(clan.pregnancies[she]?.litterSize ?? 0, 0)
            XCTAssertTrue(clan[she]!.isNotWorking)
            XCTAssertFalse(PatrolEngine.eligible(in: clan).contains { $0.id == she }, "an expecting queen doesn't patrol")

            let before = Set(clan.cats.map(\.id))
            engine.advance(&clan, using: &rng)
            XCTAssertNil(clan.pregnancies[she])
            let kits = clan.cats.filter { !before.contains($0.id) && $0.parents.contains(she) }
            XCTAssertFalse(kits.isEmpty, "kits are born")
            XCTAssertTrue(kits.allSatisfy { $0.parents == [she, he] })
            let birth = try XCTUnwrap(clan.history.last?.entries.first { $0.cats.contains(kits[0].id) })
            assertResolved(birth.text)
            XCTAssertFalse(clan[she]!.has("pregnant"), "the pregnant condition ends at birth")
            guard clan.isAlive(she) else { continue }
            births += 1
            XCTAssertTrue(clan[she]!.has("recovering from birth"))
            XCTAssertEqual(clan[she]?.birthCooldown, 6)

            for _ in 0..<12 where clan[she]?.has("recovering from birth") == true {
                engine.advance(&clan, using: &rng)
            }
            if clan.isAlive(she) { XCTAssertFalse(clan[she]!.has("recovering from birth"), "she recovers") }
        }
        XCTAssertGreaterThan(births, 3)
    }

    func testChildbirthMortalityComesFromThePregnantConditionInExpandedMode() throws {
        for expanded in [true, false] {
            var deaths = 0
            for seed in 1...10 as ClosedRange<UInt64> {
                var (clan, rng) = clan(seed: seed, preyAndHerbs: expanded)
                let (she, he) = pair(in: &clan, using: &rng)
                _ = engine.conceive(she, with: he, in: &clan, using: &rng)
                let i = try XCTUnwrap(clan.index(of: she))
                let c = try XCTUnwrap(clan.cats[i].conditions.firstIndex { $0.name == "pregnant" })
                XCTAssertEqual(clan.cats[i].conditions[c].mortality, 40, "a young adult's pregnancy is 1 in 40")
                clan.cats[i].conditions[c].mortality = 1
                clan.pregnancies[she]?.moons = 2
                clan.pregnancies[she]?.litterSize = 2
                _ = engine.pregnancy(for: she, in: &clan, using: &rng)
                if !clan.isAlive(she) { deaths += 1 }
            }
            if expanded {
                XCTAssertEqual(deaths, 10, "expanded mode uses the condition's mortality")
            } else {
                XCTAssertLessThan(deaths, 3, "classic mode keeps Clangen's 1 in 40")
            }
        }
    }

    func testPregnantMortalityByAge() {
        let pregnant = Self.assets.engine.conditions!.conditions["pregnant"]!
        XCTAssertEqual(pregnant.mortality["young adult"], 40)
        XCTAssertEqual(pregnant.mortality["adult"], 40)
        XCTAssertEqual(pregnant.mortality["senior adult"], 30)
        XCTAssertEqual(pregnant.mortality["senior"], 20)
    }

    func testPregnantCatSkipsDeathRollsAndInjuriesPause() throws {
        var (clan, rng) = clan(seed: 3)
        let (she, he) = pair(in: &clan, using: &rng)
        _ = engine.conceive(she, with: he, in: &clan, using: &rng)
        engine.getInjured(she, "sprain", in: &clan, using: &rng)
        let i = try XCTUnwrap(clan.index(of: she))
        clan.cats[i].conditions = clan.cats[i].conditions.map { var c = $0; c.eventTriggered = false; return c }
        var skip: Set<String> = []
        _ = engine.progressConditions(for: she, skip: &skip, in: &clan, using: &rng)
        XCTAssertTrue(clan[she]!.has("sprain"), "injuries don't progress while pregnant")

        clan.pregnancies[she] = nil
        _ = engine.progressConditions(for: she, skip: &skip, in: &clan, using: &rng)
        XCTAssertFalse(clan[she]!.has("pregnant"), "a pregnant condition without a pregnancy is cleared")
    }

    // MARK: - Kits settings

    func testUnmatedCatsNeedASetting() throws {
        var (clan, rng) = clan(seed: 4)
        let loner = adult(40, .female, using: &rng)
        clan.cats.append(loner)
        XCTAssertFalse(engine.canHaveKits(loner, in: clan))
        clan.singleParentage = true
        XCTAssertTrue(engine.canHaveKits(loner, in: clan))
        clan.singleParentage = false
        clan.unmatedParentage = true
        XCTAssertTrue(engine.canHaveKits(loner, in: clan))
    }

    func testUnmatedParentageFindsTheLovedCat() throws {
        var (clan, rng) = clan(seed: 5)
        let she = adult(40, .female, using: &rng), he = adult(42, .male, using: &rng)
        clan.cats += [she, he]
        for (a, b) in [(she.id, he.id), (he.id, she.id)] {
            clan.updateRelationship(from: a, to: b) { $0.set(.romance, 60); $0.set(.like, 50) }
        }
        XCTAssertNil(engine.secondParent(for: she, in: clan, using: &rng).0, "unmated cats have no partner by default")
        clan.unmatedParentage = true
        var found = 0
        for _ in 0..<50 {
            let (partner, isAffair) = engine.secondParent(for: she, in: clan, using: &rng)
            if partner?.id == he.id { found += 1; XCTAssertTrue(isAffair) }
        }
        XCTAssertGreaterThan(found, 8, "a cat in love co-parents with a 1 in 3 chance")
    }

    func testAffairsNeedTheSetting() throws {
        var (clan, rng) = clan(seed: 6)
        let (she, he) = pair(in: &clan, using: &rng)
        let lover = adult(32, .male, using: &rng)
        clan.cats.append(lover)
        for (a, b) in [(she, lover.id), (lover.id, she)] {
            clan.updateRelationship(from: a, to: b) { $0.set(.romance, 100); $0.set(.like, 50) }
        }
        let cat = try XCTUnwrap(clan[she])
        for _ in 0..<50 { XCTAssertEqual(engine.secondParent(for: cat, in: clan, using: &rng).0?.id, he) }
        clan.affairs = true
        var strayed = 0
        for _ in 0..<100 where engine.secondParent(for: cat, in: clan, using: &rng).0?.id == lover.id { strayed += 1 }
        XCTAssertGreaterThan(strayed, 5)
    }

    func testAffairBirthUsesAffairText() throws {
        var affairs = 0
        for seed in 1...10 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            clan.affairs = true
            let (she, he) = pair(in: &clan, using: &rng)
            let lover = adult(32, .male, using: &rng)
            clan.cats.append(lover)
            _ = engine.conceive(she, with: lover.id, in: &clan, using: &rng)
            XCTAssertEqual(clan.pregnancies[she]?.otherParent, lover.id)
            clan.pregnancies[she]?.moons = 2
            clan.pregnancies[she]?.litterSize = 2
            let events = engine.pregnancy(for: she, in: &clan, using: &rng)
            for text in texts(events, in: clan, using: &rng) { assertResolved(text) }
            let kits = clan.cats.filter { $0.parents.contains(she) }
            XCTAssertTrue(kits.allSatisfy { $0.parents == [she, lover.id] })
            if kits.first?.adoptiveParents.contains(he) == false { affairs += 1 }
            XCTAssertTrue(clan.relationship(from: he, to: she)!.romance < 60 || kits.first?.adoptiveParents.contains(he) == true,
                          "the mate learns of it, or raises the kits unknowing")
        }
        XCTAssertGreaterThan(affairs, 0)
    }

    func testSingleParentageGivesOneParentKits() throws {
        var (clan, rng) = clan(seed: 7)
        clan.singleParentage = true
        let queen = adult(40, .female, using: &rng), he = adult(40, .male, using: &rng)
        clan.cats += [queen, he]
        let she = queen.id
        _ = engine.conceive(she, with: nil, in: &clan, using: &rng)
        XCTAssertNotNil(clan.pregnancies[she])
        XCTAssertNil(clan.pregnancies[she]?.otherParent)

        let events = engine.conceive(he.id, with: nil, in: &clan, using: &rng)
        XCTAssertNil(clan.pregnancies[he.id], "a single tom can't carry kits")
        let kits = clan.cats.filter { $0.parents == [he.id] }
        XCTAssertFalse(kits.isEmpty, "he brings home a litter")
        XCTAssertTrue(kits.allSatisfy { ["halfclan2", "outsider_roots2"].contains($0.backstory ?? "") })
        for text in texts(events, in: clan, using: &rng) { assertResolved(text) }

        clan.pregnancies[she]?.moons = 2
        clan.pregnancies[she]?.litterSize = 3
        let birth = engine.pregnancy(for: she, in: &clan, using: &rng)
        for text in texts(birth, in: clan, using: &rng) { assertResolved(text) }
        XCTAssertTrue(clan.cats.filter { $0.parents.first == she }.allSatisfy { $0.parents == [she] })
    }

    func testSameSexBirthLetsEitherCatCarry() throws {
        var (clan, rng) = clan(seed: 8)
        var a = adult(30, .male, using: &rng), b = adult(30, .male, using: &rng)
        a.mates = [b.id]; b.mates = [a.id]
        clan.cats += [a, b]
        for (x, y) in [(a.id, b.id), (b.id, a.id)] {
            clan.updateRelationship(from: x, to: y) { $0.set(.romance, 90); $0.set(.comfort, 90); $0.set(.trust, 90) }
        }
        func pregnancies(sameSexBirth: Bool) -> Int {
            var count = 0
            for _ in 0..<300 {
                var copy = clan
                copy.sameSexBirth = sameSexBirth
                _ = engine.pregnancy(for: a.id, in: &copy, using: &rng)
                if copy.pregnancies[a.id] != nil { count += 1 }
            }
            return count
        }
        XCTAssertEqual(pregnancies(sameSexBirth: false), 0)
        XCTAssertGreaterThan(pregnancies(sameSexBirth: true), 0)
        clan.sameSexBirth = true
        _ = engine.conceive(a.id, with: b.id, in: &clan, using: &rng)
        XCTAssertEqual(clan.pregnancies[a.id]?.otherParent, b.id, "the cat who rolled carries the kits")
        XCTAssertTrue(clan[a.id]!.has("pregnant"))
        XCTAssertTrue(clan.mateCandidates(for: a.id, kitsOnly: true).contains { $0.sex == .male })
    }

    func testKitChanceFollowsSettings() throws {
        var (clan, rng) = clan(seed: 9)
        let (she, he) = pair(in: &clan, using: &rng)
        let first = try XCTUnwrap(clan[she]), second = try XCTUnwrap(clan[he])
        let strict = engine.kitChance(first, second, in: clan)
        clan.affairs = true
        let withAffairs = engine.kitChance(first, second, in: clan)
        XCTAssertGreaterThan(withAffairs, strict, "allowing affairs makes each pair's kits less likely")
        clan.singleParentage = true
        clan.unmatedParentage = true
        XCTAssertGreaterThan(engine.kitChance(first, second, in: clan), withAffairs)
        XCTAssertGreaterThan(engine.kitChance(first, second, isAffair: true, in: clan), engine.kitChance(first, second, in: clan),
                             "affairs use Clangen's unmated odds")
    }

    // MARK: - Mates settings

    func testFormerMentorRomanceSetting() throws {
        var (clan, rng) = clan(seed: 10)
        var mentor = adult(40, .female, using: &rng), student = adult(20, .male, using: &rng)
        mentor.formerApprentices = [student.id]
        student.formerMentors = [mentor.id]
        clan.cats += [mentor, student]
        XCTAssertTrue(clan.isPotentialMate(mentor, student))
        XCTAssertTrue(clan.canChooseMate(mentor, student))
        clan.romanceWithFormerMentor = false
        XCTAssertFalse(clan.isPotentialMate(mentor, student))
        XCTAssertFalse(clan.isPotentialMate(student, mentor, forLoveInterest: true))
        XCTAssertFalse(clan.canChooseMate(mentor, student))
    }

    func testFirstCousinMatesSetting() throws {
        var (clan, rng) = clan(seed: 11)
        let grandma = adult(120, .female, using: &rng), grandpa = adult(120, .male, using: &rng)
        var aunt = adult(70, .female, using: &rng), dad = adult(70, .male, using: &rng)
        aunt.parents = [grandma.id, grandpa.id]; dad.parents = [grandma.id, grandpa.id]
        var cousinA = adult(30, .female, using: &rng), cousinB = adult(30, .male, using: &rng), sibling = adult(30, .female, using: &rng)
        cousinA.parents = [aunt.id]; cousinB.parents = [dad.id]; sibling.parents = [dad.id]
        clan.cats += [grandma, grandpa, aunt, dad, cousinA, cousinB, sibling]
        XCTAssertFalse(clan.isPotentialMate(cousinA, cousinB))
        clan.firstCousinMates = true
        XCTAssertTrue(clan.isPotentialMate(cousinA, cousinB))
        XCTAssertTrue(clan.canChooseMate(cousinA, cousinB))
        XCTAssertFalse(clan.isPotentialMate(sibling, cousinB), "siblings stay related")
        XCTAssertFalse(clan.isPotentialMate(aunt, cousinB), "aunts stay related")
    }

    func testNoMatesCat() throws {
        var (clan, rng) = clan(seed: 12)
        var loner = adult(30, .female, using: &rng)
        let other = adult(30, .male, using: &rng)
        loner.noMates = true
        clan.cats += [loner, other]
        XCTAssertFalse(clan.isPotentialMate(loner, other, forLoveInterest: true))
        XCTAssertTrue(clan.isPotentialMate(loner, other, ignoreNoMates: true))
        XCTAssertTrue(clan.canChooseMate(loner, other), "the player can still choose a mate for them")

        let data = try JSONEncoder().encode(clan)
        let decoded = try JSONDecoder().decode(Clan.self, from: data)
        XCTAssertTrue(decoded[loner.id]!.noMates)
    }

    func testNoMatesCatNeverMovesOn() throws {
        var movedOn = [false: 0, true: 0]
        for noMates in [false, true] {
            for seed in 1...12 as ClosedRange<UInt64> {
                var (clan, rng) = clan(seed: seed)
                var widow = adult(40, .female, using: &rng)
                var mate = adult(40, .male, using: &rng)
                widow.mates = [mate.id]; mate.mates = [widow.id]
                widow.noMates = noMates
                mate.isDead = true
                mate.diedAtClanAge = clan.age - 5
                clan.cats += [widow, mate]
                var counts: [UUID: Int] = [:]
                _ = engine.relationships!.moon(for: widow.id, in: &clan, counts: &counts, using: &rng)
                if clan[widow.id]!.mates.isEmpty { movedOn[noMates, default: 0] += 1 }
            }
        }
        XCTAssertGreaterThan(movedOn[false]!, 0)
        XCTAssertEqual(movedOn[true], 0)
    }

    // MARK: - Roles settings

    func testTwelveMoonGraduation() throws {
        for twelve in [false, true] {
            var (clan, rng) = clan(seed: 13)
            clan.twelveMoonGraduation = twelve
            var apprentice = factory.make(rank: .apprentice, moons: 11, using: &rng)
            apprentice.experience = 0
            apprentice.conditions = []
            clan.cats.append(apprentice)
            engine.advance(&clan, using: &rng)
            guard let cat = clan[apprentice.id], cat.isAlive else { continue }
            XCTAssertEqual(cat.rank.isApprentice, !twelve, "12-moon graduation is \(twelve)")
        }
    }

    func testAssignMentorsSetting() throws {
        for assign in [true, false] {
            var (clan, rng) = clan(seed: 14)
            clan.assignMentors = assign
            var apprentice = factory.make(rank: .apprentice, moons: 7, using: &rng)
            apprentice.conditions = []
            clan.cats.append(apprentice)
            engine.advance(&clan, using: &rng)
            XCTAssertEqual(clan[apprentice.id]?.mentor != nil, assign)
            let warned = clan.history.last!.entries.contains { $0.text.contains("no mentor") }
            XCTAssertEqual(warned, !assign)
        }
        var (clan, rng) = clan(seed: 15)
        clan.assignMentors = false
        let before = clan.living.filter { $0.rank.isApprentice }.map(\.mentor)
        MoonEngine.assignMentor(to: clan.living.first { $0.rank.isApprentice }?.id ?? UUID(), in: &clan, using: &rng)
        XCTAssertEqual(clan.living.filter { $0.rank.isApprentice }.map(\.mentor), before, "a valid mentor is kept")
    }

    func testAutoDeputySetting() throws {
        for auto in [true, false] {
            var (clan, rng) = clan(seed: 16)
            clan.autoDeputy = auto
            let deputy = try XCTUnwrap(clan.deputy)
            engine.setRank(.warrior, for: deputy, in: &clan, using: &rng)
            clan.deputy = nil
            engine.advance(&clan, using: &rng)
            XCTAssertEqual(clan.deputy != nil, auto)
            XCTAssertEqual(clan.history.last!.entries.contains { $0.text == "TestClan has no deputy!" }, !auto)
        }
        XCTAssertFalse(Clan(prefix: "New", cats: []).autoDeputy, "new Clans match Clangen's default")
        let old = try JSONDecoder().decode(Clan.self, from: Data(#"{"prefix":"Old","cats":[]}"#.utf8))
        XCTAssertTrue(old.autoDeputy, "older saves keep naming deputies")
        XCTAssertTrue(old.assignMentors)
        XCTAssertTrue(old.romanceWithFormerMentor)
        XCTAssertFalse(old.disasters)
    }

    func testRetirementSetting() throws {
        let library = Self.assets.engine.conditions!
        let severe = try XCTUnwrap(library.conditions.filter {
            $0.value.kind == .permanent && $0.value.severity == "severe"
        }.map(\.key).sorted().first)
        for never in [false, true] {
            var retired = 0
            for seed in 1...8 as ClosedRange<UInt64> {
                var (clan, rng) = clan(seed: seed)
                clan.noConditionRetirement = never
                var warrior = adult(60, .male, using: &rng)
                warrior.rank = .warrior
                clan.cats.append(warrior)
                engine.getPermanent(warrior.id, severe, in: &clan, using: &rng)
                for _ in 0..<20 where clan[warrior.id]?.rank == .warrior && clan.isAlive(warrior.id) {
                    var skip: Set<String> = []
                    _ = engine.progressDisabilities(for: warrior.id, skip: &skip, in: &clan, using: &rng)
                }
                if clan[warrior.id]?.rank == .elder { retired += 1 }
            }
            if never { XCTAssertEqual(retired, 0) } else { XCTAssertGreaterThan(retired, 0) }
        }
    }

    // MARK: - Disasters

    func testMassDeathEventsLoad() {
        XCTAssertGreaterThanOrEqual(Self.assets.engine.library!.massDeathCount, 11)
    }

    func testDisastersNeedTheSettingAndABigClan() throws {
        var (clan, rng) = clan(seed: 17, members: 7)
        for _ in 0..<12 { clan.cats.append(adult(Int.random(in: 20...90, using: &rng), .female, using: &rng)) }
        let roller = try XCTUnwrap(clan.living.first { $0.rank == .warrior })
        for _ in 0..<20 { XCTAssertTrue(engine.massDeath(by: roller.id, in: &clan, using: &rng).isEmpty) }
        clan.disasters = true

        var small = clan
        small.cats.removeAll { $0.rank == .warrior && $0.id != roller.id && $0.moons < 60 }
        if small.living.count <= 15 {
            for _ in 0..<20 { XCTAssertTrue(engine.massDeath(by: roller.id, in: &small, using: &rng).isEmpty, "needs more than 15 cats") }
        }

        var struck = 0
        for _ in 0..<40 {
            var copy = clan
            let living = copy.living.count
            let events = engine.massDeath(by: roller.id, in: &copy, using: &rng)
            guard !events.isEmpty else { continue }
            struck += 1
            let gone = living - copy.living.count + (copy.leaderLives < clan.leaderLives ? 1 : 0)
            XCTAssertGreaterThan(gone, 2, "a disaster takes more than two cats")
            XCTAssertLessThanOrEqual(gone, 10)
            XCTAssertFalse(copy.isAlive(roller.id), "the cat who rolled it is caught up in it")
            for text in texts(events, in: copy, using: &rng) { assertResolved(text) }
            let lost = copy.outsiders.filter(\.isLost)
            if lost.isEmpty {
                let dead = copy.cats.filter { $0.isDead && !clan[$0.id]!.isDead }
                XCTAssertTrue(dead.allSatisfy { !($0.deaths.last?.text.isEmpty ?? true) }, "each death has a history")
                let shaken = engine.mourn(in: &copy, using: &rng)
                XCTAssertTrue(copy.living.contains { $0.has("shock") } || shaken.count == 1, "more than two deaths leave some cats shaken")
            } else {
                XCTAssertTrue(lost.contains { $0.id == roller.id })
            }
        }
        XCTAssertGreaterThan(struck, 5)
    }
}
