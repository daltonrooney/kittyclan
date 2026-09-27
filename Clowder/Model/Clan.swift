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
}
