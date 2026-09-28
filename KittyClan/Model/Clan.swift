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
    /// How each cat feels about each other cat: `relationships[from][to]`.
    var relationships: [UUID: [UUID: Relationship]] = [:]
    var history: [MoonLog] = []

    var displayName: String { prefix + "Clan" }

    /// Clangen's calendar: each season lasts three moons, starting at Newleaf.
    var season: Season { Season.allCases[(age / 3) % 4] }

    var living: [Cat] { cats.filter(\.isAlive) }
    var dead: [Cat] { cats.filter(\.isDead) }

    subscript(id: UUID?) -> Cat? {
        guard let id else { return nil }
        return cats.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        cats.firstIndex { $0.id == id }
    }

    func isAlive(_ id: UUID?) -> Bool {
        self[id]?.isAlive ?? false
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
