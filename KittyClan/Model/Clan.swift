import Foundation

struct Pregnancy: Codable, Hashable, Sendable {
    var otherParent: UUID
    var moons = 0
    var litterSize = 0
}

enum Season: String, Codable, CaseIterable, Sendable {
    case newleaf = "Newleaf"
    case greenleaf = "Greenleaf"
    case leafFall = "Leaf-fall"
    case leafBare = "Leaf-bare"
}

struct MoonLog: Codable, Hashable, Sendable, Identifiable {
    /// The clan's age in moons when this happened.
    let moon: Int
    var entries: [LogEntry]

    var id: Int { moon }
}

struct LogEntry: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case ceremony, birth, death, join, relationship, info
        /// Everyday interactions between cats, which change how they feel about each other.
        case interaction
        /// Injuries, illnesses and recoveries.
        case health
        /// What happened on a patrol the player sent out.
        case patrol
        /// News about neighbouring Clans: wars and the leader's den.
        case clans
    }

    var id = UUID()
    var kind: Kind
    var text: String
    var cats: [UUID]
}

struct Clan: Codable, Sendable {
    static let maxLeaderLives = 9

    var prefix: String
    var age = 0
    var cats: [Cat]
    var leader: UUID?
    var deputy: UUID?
    var leaderLives = maxLeaderLives
    var reputation = 80
    var pregnancies: [UUID: Pregnancy] = [:]
    /// Loners, rogues and kittypets the Clan has met, and cats who were lost.
    var outsiders: [Cat] = []
    /// Cats who have already been on a patrol this moon.
    var patrolledThisMoon: Set<UUID> = []
    /// How each cat feels about each other cat: `relationships[from][to]`.
    var relationships: [UUID: [UUID: Relationship]] = [:]
    var history: [MoonLog] = []
    /// Clangen's expanded mode: a fresh-kill pile to feed the Clan, and herbs used in treatment.
    var preyAndHerbs = false
    /// Whether cats who go without food long enough die of starvation, as in Clangen.
    var canStarve = false
    var freshKill = FreshKillPile()
    /// Each cat's nutrition, only tracked with prey and herbs on.
    var nutrition: [UUID: Nutrition] = [:]
    var herbs = HerbSupply()
    var otherClans: [OtherClan] = []
    /// Which of Clangen's four forest camps the Clan lives in (1–4).
    var camp = 1
    var war = War()
    /// This moon's leader's den choices: one about another Clan, one about an outsider.
    var leaderDenPlan: LeaderDenPlan?
    var outsiderDenPlan: LeaderDenPlan?
    /// The StarClan (or Dark Forest) cat who guides the Clan. The Clan's dead follow it.
    var guide: UUID?
    /// Clangen's `fading` setting: long-dead cats fade from the afterlife.
    var fading = true
    var faded: [FadedCat] = []

    var displayName: String { prefix + "Clan" }

    /// Clangen's calendar: each season lasts three moons, starting at Newleaf.
    var season: Season { Season.allCases[(age / 3) % 4] }

    var living: [Cat] { cats.filter(\.isAlive) }
    var dead: [Cat] { cats.filter(\.isDead) }

    subscript(id: UUID?) -> Cat? {
        guard let id else { return nil }
        return cats.first { $0.id == id } ?? outsiders.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        cats.firstIndex { $0.id == id }
    }

    /// Whether the cat is a living member of the Clan.
    func isAlive(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return cats.first { $0.id == id }?.isAlive ?? false
    }

    func otherClan(_ id: UUID?) -> OtherClan? {
        otherClans.first { $0.id == id }
    }

    mutating func changeRelations(with id: UUID, by amount: Int) {
        guard let i = otherClans.firstIndex(where: { $0.id == id }) else { return }
        otherClans[i].changeRelations(by: amount)
    }

    /// Outsider reputation, kept between 0 and 100.
    mutating func changeReputation(by amount: Int) {
        reputation = min(max(reputation + amount, 0), 100)
    }

    /// Clangen's outsider reputation bands.
    var reputationStanding: String {
        switch reputation {
        case ...30: "hostile"
        case ...70: "neutral"
        default: "welcoming"
        }
    }

    func relationship(from: UUID, to: UUID) -> Relationship? {
        relationships[from]?[to]
    }

    /// Edits the relationship from one cat to another, creating it at all zeros if needed.
    mutating func updateRelationship(from: UUID, to: UUID, _ body: (inout Relationship) -> Void) {
        guard from != to else { return }
        body(&relationships[from, default: [:]][to, default: Relationship()])
    }

    /// Ancestors up to grandparents, plus the cat itself.
    private func family(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        for parent in self[id]?.parents ?? [] {
            result.insert(parent)
            result.formUnion(self[parent]?.parents ?? [])
        }
        return result
    }

    /// Clangen's `is_related` with cousins included: parents, children, siblings,
    /// grandparents, grandchildren, aunts, uncles, nieces, nephews and cousins.
    func areRelated(_ a: UUID, _ b: UUID) -> Bool {
        !family(of: a).isDisjoint(with: family(of: b))
    }
}

extension Clan {
    /// Saves from earlier versions may lack newer fields, which then take their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prefix = try c.decode(String.self, forKey: .prefix)
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 0
        cats = try c.decode([Cat].self, forKey: .cats)
        leader = try c.decodeIfPresent(UUID.self, forKey: .leader)
        deputy = try c.decodeIfPresent(UUID.self, forKey: .deputy)
        leaderLives = try c.decodeIfPresent(Int.self, forKey: .leaderLives) ?? Self.maxLeaderLives
        reputation = try c.decodeIfPresent(Int.self, forKey: .reputation) ?? 80
        pregnancies = try c.decodeIfPresent([UUID: Pregnancy].self, forKey: .pregnancies) ?? [:]
        outsiders = try c.decodeIfPresent([Cat].self, forKey: .outsiders) ?? []
        patrolledThisMoon = try c.decodeIfPresent(Set<UUID>.self, forKey: .patrolledThisMoon) ?? []
        relationships = try c.decodeIfPresent([UUID: [UUID: Relationship]].self, forKey: .relationships) ?? [:]
        history = try c.decodeIfPresent([MoonLog].self, forKey: .history) ?? []
        preyAndHerbs = try c.decodeIfPresent(Bool.self, forKey: .preyAndHerbs) ?? false
        canStarve = try c.decodeIfPresent(Bool.self, forKey: .canStarve) ?? false
        freshKill = try c.decodeIfPresent(FreshKillPile.self, forKey: .freshKill) ?? FreshKillPile()
        nutrition = try c.decodeIfPresent([UUID: Nutrition].self, forKey: .nutrition) ?? [:]
        herbs = try c.decodeIfPresent(HerbSupply.self, forKey: .herbs) ?? HerbSupply()
        otherClans = try c.decodeIfPresent([OtherClan].self, forKey: .otherClans) ?? []
        camp = try c.decodeIfPresent(Int.self, forKey: .camp) ?? 1
        war = try c.decodeIfPresent(War.self, forKey: .war) ?? War()
        leaderDenPlan = try c.decodeIfPresent(LeaderDenPlan.self, forKey: .leaderDenPlan)
        outsiderDenPlan = try c.decodeIfPresent(LeaderDenPlan.self, forKey: .outsiderDenPlan)
        guide = try c.decodeIfPresent(UUID.self, forKey: .guide)
        fading = try c.decodeIfPresent(Bool.self, forKey: .fading) ?? true
        faded = try c.decodeIfPresent([FadedCat].self, forKey: .faded) ?? []
    }
}
