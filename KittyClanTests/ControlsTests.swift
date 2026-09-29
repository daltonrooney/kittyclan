import XCTest
@testable import KittyClan

final class ControlsTests: XCTestCase {
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

    func testRoleScreenMatrix() {
        XCTAssertEqual(Rank.warrior.manualTargets(leaderVacant: false, deputyVacant: false), [.medicineCat, .mediator, .elder])
        XCTAssertEqual(Rank.warrior.manualTargets(leaderVacant: true, deputyVacant: true), [.leader, .deputy, .medicineCat, .mediator, .elder])
        XCTAssertEqual(Rank.medicineCat.manualTargets(leaderVacant: true, deputyVacant: true), [.warrior, .mediator, .elder])
        XCTAssertEqual(Rank.apprentice.manualTargets(leaderVacant: true, deputyVacant: true), [.medicineApprentice, .mediatorApprentice])
        XCTAssertTrue(Rank.kitten.manualTargets(leaderVacant: true, deputyVacant: true).isEmpty)
        XCTAssertFalse(Rank.apprentice.manualTargets(leaderVacant: true, deputyVacant: true).contains(.warrior))
    }

    func testRetiringLeaderThenPromotingDeputy() throws {
        var (clan, rng) = clan(seed: 1)
        let leader = try XCTUnwrap(clan.leader)
        let deputy = try XCTUnwrap(clan.deputy)
        XCTAssertFalse(engine.changeRank(.leader, for: deputy, in: &clan, using: &rng), "the leader's place is taken")
        XCTAssertTrue(engine.changeRank(.elder, for: leader, in: &clan, using: &rng))
        XCTAssertNil(clan.leader)
        XCTAssertEqual(clan[leader]?.rank, .elder)

        XCTAssertTrue(engine.changeRank(.leader, for: deputy, in: &clan, using: &rng))
        XCTAssertEqual(clan.leader, deputy)
        XCTAssertNil(clan.deputy)
        XCTAssertEqual(clan.leaderLives, 9)
        XCTAssertFalse(clan[deputy]?.leaderCeremony.isEmpty ?? true)

        let warrior = try XCTUnwrap(clan.living.first { $0.rank == .warrior })
        XCTAssertTrue(engine.changeRank(.deputy, for: warrior.id, in: &clan, using: &rng))
        XCTAssertEqual(clan.deputy, warrior.id)
    }

    func testMentorChange() throws {
        var (clan, rng) = clan(seed: 3)
        var apprentice = clan.living.first { $0.rank == .apprentice }
        if apprentice == nil, let kit = clan.living.first(where: { $0.rank == .warrior && $0.id != clan.deputy }) {
            engine.setRank(.apprentice, for: kit.id, in: &clan, using: &rng)
            apprentice = clan[kit.id]
        }
        let id = try XCTUnwrap(apprentice?.id)
        let candidates = MoonEngine.mentorCandidates(for: id, in: clan)
        XCTAssertTrue(candidates.allSatisfy { [.warrior, .deputy, .leader].contains($0.rank) })
        let current = clan[id]?.mentor
        let next = try XCTUnwrap(candidates.first { $0.id != current })
        MoonEngine.setMentor(next.id, for: id, in: &clan)
        XCTAssertEqual(clan[id]?.mentor, next.id)
        XCTAssertTrue(clan[next.id]?.apprentices.contains(id) == true)
        if let current { XCTAssertFalse(clan[current]?.apprentices.contains(id) ?? false) }
        MoonEngine.setMentor(nil, for: id, in: &clan)
        XCTAssertNil(clan[id]?.mentor)
    }

    func testChooseAndBreakUpMates() throws {
        var (clan, rng) = clan(seed: 4)
        let relationships = try XCTUnwrap(engine.relationships)
        let cat = try XCTUnwrap(clan.living.first { $0.moons >= 12 && $0.mates.isEmpty })
        let candidates = clan.mateCandidates(for: cat.id)
        XCTAssertFalse(candidates.contains { $0.id == cat.id || $0.isDead || $0.moons < 12 })
        let mate = try XCTUnwrap(candidates.first)
        relationships.setMates(cat.id, mate.id, in: &clan)
        XCTAssertFalse(clan.mateCandidates(for: cat.id).contains { $0.id == mate.id })
        let romance = clan.relationship(from: cat.id, to: mate.id)?.romance ?? 0
        relationships.breakUp(cat.id, mate.id, in: &clan, using: &rng)
        XCTAssertEqual(clan[cat.id]?.previousMates, [mate.id])
        XCTAssertLessThan(clan.relationship(from: cat.id, to: mate.id)?.romance ?? 0, max(romance, 1))
    }

    func testRenameKeepsRankEndingUnlessHidden() throws {
        var (clan, _) = clan(seed: 5)
        let names = Self.assets.names
        let leader = try XCTUnwrap(clan.leader)
        XCTAssertTrue(clan.rename(leader, prefix: "Moss!!", suffix: "whisker", hideSpecialSuffix: false, names: names))
        XCTAssertEqual(Self.assets.displayName(try XCTUnwrap(clan[leader])), "Mossstar")
        clan.rename(leader, prefix: "", suffix: "whisker", hideSpecialSuffix: true, names: names)
        XCTAssertEqual(Self.assets.displayName(try XCTUnwrap(clan[leader])), "Mosswhisker")
    }

    func testFamilyTree() throws {
        var (clan, _) = clan(seed: 6)
        let factory = Self.assets.factory
        var rng = SeededRNG(seed: 60)
        let mom = clan.living[1].id, dad = clan.living[2].id
        var a = factory.make(rank: .kitten, moons: 3, using: &rng); a.parents = [mom, dad]
        var b = factory.make(rank: .kitten, moons: 3, using: &rng); b.parents = [mom, dad]
        var c = factory.make(rank: .kitten, moons: 1, using: &rng); c.parents = [mom]
        clan.cats += [a, b, c]
        let family = clan.family(of: a.id)
        XCTAssertEqual(Set(family.filter { $0.kind == .parent }.map(\.id)), [mom, dad])
        XCTAssertEqual(family.first { $0.id == b.id }?.kind, .littermate)
        XCTAssertEqual(family.first { $0.id == c.id }?.kind, .halfSibling)
        XCTAssertEqual(Set(clan.children(of: mom)), [a.id, b.id, c.id])
    }
}
