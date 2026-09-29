import XCTest
@testable import KittyClan

final class AccessoryTests: XCTestCase {
    private static let assets = try! GameAssets.loadBundled()
    private var factory: CatFactory { Self.assets.factory }
    private var index: SpriteIndex { factory.appearance.index }

    private func foundClan(seed: UInt64) -> (Clan, SeededRNG) {
        var rng = SeededRNG(seed: seed)
        let founding = Self.assets.founding
        let candidates = founding.candidates(using: &rng)
        let adults = candidates.filter(ClanFounding.canLead)
        let others = candidates.filter { cat in !adults.prefix(3).contains { $0.id == cat.id } }
        let clan = founding.found(
            prefix: "Test", leader: adults[0], deputy: adults[1], medicineCat: adults[2],
            members: Array(others.prefix(6)), preyAndHerbs: false, engine: Self.assets.engine, using: &rng
        )
        return (clan, rng)
    }

    func testHalfOfKittypetJoinersWearACollar() {
        var rng = SeededRNG(seed: 7)
        let kittypets = (0..<400).map { _ in factory.makeJoiner(origin: .kittypet, using: &rng) }
        let collared = kittypets.filter { $0.appearance.accessories.contains { index.collarStyle(of: $0) != nil } }.count
        XCTAssertGreaterThan(collared, 160)
        XCTAssertLessThan(collared, 240)
        for origin in [Cat.Origin.loner, .rogue] {
            let cats = (0..<200).map { _ in factory.makeJoiner(origin: origin, using: &rng) }
            XCTAssertFalse(cats.contains { $0.appearance.accessories.contains { index.collarStyle(of: $0) != nil } })
        }
    }

    func testRandomCatsNeverGetCollars() {
        var rng = SeededRNG(seed: 3)
        for _ in 0..<2000 {
            let cat = factory.make(rank: .warrior, using: &rng)
            XCTAssertFalse(cat.appearance.accessories.contains { index.collarStyle(of: $0) != nil })
        }
    }

    func testEventAccessoriesSkipWornGroupsAndMissingParts() {
        var rng = SeededRNG(seed: 11)
        var looks = factory.make(rank: .warrior, using: &rng).appearance
        looks.accessories = ["NYLON_pink"]
        XCTAssertNil(factory.appearance.eventAccessory(from: ["COLLAR"], for: looks, using: &rng))

        looks.accessories = []
        looks.scars = ["NOTAIL"]
        let tail = index.wild.filter { index.accessoryBodyParts[$0] == "tail" }
        XCTAssertFalse(tail.isEmpty)
        XCTAssertNil(factory.appearance.eventAccessory(from: tail, for: looks, using: &rng))

        for _ in 0..<50 {
            let collar = try? XCTUnwrap(factory.appearance.eventAccessory(from: ["COLLAR"], for: looks, using: &rng))
            XCTAssertNotNil(collar.flatMap(index.collarStyle(of:)))
        }
    }

    func testAccessoryChanceFollowsClangenModifiers() {
        var rng = SeededRNG(seed: 5)
        var cat = factory.make(rank: .warrior, moons: 60, using: &rng)
        cat.personality.trait = "calm"
        cat.appearance.accessories = []
        XCTAssertEqual(MoonEngine.accessoryChance(for: cat, hadCeremony: false), 150)
        cat.rank = .medicineCat
        cat.personality.trait = "playful"
        XCTAssertEqual(MoonEngine.accessoryChance(for: cat, hadCeremony: true), 20)
        cat.rank = .warrior
        cat.moons = 130
        cat.personality.trait = "cold"
        cat.appearance.accessories = ["MAPLE LEAF"]
        XCTAssertEqual(MoonEngine.accessoryChance(for: cat, hadCeremony: false), 250)
    }

    func testCollarEventGivesACollarNamedByStyle() throws {
        let library = try XCTUnwrap(Self.assets.engine.library)
        XCTAssertGreaterThan(library.accessoryEventCount, 10)
        var (clan, rng) = foundClan(seed: 2)
        let id = try XCTUnwrap(clan.living.first { $0.age == .adult || $0.age == .youngAdult }?.id)
        let i = try XCTUnwrap(clan.index(of: id))
        clan.cats[i].appearance.accessories = []

        var pick = StoryPick(
            template: "m_c disappeared for a few days, then returned to camp with a acc_singular around {PRONOUN/m_c/poss} neck.",
            cats: ["m_c": id], newAccessory: ["COLLAR"]
        )
        XCTAssertTrue(Self.assets.engine.giveAccessory(for: &pick, in: &clan, using: &rng))
        let collar = try XCTUnwrap(clan.cats[i].appearance.accessories.last)
        let style = try XCTUnwrap(index.collarStyle(of: collar)?.style)
        XCTAssertTrue(pick.template.contains("a \(index.accessoryNames[style]!.one) around"), pick.template)
        XCTAssertFalse(Self.assets.engine.giveAccessory(for: &pick, in: &clan, using: &rng))

        clan.cats[i].appearance.accessories = []
        var collarEvents = 0
        for _ in 0..<2000 {
            let event = library.accessoryEvent(for: clan.cats[i], ceremony: false, in: clan, context: .init(), using: &rng)
            XCTAssertFalse(event?.newAccessory.isEmpty ?? false)
            if event?.newAccessory == ["COLLAR"] { collarEvents += 1 }
        }
        XCTAssertGreaterThan(collarEvents, 0)
    }

    func testCatsGainAccessoriesOverManyMoons() {
        var (clan, rng) = foundClan(seed: 9)
        for i in clan.cats.indices { clan.cats[i].appearance.accessories = [] }
        for _ in 0..<60 { Self.assets.engine.advance(&clan, using: &rng) }
        let worn = clan.cats.flatMap(\.appearance.accessories)
        XCTAssertFalse(worn.isEmpty)
        for cat in clan.cats {
            XCTAssertLessThanOrEqual(cat.appearance.accessories.count, 3)
            XCTAssertLessThanOrEqual(cat.appearance.accessories.filter { index.collarStyle(of: $0) != nil }.count, 1)
        }
    }
}
