import Foundation

enum Rank: String, Codable, CaseIterable, Sendable {
    case newborn
    case kitten
    case apprentice
    case medicineApprentice = "medicine cat apprentice"
    case warrior
    case medicineCat = "medicine cat"
    case deputy
    case leader
    case elder

    var label: String { rawValue.capitalized }

    var isApprentice: Bool { self == .apprentice || self == .medicineApprentice }
    var isBaby: Bool { self == .newborn || self == .kitten }

    /// Clangen's display order, top to bottom.
    static let displayOrder: [Rank] = [
        .leader, .deputy, .medicineCat, .medicineApprentice, .warrior, .apprentice, .elder, .kitten, .newborn,
    ]
}

/// Clangen's three English pronoun sets (`pronouns.en.json` keys 0, 1, 2).
enum Pronouns: String, Codable, CaseIterable, Sendable {
    case they = "0", he = "1", she = "2"
}

struct Cat: Identifiable, Codable, Hashable, Sendable {
    enum Sex: String, Codable, Sendable { case female, male }

    enum Origin: String, Codable, Sendable {
        case founder, clanborn, loner, kittypet, rogue
    }

    let id: UUID
    var name: CatName
    var sex: Sex
    var pronouns: Pronouns
    var moons: Int
    var appearance: CatAppearance
    var personality: Personality
    var rank: Rank
    var origin: Origin = .founder
    var experience = 0

    var mentor: UUID?
    var apprentices: [UUID] = []
    var formerApprentices: [UUID] = []
    var formerMentors: [UUID] = []
    var parents: [UUID] = []
    var mates: [UUID] = []
    var previousMates: [UUID] = []
    var birthCooldown = 0

    var isDead = false
    var diedAtClanAge: Int?

    var age: CatAge { CatAge(moons: moons) }
    var isAlive: Bool { !isDead }

    /// Clangen's `can_have_mate`: not a newborn, kitten or adolescent.
    var isMateAge: Bool { ![.newborn, .kitten, .adolescent].contains(age) }
}

extension CatAge {
    init(moons: Int) {
        self = CatAge.allCases.first { $0.moons.contains(moons) } ?? .senior
    }
}
