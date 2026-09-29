import Foundation

enum ConditionKind: String, Codable, Sendable {
    case injury, illness, permanent
}

struct ConditionRisk: Codable, Hashable, Sendable {
    var name: String
    var chance: Int
}

/// An injury, illness or permanent condition a cat has, with its mutable per-cat state
/// (Clangen stores these per cat because treatment and risks change them over time).
struct CatCondition: Codable, Hashable, Sendable {
    var kind: ConditionKind
    var name: String
    var severity: String
    var mortality: Int
    var duration: Int
    /// The Clan's age when the condition started.
    var moonStart: Int
    var risks: [ConditionRisk]
    /// A newly gained condition skips its first moon of progression.
    var eventTriggered: Bool
    var infectiousness = 0
    /// "infected" or "festering" when a wound infection is stopping the injury from healing.
    var complication: String?
    var potentialScars: [String]?
    var bornWith = false
    /// Moons until a congenital condition shows; -2 once revealed.
    var moonsUntil = 0

    func moonsWith(clanAge: Int) -> Int { clanAge - moonStart }

    /// False while a condition the cat was born with hasn't shown yet.
    var isRevealed: Bool { !(bornWith && moonsUntil >= 0) }

    /// Clangen's `pregnant` and `recovering from birth` injuries.
    var isBirthCondition: Bool { kind == .injury && ["pregnant", "recovering from birth"].contains(name) }
}

extension Cat {
    var injuries: [CatCondition] { conditions.filter { $0.kind == .injury } }
    var illnesses: [CatCondition] { conditions.filter { $0.kind == .illness } }
    var permanentConditions: [CatCondition] { conditions.filter { $0.kind == .permanent } }

    var isIll: Bool { conditions.contains { $0.kind == .illness } }
    var isInjured: Bool { conditions.contains { $0.kind == .injury } }
    var isDisabled: Bool { conditions.contains { $0.kind == .permanent } }

    /// Clangen's `not_working`: any illness or injury worse than minor. Keeps cats off patrols.
    var isNotWorking: Bool {
        conditions.contains { $0.kind != .permanent && $0.severity != "minor" }
    }

    var isParalyzed: Bool { conditions.contains { $0.kind == .permanent && $0.name == "paralyzed" } }

    func condition(_ name: String, _ kind: ConditionKind) -> CatCondition? {
        conditions.first { $0.name == name && $0.kind == kind }
    }

    func has(_ name: String) -> Bool { conditions.contains { $0.name == name } }
}
