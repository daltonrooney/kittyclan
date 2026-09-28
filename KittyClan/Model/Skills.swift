import Foundation

/// Clangen's 24 skill paths (`scripts/cat/skills.py`).
enum SkillPath: String, Codable, CaseIterable, Sendable {
    case TEACHER, HUNTER, FIGHTER, RUNNER, CLIMBER, SWIMMER, STEALTH, SPEAKER, MEDIATOR, CLEVER, INSIGHTFUL
    case SENSE, KIT, STORY, LORE, CAMP, HEALER, STAR, OMEN, DREAM, CLAIRVOYANT, PROPHET, GHOST, DARK

    struct Kind: OptionSet, Sendable {
        let rawValue: Int
        static let supernatural = Kind(rawValue: 1 << 0)
        static let strong = Kind(rawValue: 1 << 1)
        static let agile = Kind(rawValue: 1 << 2)
        static let smart = Kind(rawValue: 1 << 3)
        static let observant = Kind(rawValue: 1 << 4)
        static let social = Kind(rawValue: 1 << 5)
    }

    static let uncommon: [SkillPath] = [.GHOST, .PROPHET, .CLAIRVOYANT, .DREAM, .OMEN, .STAR, .HEALER, .DARK]

    /// Which kinds of skill a mentor can help with.
    var kinds: Kind {
        switch self {
        case .TEACHER: [.strong, .agile, .smart, .observant, .social]
        case .HUNTER: [.strong, .agile, .observant]
        case .FIGHTER, .CLIMBER, .SWIMMER: [.strong, .agile]
        case .RUNNER: .agile
        case .STEALTH: [.agile, .social, .smart]
        case .SPEAKER, .MEDIATOR, .STORY, .LORE: [.smart, .social]
        case .CLEVER: .smart
        case .INSIGHTFUL: [.smart, .observant]
        case .SENSE: .observant
        case .KIT: .social
        case .CAMP: [.observant, .social]
        case .HEALER: [.smart, .observant, .social]
        case .OMEN, .CLAIRVOYANT: [.supernatural, .observant]
        case .STAR, .DREAM, .PROPHET, .GHOST, .DARK: .supernatural
        }
    }

    /// The key of the short description in `skills.en.json`, e.g. "hunting".
    var shortKey: String {
        switch self {
        case .TEACHER: "teaching"
        case .HUNTER: "hunting"
        case .FIGHTER: "fighting"
        case .RUNNER: "running"
        case .CLIMBER: "climbing"
        case .SWIMMER: "swimming"
        case .STEALTH: "stealth"
        case .SPEAKER: "speaking"
        case .MEDIATOR: "mediating"
        case .CLEVER: "clever"
        case .INSIGHTFUL: "advising"
        case .SENSE: "observing"
        case .KIT: "caretaking"
        case .STORY: "storytelling"
        case .LORE: "lorekeeping"
        case .CAMP: "campkeeping"
        case .HEALER: "healing"
        case .STAR: "StarClan"
        case .OMEN: "omen"
        case .DREAM: "dreaming"
        case .CLAIRVOYANT: "predicting"
        case .PROPHET: "prophesying"
        case .GHOST: "ghosts"
        case .DARK: "dark forest"
        }
    }

    /// Clangen's `SkillPath.random`: one in fifteen picks is an uncommon skill.
    static func random(excluding: [SkillPath] = [], using rng: inout some RandomNumberGenerator) -> SkillPath {
        let rare = uncommon.filter { !excluding.contains($0) }
        if !rare.isEmpty, oneIn(15, &rng) { return pick(rare, &rng) }
        return pick(allCases.filter { !excluding.contains($0) && !uncommon.contains($0) }, &rng)
    }
}

struct Skill: Codable, Hashable, Sendable {
    var path: SkillPath
    private(set) var points: Int
    /// A kit or apprentice's interest, which only becomes a real skill at graduation.
    var interestOnly: Bool

    init(path: SkillPath, points: Int, interestOnly: Bool) {
        self.path = path
        self.points = min(max(points, 0), 29)
        self.interestOnly = interestOnly
    }

    /// 0 while only an interest, otherwise 1 (0–9 points), 2 (10–19) or 3 (20–29).
    var tier: Int { interestOnly ? 0 : points / 10 + 1 }

    mutating func add(_ amount: Int) { points = min(max(points + amount, 0), 29) }

    static func random(tier: Int?, excluding: [SkillPath] = [], interestOnly: Bool = false, using rng: inout some RandomNumberGenerator) -> Skill {
        let points = if let tier, (1...3).contains(tier) {
            Int.random(in: ((tier - 1) * 10)...((tier - 1) * 10 + 9), using: &rng)
        } else {
            Int.random(in: 0...29, using: &rng)
        }
        return Skill(path: .random(excluding: excluding, using: &rng), points: points, interestOnly: interestOnly)
    }
}

/// A cat's primary and optional secondary skill.
struct CatSkills: Codable, Hashable, Sendable {
    var primary: Skill?
    var secondary: Skill?

    var all: [Skill] { [primary, secondary].compactMap { $0 } }

    func tier(of path: SkillPath) -> Int? {
        all.first { $0.path == path }?.tier
    }

    /// Clangen's `meets_skill_requirement`.
    func meets(_ path: SkillPath, tier: Int) -> Bool {
        all.contains { $0.path == path && $0.tier >= tier }
    }

    /// Parses a Clangen requirement such as "HUNTER,2" (without any leading "-").
    static func requirement(_ token: String) -> (path: SkillPath, tier: Int)? {
        let parts = token.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let path = SkillPath(rawValue: parts[0]), let tier = Int(parts[1]) else { return nil }
        return (path, tier)
    }

    /// Clangen's `_check_cat_skills`: a plain list passes if any entry is met;
    /// a list with "-" entries passes only if none is met.
    func satisfies(_ list: [String]) -> Bool {
        guard !list.isEmpty, !list.contains("any") else { return true }
        let exclusion = list.contains { $0.hasPrefix("-") }
        let met = list.contains { token in
            let name = token.hasPrefix("-") ? String(token.dropFirst()) : token
            guard let (path, tier) = Self.requirement(name) else { return false }
            return meets(path, tier: tier)
        }
        return exclusion ? !met : met
    }

    /// The tier of the skill that meets a patrol stat requirement, for Clangen's +5 per tier bonus.
    func requirementTier(_ list: [String]) -> Int {
        for token in list {
            let exclusion = token.hasPrefix("-")
            guard let (path, tier) = Self.requirement(exclusion ? String(token.dropFirst()) : token) else { continue }
            if meets(path, tier: tier) {
                if !exclusion { return all.first { $0.path == path }?.tier ?? 0 }
            } else if exclusion {
                return primary?.tier ?? 0
            }
        }
        return 0
    }
}
