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

/// Clangen's `genderalign`: a built-in identity or free text the player typed.
struct GenderAlign: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    static let female = Self(rawValue: "female"), male = Self(rawValue: "male")
    static let transFemale = Self(rawValue: "trans female"), transMale = Self(rawValue: "trans male")
    static let nonbinary = Self(rawValue: "nonbinary")
    static let builtIn: [Self] = [.female, .male, .transFemale, .transMale, .nonbinary]

    static func cis(_ sex: Cat.Sex) -> Self { sex == .female ? .female : .male }
    static func trans(_ sex: Cat.Sex) -> Self { sex == .female ? .transMale : .transFemale }

    var isCustom: Bool { !Self.builtIn.contains(self) }
    var label: String { rawValue.capitalized }

    /// Clangen's `config.json` pronoun sets.
    var defaultPronouns: Pronouns {
        switch self {
        case .male, .transMale: .he
        case .female, .transFemale: .she
        default: .they
        }
    }

    /// Clangen's `describe_appearance` "cat" rule.
    var noun: String {
        switch self {
        case .female, .transFemale: "she-cat"
        case .male, .transMale: "tom"
        default: "cat"
        }
    }
}

struct Cat: Identifiable, Codable, Hashable, Sendable {
    enum Sex: String, Codable, Sendable { case female, male }

    enum Origin: String, Codable, Sendable {
        case founder, clanborn, loner, kittypet, rogue
    }

    let id: UUID
    var name: CatName
    var sex: Sex
    var genderAlign: GenderAlign
    var pronouns: Pronouns
    var moons: Int
    var appearance: CatAppearance
    var personality: Personality
    var skills = CatSkills()
    var rank: Rank
    var origin: Origin = .founder
    var experience = 0

    var mentor: UUID?
    var apprentices: [UUID] = []
    var formerApprentices: [UUID] = []
    var formerMentors: [UUID] = []
    /// Blood parents, birth parent first.
    var parents: [UUID] = []
    var adoptiveParents: [UUID] = []
    var mates: [UUID] = []
    var previousMates: [UUID] = []
    var birthCooldown = 0
    var conditions: [CatCondition] = []

    var isDead = false
    var diedAtClanAge: Int?
    var afterlife: Afterlife?
    var deadFor = 0
    var afterlifeAcceptance: String?
    var deaths: [DeathRecord] = []
    var starClanAffinity = 0
    var darkForestAffinity = 0
    var preventFading = false
    /// A Clangen backstory key, e.g. `clan_guide3`.
    var backstory: String?
    var leaderCeremony: [CeremonyLine] = []
    var thought: Thought?
    /// Set by this moon's events; nil means the everyday thought for the cat's state.
    var nextThought: ThoughtKind?

    /// Outsiders only: lost from the Clan, exiled from it, or driven out of the area.
    var isLost = false
    var isExiled = false
    var isNear = true
    /// The rank a former Clan cat held before leaving, restored if they return.
    var lastClanRank: Rank?

    var age: CatAge { CatAge(moons: moons) }
    var isAlive: Bool { !isDead }

    var isFormerClanCat: Bool { lastClanRank != nil }

    /// An outsider's way of life: loner, rogue or kittypet.
    var social: Origin { [.loner, .rogue, .kittypet].contains(origin) ? origin : .loner }

    /// Clangen's `can_have_mate`: not a newborn, kitten or adolescent.
    var isMateAge: Bool { ![.newborn, .kitten, .adolescent].contains(age) }

    /// Clangen's `get_parents`: blood parents first, then adoptive.
    var allParents: [UUID] { parents + adoptiveParents.filter { !parents.contains($0) } }

    var isCis: Bool { genderAlign == .cis(sex) }

    /// Clangen's profile wording: the sex for cis cats, otherwise the identity.
    var genderLabel: String { isCis ? sex.rawValue.capitalized : genderAlign.label }
}

extension CatAge {
    init(moons: Int) {
        self = CatAge.allCases.first { $0.moons.contains(moons) } ?? .senior
    }
}

extension Cat {
    /// Saves from earlier versions may lack newer fields, which then take their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(CatName.self, forKey: .name)
        sex = try c.decode(Sex.self, forKey: .sex)
        pronouns = try c.decode(Pronouns.self, forKey: .pronouns)
        if let align = try c.decodeIfPresent(GenderAlign.self, forKey: .genderAlign) {
            genderAlign = align
        } else {
            genderAlign = switch (sex, pronouns) {
            case (_, .they): .nonbinary
            case (.female, .he): .transMale
            case (.male, .she): .transFemale
            default: .cis(sex)
            }
        }
        moons = try c.decode(Int.self, forKey: .moons)
        appearance = try c.decode(CatAppearance.self, forKey: .appearance)
        personality = try c.decode(Personality.self, forKey: .personality)
        skills = try c.decodeIfPresent(CatSkills.self, forKey: .skills) ?? CatSkills()
        rank = try c.decode(Rank.self, forKey: .rank)
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? .founder
        experience = try c.decodeIfPresent(Int.self, forKey: .experience) ?? 0
        mentor = try c.decodeIfPresent(UUID.self, forKey: .mentor)
        apprentices = try c.decodeIfPresent([UUID].self, forKey: .apprentices) ?? []
        formerApprentices = try c.decodeIfPresent([UUID].self, forKey: .formerApprentices) ?? []
        formerMentors = try c.decodeIfPresent([UUID].self, forKey: .formerMentors) ?? []
        parents = try c.decodeIfPresent([UUID].self, forKey: .parents) ?? []
        adoptiveParents = try c.decodeIfPresent([UUID].self, forKey: .adoptiveParents) ?? []
        mates = try c.decodeIfPresent([UUID].self, forKey: .mates) ?? []
        previousMates = try c.decodeIfPresent([UUID].self, forKey: .previousMates) ?? []
        birthCooldown = try c.decodeIfPresent(Int.self, forKey: .birthCooldown) ?? 0
        conditions = try c.decodeIfPresent([CatCondition].self, forKey: .conditions) ?? []
        isDead = try c.decodeIfPresent(Bool.self, forKey: .isDead) ?? false
        diedAtClanAge = try c.decodeIfPresent(Int.self, forKey: .diedAtClanAge)
        afterlife = try c.decodeIfPresent(Afterlife.self, forKey: .afterlife)
        deadFor = try c.decodeIfPresent(Int.self, forKey: .deadFor) ?? 0
        afterlifeAcceptance = try c.decodeIfPresent(String.self, forKey: .afterlifeAcceptance)
        deaths = try c.decodeIfPresent([DeathRecord].self, forKey: .deaths) ?? []
        starClanAffinity = try c.decodeIfPresent(Int.self, forKey: .starClanAffinity) ?? 0
        darkForestAffinity = try c.decodeIfPresent(Int.self, forKey: .darkForestAffinity) ?? 0
        preventFading = try c.decodeIfPresent(Bool.self, forKey: .preventFading) ?? false
        backstory = try c.decodeIfPresent(String.self, forKey: .backstory)
        leaderCeremony = try c.decodeIfPresent([CeremonyLine].self, forKey: .leaderCeremony) ?? []
        thought = try c.decodeIfPresent(Thought.self, forKey: .thought)
        nextThought = try c.decodeIfPresent(ThoughtKind.self, forKey: .nextThought)
        isLost = try c.decodeIfPresent(Bool.self, forKey: .isLost) ?? false
        isExiled = try c.decodeIfPresent(Bool.self, forKey: .isExiled) ?? false
        isNear = try c.decodeIfPresent(Bool.self, forKey: .isNear) ?? true
        lastClanRank = try c.decodeIfPresent(Rank.self, forKey: .lastClanRank)
    }
}
