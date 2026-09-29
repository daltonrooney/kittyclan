import Foundation

/// Where Clangen's dead go: StarClan, the Dark Forest, or the Unknown Residence.
enum Afterlife: String, Codable, CaseIterable, Sendable {
    case starClan = "starclan"
    case darkForest = "dark_forest"
    case unknownResidence = "unknown_residence"

    var label: String {
        switch self {
        case .starClan: "StarClan"
        case .darkForest: "Dark Forest"
        case .unknownResidence: "Unknown Residence"
        }
    }

    /// Clangen's `[fading]` settings: cats fade after 202 moons dead.
    static let ageToFade = 202
}

/// One line of a cat's death history. Leaders get one per life lost.
struct DeathRecord: Codable, Hashable, Sendable {
    /// Clangen text with `m_c` for the dead cat and `r_c` for `involved`, or
    /// `DeathRecord.multiLives` for a life lost alongside the next entry.
    var text: String
    var involved: UUID?
    var moon: Int

    static let multiLives = "multi_lives"
}

/// One passage of a leader's nine-lives ceremony, rendered when shown.
struct CeremonyLine: Codable, Hashable, Sendable {
    var text: String
    /// The cat giving this life, or nil for the intro and the unknown blessing.
    var giver: UUID?
    var virtue: String?
    /// For the unknown blessing: how many lives it gives.
    var extraLives: Int?
}

/// What is kept of a cat once it fades from the afterlife.
struct FadedCat: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: CatName
    var pronouns: Pronouns
    var rank: Rank
    var moons: Int
    var deadFor: Int
    var afterlife: Afterlife
    var parents: [UUID]
    var adoptiveParents: [UUID] = []
}

extension FadedCat {
    /// Saves from earlier versions may lack newer fields, which then take their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(CatName.self, forKey: .name)
        pronouns = try c.decode(Pronouns.self, forKey: .pronouns)
        rank = try c.decode(Rank.self, forKey: .rank)
        moons = try c.decode(Int.self, forKey: .moons)
        deadFor = try c.decode(Int.self, forKey: .deadFor)
        afterlife = try c.decode(Afterlife.self, forKey: .afterlife)
        parents = try c.decode([UUID].self, forKey: .parents)
        adoptiveParents = try c.decodeIfPresent([UUID].self, forKey: .adoptiveParents) ?? []
    }
}

extension Cat {
    /// Clangen's `pelt.opacity`: fades from 100 to 20 as a cat nears 202 moons dead.
    var opacity: Int {
        guard isDead else { return 100 }
        let ratio = Double(deadFor) / Double(Afterlife.ageToFade)
        return Int(80 * (1 - pow(ratio, 5)) + 20)
    }

    /// Clangen's fog stage for a fading cat's sprite.
    var fadeStage: Int? {
        guard isDead, !preventFading else { return nil }
        return switch opacity {
        case 81...97: 0
        case 46...80: 1
        case ...45: 2
        default: nil
        }
    }

    /// Clangen's `dead` setter: kits are always accepted; otherwise a negative affinity for
    /// the afterlife may see the cat rejected into the other one.
    mutating func enterAfterlife(_ destination: Afterlife, moon: Int, using rng: inout some RandomNumberGenerator) {
        isDead = true
        diedAtClanAge = moon
        deadFor = 0
        guard destination != .unknownResidence else {
            afterlife = .unknownResidence
            return
        }
        let other: Afterlife = destination == .starClan ? .darkForest : .starClan
        if [.newborn, .kitten].contains(age) {
            afterlife = destination
            afterlifeAcceptance = Self.acceptanceKey(destination, "kit", using: &rng)
            return
        }
        let affinity = destination == .starClan ? starClanAffinity : darkForestAffinity
        if affinity < 0 {
            if Double.random(in: 0..<1, using: &rng) < Double(-affinity) / 100 {
                afterlife = other
                afterlifeAcceptance = Self.acceptanceKey(destination, "rejected", using: &rng)
                return
            }
            afterlifeAcceptance = Self.acceptanceKey(destination, "contentious", using: &rng)
        } else {
            afterlifeAcceptance = Self.acceptanceKey(destination, "default", using: &rng)
        }
        afterlife = destination
    }

    /// Counts of Clangen's `afterlife_acceptance_options`.
    private static let acceptanceCounts: [String: Int] = [
        "starclan_default": 9, "starclan_rejected": 5, "starclan_contentious": 4, "starclan_kit": 8,
        "dark_forest_default": 8, "dark_forest_rejected": 8, "dark_forest_contentious": 6, "dark_forest_kit": 5,
    ]

    private static func acceptanceKey(_ afterlife: Afterlife, _ kind: String, using rng: inout some RandomNumberGenerator) -> String? {
        let group = "\(afterlife.rawValue)_\(kind)"
        guard let count = acceptanceCounts[group] else { return nil }
        return "\(group)_\(Int.random(in: 0..<count, using: &rng))"
    }
}

extension Clan {
    /// Where the Clan's dead go: wherever its guide resides.
    var guideAfterlife: Afterlife { self[guide]?.afterlife ?? .starClan }

    /// Clangen's `get_default_afterlife_id`: exiles and cats who were never in the Clan go
    /// to the Unknown Residence; everyone else follows the guide.
    func afterlife(for cat: Cat, isOutsider: Bool) -> Afterlife {
        isOutsider && (cat.isExiled || !cat.isFormerClanCat) ? .unknownResidence : guideAfterlife
    }

    /// Kills a Clan cat or outsider and records how it died.
    mutating func sendToAfterlife(_ id: UUID, history: String?, involved: UUID? = nil, using rng: inout some RandomNumberGenerator) {
        let record = DeathRecord(text: history ?? "m_c died.", involved: involved, moon: age)
        if let i = index(of: id) {
            cats[i].deaths.append(record)
            cats[i].enterAfterlife(afterlife(for: cats[i], isOutsider: false), moon: age, using: &rng)
        } else if let i = outsiders.firstIndex(where: { $0.id == id }) {
            outsiders[i].deaths.append(record)
            outsiders[i].enterAfterlife(afterlife(for: outsiders[i], isOutsider: true), moon: age, using: &rng)
        }
    }

    /// Every cat in an afterlife who hasn't faded, Clan cats first.
    var afterlifeCats: [Cat] {
        (cats + outsiders).filter { $0.isDead && $0.afterlife != nil }
    }

    /// Clangen's afterlife lists: the guide first, then the rest; the Unknown Residence
    /// shows only cats who lived near the Clan.
    func residents(of afterlife: Afterlife) -> [Cat] {
        let residents = afterlifeCats.filter { $0.afterlife == afterlife && (afterlife != .unknownResidence || $0.isNear) }
        let guide = residents.filter { $0.id == self.guide }
        return guide + residents.filter { $0.id != self.guide }
    }
}

/// Clangen's murder history, kept on both the murderer and the victim.
struct MurderRecord: Codable, Hashable, Sendable {
    var murderer: UUID
    var victim: UUID
    var moon: Int
    var revealedToClan = false
    /// Cats who know without the Clan knowing.
    var aware: [UUID] = []
}

/// A Clangen `future_event` waiting to happen, e.g. a murder coming to light.
struct PendingEvent: Codable, Hashable, Sendable {
    var eventType: String
    var subTypes: [String]
    var moonsLeft: Int
    /// Cats carried over from the event that scheduled it, by abbreviation.
    var cats: [String: UUID]
}
