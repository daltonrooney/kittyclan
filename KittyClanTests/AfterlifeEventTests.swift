import XCTest
@testable import KittyClan

final class AfterlifeEventTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var library: EventLibrary { Self.assets.engine.library! }

    static let afterlifeEventIDs = [
        "app_dead_parent0", "app_dead_parent1", "app_dead_both_parents0", "app_dead_both_parents1",
        "med_dead_mentor0", "med_dead_mentor1", "med_dead_parent0", "med_dead_both_parents0",
        "med_app_dead_parent0", "med_app_dead_both_parents0",
        "warrior_dead_mentor", "warrior_no_leader_dead_mentor0", "warrior_dead_both_parents0", "warrior_dead_both_parents1",
        "warrior_approval0", "warrior_legacy0", "warrior_legacy1",
        "gen_misc_leader_starclan1", "gen_misc_starclanparent_comfort1", "gen_misc_leader_darkforest1", "gen_misc_darkforestparent_taunt1",
    ]
    static let deadNewCatEventIDs = [
        "gen_misc_hitmanfailedmurder2", "gen_new_cat_queenhelpdeath", "gen_new_cat_queenhelpmurder", "gen_new_cat_queenhelpstealdeath",
        "gen_new_cat_queenhelpchildsupport", "gen_new_cat_rogueredemption_kill1", "gen_new_cat_rogueredemption_kill2",
        "mtn_new_cat_litter1", "pln_new_cat_litter_deadparent1",
    ]

    private var engine: MoonEngine { Self.assets.engine }
    private var template: TextTemplate { Self.assets.afterlifeText.template }

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

    private func dead(_ cat: Cat, in afterlife: Afterlife) -> Cat {
        var cat = cat
        cat.isDead = true
        cat.afterlife = afterlife
        return cat
    }

    func testAfterlifeEventsLoad() {
        let afterlife = Self.afterlifeEventIDs.filter(library.eventIDs.contains)
        let dead = Self.deadNewCatEventIDs.filter(library.eventIDs.contains)
        print("afterlife-gated events loaded: \(afterlife.count)/\(Self.afterlifeEventIDs.count) \(afterlife)")
        print("dead new-cat events loaded: \(dead.count)/\(Self.deadNewCatEventIDs.count) \(dead)")
        print("ceremonies:", library.ceremonyCounts, "misc:", library.miscCount, "new cat:", library.newCatCount)
        for id in [
            "gen_misc_leader_starclan1", "gen_misc_starclanparent_comfort1", "gen_misc_leader_darkforest1", "gen_misc_darkforestparent_taunt1",
            "warrior_dead_mentor", "warrior_no_leader_dead_mentor0", "med_dead_mentor0", "med_dead_mentor1",
        ] {
            XCTAssertTrue(library.eventIDs.contains(id), id)
        }
        XCTAssertEqual(dead.count, Self.deadNewCatEventIDs.count)
    }

    func testGroupConstraints() throws {
        var rng = SeededRNG(seed: 1)
        let living = Self.assets.factory.make(rank: .warrior, using: &rng)
        let starClan = dead(living, in: .starClan)
        let darkForest = dead(living, in: .darkForest)
        let foreign = dead(living, in: .unknownResidence)

        let sc = try XCTUnwrap(Constraint(["group": ["starclan"]]))
        XCTAssertEqual([living, starClan, darkForest, foreign].map { sc.matches($0) }, [false, true, false, false])
        let any = try XCTUnwrap(Constraint(["group": ["afterlife"]]))
        XCTAssertEqual([living, starClan, darkForest, foreign].map { any.matches($0) }, [false, true, true, true])
        let notDF = try XCTUnwrap(Constraint(["group": ["-dark_forest"]]))
        XCTAssertEqual([living, starClan, darkForest, foreign].map { notDF.matches($0) }, [true, true, false, true])
        let clanOnly = try XCTUnwrap(Constraint(["group": ["player_clan"]]))
        XCTAssertNil(clanOnly.groups, "the living Clan is the default")
        let match = try XCTUnwrap(Constraint(["group": ["match:m_c"]]))
        XCTAssertTrue(match.matches(darkForest, involved: ["m_c": darkForest]))
        XCTAssertFalse(match.matches(starClan, involved: ["m_c": darkForest]))
        XCTAssertNil(Constraint(["group": ["other_clan"]]), "other Clans' cats aren't simulated")
    }

    func testCandidatesAreOnlyTheRightAfterlife() throws {
        var (clan, rng) = clan(seed: 2)
        let victims = clan.living.filter { $0.rank == .warrior }.prefix(3).map(\.id)
        for id in victims { clan.sendToAfterlife(id, history: nil, using: &rng) }
        let i = try XCTUnwrap(clan.index(of: victims[1]))
        clan.cats[i].afterlife = .darkForest
        engine.fade(victims[2], in: &clan)

        let sc = try XCTUnwrap(Constraint(["group": ["starclan"]]))
        let ids = Set(sc.candidates(in: clan).map(\.id))
        XCTAssertEqual(ids, [victims[0], clan.guide!])
        let df = try XCTUnwrap(Constraint(["group": ["dark_forest"]]))
        XCTAssertEqual(df.candidates(in: clan).map(\.id), [victims[1]])
        let plain = try XCTUnwrap(Constraint([:]))
        XCTAssertEqual(plain.candidates(in: clan).map(\.id), clan.living.map(\.id))
    }

    func testWarriorCeremonyRemembersDeadMentor() throws {
        var (clan, rng) = clan(seed: 3)
        let mentor = try XCTUnwrap(clan.living.first { $0.rank == .warrior })
        let apprentice = try XCTUnwrap(clan.living.first { $0.rank == .warrior && $0.id != mentor.id })
        let a = try XCTUnwrap(clan.index(of: apprentice.id))
        clan.cats[a].formerMentors = [mentor.id]
        clan.sendToAfterlife(mentor.id, history: nil, using: &rng)

        var remembered = 0
        for _ in 0..<400 {
            guard let pick = library.ceremony(for: clan.cats[a], in: clan, using: &rng), pick.cats["r_c0"] == mentor.id else { continue }
            remembered += 1
            let cats = pick.cats.compactMapValues { clan[$0] }
            let text = template.resolve(pick.template, cats: cats, clan: clan, extras: ["r_h": "bravery", "(old_name)": "Testpaw"])
            assertResolved(text)
            XCTAssertTrue(text.contains(Self.assets.displayName(clan[mentor.id]!)), text)
        }
        XCTAssertGreaterThan(remembered, 0, "a dead former mentor appears in warrior ceremonies")
    }

    func testLeaderDreamsOfStarClanLeader() throws {
        var dreamt = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var (clan, rng) = clan(seed: seed)
            let leader = try XCTUnwrap(clan.leader)
            let l = try XCTUnwrap(clan.index(of: leader))
            clan.cats[l].skills.primary = Skill(path: .STAR, points: 25, interestOnly: false)
            let old = try XCTUnwrap(clan.living.first { $0.rank == .warrior })
            let o = try XCTUnwrap(clan.index(of: old.id))
            clan.cats[o].rank = .leader
            clan.sendToAfterlife(old.id, history: nil, using: &rng)

            for _ in 0..<300 {
                let context = engine.eventContext(for: clan, using: &rng)
                guard let pick = library.miscEvent(for: clan.cats[l], in: clan, context: context, using: &rng),
                      let other = pick.cats["r_c"], clan[other]?.isDead == true
                else { continue }
                XCTAssertTrue(other == old.id || other == clan.guide, "the dead leader or a guide who led")
                XCTAssertEqual(clan[other]?.rank, .leader)
                XCTAssertEqual(clan[other]?.afterlife, .starClan)
                let text = template.resolve(pick.template, cats: pick.cats.compactMapValues { clan[$0] }, clan: clan)
                assertResolved(text)
                XCTAssertTrue(text.contains("dreamed"), text)
                dreamt += 1
            }
        }
        XCTAssertGreaterThan(dreamt, 0, "a leader with a StarClan skill dreams of a dead leader")
    }
}
