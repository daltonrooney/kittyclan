import XCTest
@testable import KittyClan

final class AdoptionGenderTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var engine: MoonEngine { Self.assets.engine }
    private var factory: CatFactory { Self.assets.factory }

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

    private func adult(_ moons: Int, sex: Cat.Sex? = nil, using rng: inout SeededRNG) -> Cat {
        factory.make(rank: .warrior, moons: moons, sex: sex, using: &rng)
    }

    private func kit(_ moons: Int, using rng: inout SeededRNG) -> Cat {
        factory.make(rank: .kitten, moons: moons, using: &rng)
    }

    // MARK: - Adoption

    func testAdoptiveSiblingIsNotALittermate() {
        var (clan, rng) = clan(seed: 11)
        let mom = adult(40, using: &rng), dad = adult(40, using: &rng), carer = adult(50, using: &rng)
        var a = kit(3, using: &rng); a.parents = [mom.id, dad.id]; a.adoptiveParents = [carer.id]
        var b = kit(3, using: &rng); b.adoptiveParents = [carer.id]
        clan.cats += [mom, dad, carer, a, b]

        XCTAssertEqual(clan.siblings(of: a.id).first { $0.id == b.id }?.kind, .adoptiveSibling)
        XCTAssertEqual(clan.family(of: b.id).first { $0.id == a.id }?.kind, .adoptiveSibling)
        XCTAssertTrue(RelationshipRule.kinship("siblings", from: a, to: b, in: clan))
        XCTAssertFalse(RelationshipRule.kinship("littermates", from: a, to: b, in: clan))
    }

    func testLittermatesNeedTheSameBloodParentsAndBirthMoon() {
        var (clan, rng) = clan(seed: 12)
        let mom = adult(40, using: &rng), dad = adult(40, using: &rng)
        var a = kit(3, using: &rng); a.parents = [mom.id, dad.id]
        var b = kit(3, using: &rng); b.parents = [dad.id, mom.id]
        var c = kit(2, using: &rng); c.parents = [mom.id]
        clan.cats += [mom, dad, a, b, c]
        XCTAssertTrue(RelationshipRule.kinship("littermates", from: a, to: b, in: clan))
        XCTAssertFalse(RelationshipRule.kinship("littermates", from: a, to: c, in: clan))
    }

    func testAdoptiveFamilyIsRelated() {
        var (clan, rng) = clan(seed: 13)
        let carer = adult(50, using: &rng), grandparent = adult(100, using: &rng)
        var carerWithParent = carer
        carerWithParent.adoptiveParents = [grandparent.id]
        var a = kit(3, using: &rng); a.adoptiveParents = [carer.id]
        var b = kit(4, using: &rng); b.adoptiveParents = [carer.id]
        clan.cats += [carerWithParent, grandparent, a, b]

        XCTAssertTrue(clan.areRelated(a.id, carer.id))
        XCTAssertTrue(clan.areRelated(carer.id, a.id))
        XCTAssertTrue(clan.areRelated(a.id, b.id))
        XCTAssertTrue(clan.areRelated(a.id, grandparent.id))
        XCTAssertFalse(clan.canChooseMate(clan[a.id]!, clan[carer.id]!))
        let family = clan.family(of: carer.id)
        XCTAssertEqual(Set(family.filter { $0.kind == .adoptiveKit }.map(\.id)), [a.id, b.id])
        XCTAssertEqual(clan.family(of: a.id).first { $0.id == carer.id }?.kind, .adoptiveParent)
        XCTAssertEqual(Set(clan.children(of: carer.id)), [a.id, b.id])
        XCTAssertTrue(clan.bloodChildren(of: carer.id).isEmpty)
    }

    func testParentConstraintsIncludeAdoptiveParents() {
        var (clan, rng) = clan(seed: 14)
        let carer = adult(50, using: &rng)
        var a = kit(3, using: &rng); a.adoptiveParents = [carer.id]
        clan.cats += [carer, a]
        XCTAssertTrue(RelationshipRule.kinship("child/parent", from: a, to: carer, in: clan))
        XCTAssertTrue(RelationshipRule.kinship("parent/child", from: carer, to: a, in: clan))
        XCTAssertFalse(RelationshipRule.kinship("child/parent", from: carer, to: a, in: clan))
    }

    func testAdoptionRules() throws {
        var (clan, rng) = clan(seed: 15)
        let relationships = try XCTUnwrap(engine.relationships)
        let young = adult(20, using: &rng)
        let tooClose = adult(33, using: &rng)
        let oldEnough = adult(34, using: &rng)
        let mate = adult(21, using: &rng)
        let matesMother = adult(60, using: &rng)
        var mateWithMother = mate
        mateWithMother.parents = [matesMother.id]
        clan.cats += [young, tooClose, oldEnough, mateWithMother, matesMother]
        relationships.setMates(young.id, mate.id, in: &clan)

        let candidates = Set(clan.adoptiveParentCandidates(for: young.id).map(\.id))
        XCTAssertTrue(candidates.contains(oldEnough.id))
        XCTAssertFalse(candidates.contains(tooClose.id), "needs a 14-moon gap")
        XCTAssertFalse(candidates.contains(mate.id), "not a mate")
        XCTAssertFalse(candidates.contains(matesMother.id), "not a relative of a mate")
        XCTAssertFalse(candidates.contains(young.id))

        XCTAssertFalse(clan.adopt(young.id, by: tooClose.id))
        let like = clan.relationship(from: oldEnough.id, to: young.id)?.like ?? 0
        XCTAssertTrue(clan.adopt(young.id, by: oldEnough.id))
        XCTAssertEqual(clan[young.id]?.adoptiveParents, [oldEnough.id])
        XCTAssertEqual(clan.relationship(from: oldEnough.id, to: young.id)?.like, min(like + 20, 100))
        XCTAssertFalse(clan.adoptiveParentCandidates(for: young.id).contains { $0.id == oldEnough.id }, "already a parent")
        XCTAssertFalse(clan.adopt(young.id, by: oldEnough.id))

        XCTAssertFalse(clan.unadopt(young.id, from: tooClose.id, using: &rng))
        XCTAssertTrue(clan.unadopt(young.id, from: oldEnough.id, using: &rng))
        XCTAssertTrue(clan[young.id]?.adoptiveParents.isEmpty ?? false)
    }

    func testAdoptionFilters() {
        var (clan, rng) = clan(seed: 16)
        let mom = adult(40, sex: .female, using: &rng), momsMate = adult(45, using: &rng), stranger = adult(45, using: &rng)
        var momWithMate = mom
        momWithMate.mates = [momsMate.id]
        var momsMateWithMom = momsMate
        momsMateWithMom.mates = [mom.id]
        var a = kit(3, using: &rng); a.parents = [mom.id]
        var sibling = kit(20, using: &rng); sibling.moons = 40; sibling.parents = [mom.id]
        clan.cats += [momWithMate, momsMateWithMom, stranger, a, sibling]

        let matesOnly = clan.adoptiveParentCandidates(for: a.id, matesOfParentsOnly: true).map(\.id)
        XCTAssertEqual(matesOnly, [momsMate.id])
        XCTAssertTrue(clan.adoptiveParentCandidates(for: a.id).contains { $0.id == sibling.id })
        XCTAssertFalse(clan.adoptiveParentCandidates(for: a.id, unrelatedOnly: true).contains { $0.id == sibling.id })
        XCTAssertTrue(clan.adoptiveParentCandidates(for: a.id, unrelatedOnly: true).contains { $0.id == stranger.id })
    }

    func testSameSexPairAdoptsALitter() throws {
        var (clan, rng) = clan(seed: 17)
        let relationships = try XCTUnwrap(engine.relationships)
        let a = adult(40, sex: .female, using: &rng), b = adult(40, sex: .female, using: &rng), c = adult(40, using: &rng)
        clan.cats += [a, b, c]
        relationships.setMates(a.id, b.id, in: &clan)
        relationships.setMates(b.id, c.id, in: &clan)

        let events = engine.adoptLitter(by: a.id, with: b.id, in: &clan, using: &rng)
        guard case .adopted(let parents, let kits)? = events.first else { return XCTFail("expected an adoption") }
        XCTAssertEqual(parents, [a.id, b.id])
        XCTAssertFalse(kits.isEmpty)
        XCTAssertEqual(clan[a.id]?.birthCooldown, 6)
        let first = try XCTUnwrap(clan[kits[0]])
        XCTAssertEqual(first.adoptiveParents, [a.id, b.id, c.id])
        XCTAssertEqual(first.parents.count, 1)
        let birthParent = try XCTUnwrap(clan[first.parents[0]])
        XCTAssertTrue(birthParent.isDead)
        XCTAssertTrue(clan.isOutsider(birthParent.id))
        XCTAssertTrue(first.backstory?.hasPrefix("abandoned") ?? false)
        for other in kits.dropFirst() {
            XCTAssertEqual(clan.siblings(of: first.id).first { $0.id == other }?.kind, .littermate)
        }
        XCTAssertEqual(MoonEvent.adopted(parents: parents, kits: kits).kind, .birth)
        let text = engine.narrator.text(for: events[0], in: clan, using: &rng)
        XCTAssertTrue(text.contains("adopt"), text)
    }

    func testPolyMatesAdoptTheLitter() throws {
        var (clan, rng) = clan(seed: 18)
        let relationships = try XCTUnwrap(engine.relationships)
        let mother = adult(40, sex: .female, using: &rng), father = adult(40, sex: .male, using: &rng), third = adult(40, using: &rng)
        clan.cats += [mother, father, third]
        relationships.setMates(mother.id, father.id, in: &clan)
        relationships.setMates(mother.id, third.id, in: &clan)
        let kit = factory.makeKit(mother: try XCTUnwrap(clan[mother.id]), father: father, using: &rng)
        clan.cats.append(kit)

        let adoptive = engine.polyParents(for: [kit], of: try XCTUnwrap(clan[mother.id]), try XCTUnwrap(clan[father.id]), in: &clan)
        XCTAssertEqual(adoptive, [third.id])
        XCTAssertEqual(clan[kit.id]?.adoptiveParents, [third.id])
        XCTAssertEqual(clan[kit.id]?.allParents, [mother.id, father.id, third.id])
    }

    func testAdoptionTag() {
        let (clan, _) = clan(seed: 19)
        XCTAssertTrue(Constraint.isSupportedTag("adoption"))
        var cat = clan.living[0]
        cat.moons = 19
        XCTAssertFalse(Constraint.tagsAllow(["adoption"], in: clan, cat: cat))
        cat.moons = 20
        XCTAssertTrue(Constraint.tagsAllow(["adoption"], in: clan, cat: cat))
    }

    // MARK: - Saves

    private func json(_ cat: Cat, removing keys: [String]) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cat)) as? [String: Any])
        for key in keys { object[key] = nil }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testOldSavesDecode() throws {
        var rng = SeededRNG(seed: 20)
        var cat = adult(40, sex: .male, using: &rng)
        cat.pronouns = [.she]
        cat.adoptiveParents = [UUID()]
        let old = try JSONDecoder().decode(Cat.self, from: json(cat, removing: ["adoptiveParents", "genderAlign"]))
        XCTAssertEqual(old.adoptiveParents, [])
        XCTAssertEqual(old.genderAlign, .transFemale)
        XCTAssertEqual(old.pronouns, [.she])

        cat.pronouns = [.they]
        XCTAssertEqual(try JSONDecoder().decode(Cat.self, from: json(cat, removing: ["genderAlign"])).genderAlign, .nonbinary)
        cat.pronouns = [.he]
        XCTAssertEqual(try JSONDecoder().decode(Cat.self, from: json(cat, removing: ["genderAlign"])).genderAlign, .male)

        cat.genderAlign = GenderAlign(rawValue: "genderfluid")
        let round = try JSONDecoder().decode(Cat.self, from: JSONEncoder().encode(cat))
        XCTAssertEqual(round.genderAlign.rawValue, "genderfluid")
        XCTAssertTrue(round.genderAlign.isCustom)

        let faded = FadedCat(id: UUID(), name: cat.name, pronouns: [.he], rank: .warrior, moons: 40, deadFor: 200, afterlife: .starClan, parents: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(faded)) as? [String: Any])
        object["adoptiveParents"] = nil
        let oldFaded = try JSONDecoder().decode(FadedCat.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(oldFaded.adoptiveParents, [])
    }

    func testOldClanSaveDecodesWithAdoptionOff() throws {
        let (clan, _) = clan(seed: 21)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clan)) as? [String: Any])
        object["sameSexAdoption"] = nil
        let old = try JSONDecoder().decode(Clan.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.sameSexAdoption)
    }

    // MARK: - Gender

    func testBabiesAreAlwaysCis() {
        var rng = SeededRNG(seed: 30)
        for _ in 0..<400 {
            let baby = factory.make(rank: .kitten, moons: Int.random(in: 0...5, using: &rng), using: &rng)
            XCTAssertTrue(baby.isCis)
            XCTAssertEqual(baby.pronouns, [baby.sex == .female ? .she : .he])
        }
    }

    func testChosenSexKeepsPronounsInStep() {
        var rng = SeededRNG(seed: 31)
        var sawTrans = false
        for _ in 0..<2000 {
            let cat = factory.makeJoiner(origin: .loner, sex: .male, using: &rng)
            XCTAssertEqual(cat.sex, .male)
            XCTAssertEqual(cat.pronouns, [cat.genderAlign.defaultPronouns])
            if cat.isCis { XCTAssertEqual(cat.pronouns, [.he]) }
            if cat.genderAlign == .transFemale { sawTrans = true }
        }
        XCTAssertTrue(sawTrans, "some older cats are trans")
    }

    func testGenderLabel() {
        var rng = SeededRNG(seed: 32)
        var cat = adult(40, sex: .female, using: &rng)
        cat.genderAlign = .female
        XCTAssertEqual(cat.genderLabel, "Female")
        cat.genderAlign = .transMale
        XCTAssertEqual(cat.genderLabel, "Trans Male")
        cat.genderAlign = .nonbinary
        XCTAssertEqual(cat.genderLabel, "Nonbinary")
        XCTAssertEqual(Kin.Kind.adoptiveParent.label(for: cat), "Adoptive parent")
        cat.genderAlign = .transFemale
        XCTAssertEqual(Kin.Kind.parent.label(for: cat), "Mother")
    }

    func testSetGender() {
        var (clan, _) = clan(seed: 33)
        let id = clan.living[0].id
        XCTAssertTrue(clan.setGender(id, genderAlign: GenderAlign(rawValue: "star-born!"), pronouns: [.they]))
        XCTAssertEqual(clan[id]?.genderAlign.rawValue, "starborn")
        XCTAssertEqual(clan[id]?.pronouns, [.they])
        XCTAssertFalse(clan.setGender(id, genderAlign: GenderAlign(rawValue: "  "), pronouns: [.he]))
    }

    func testAdjectivesFollowThePronounSet() {
        let (clan, _) = clan(seed: 34)
        var cat = clan.living[0]
        cat.sex = .male
        cat.genderAlign = .transFemale
        cat.pronouns = [.she]
        let template = Self.assets.patrols.template
        XCTAssertEqual(template.resolve("{ADJ/m_c/sibling/brother/sister}", cats: ["m_c": cat], clan: clan), "sister")
        cat.pronouns = [.they]
        XCTAssertEqual(template.resolve("{ADJ/m_c/sibling/brother/sister}", cats: ["m_c": cat], clan: clan), "sibling")
    }
}
