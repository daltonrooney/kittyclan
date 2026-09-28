import Foundation

/// A neighbouring Clan (Clangen's `OtherClan`). Relations are capped at 30 and have no floor.
struct OtherClan: Codable, Hashable, Sendable, Identifiable {
    enum Standing: String, Codable, Sendable { case hostile, neutral, ally }

    let id: UUID
    var prefix: String
    private(set) var relations: Int
    /// Two temperament words, one from each of Clangen's tables, e.g. ("wary", "eager").
    var temperament: [String]

    init(id: UUID = UUID(), prefix: String, relations: Int, temperament: [String]) {
        self.id = id
        self.prefix = prefix
        self.relations = min(relations, 30)
        self.temperament = temperament
    }

    var name: String { prefix + "Clan" }

    var standing: Standing {
        switch relations {
        case ...7: .hostile
        case ...17: .neutral
        default: .ally
        }
    }

    mutating func changeRelations(by amount: Int) { relations = min(relations + amount, 30) }
    mutating func setRelations(_ value: Int) { relations = min(value, 30) }
}

/// Clangen's war state. `trend` is how the current moon of the war went.
struct War: Codable, Hashable, Sendable {
    enum Trend: String, Codable, Sendable { case relUp = "rel_up", neutral, relDown = "rel_down" }

    var enemy: UUID?
    var duration = 0
    var trend = Trend.neutral

    var atWar: Bool { enemy != nil }
    /// A moon of war going badly: more deaths and injuries.
    var isGoingBadly: Bool { atWar && trend != .relUp }
}

/// A leader's den choice, resolved at the start of the next moon.
struct LeaderDenPlan: Codable, Hashable, Sendable {
    enum Target: Codable, Hashable, Sendable {
        case clan(UUID)
        case outsider(UUID)
    }

    var target: Target
    /// e.g. "befriend", "provoke", "praise", "offend", "appease", "antagonize".
    var interaction: String
    var actor: UUID
    var succeeded: Bool
    var playerTemperament: [String]
}
