import Foundation

struct CatName: Codable, Hashable, Sendable {
    var prefix: String
    var suffix: String
}

/// Clangen's prefix + suffix naming (`scripts/cat/names.py`), minus biome and history rules.
struct NameGenerator: Sendable {
    private struct Lists: Decodable {
        let normal_prefixes: [String]
        let normal_suffixes: [String]
        let special_suffixes: [String: String]
        let pelt_prefixes: [String: [String]]
        let pelt_suffixes: [String: [String]]
        let tortie_pelt_suffixes: [String: [String]]
        let colour_prefixes: [String: [String]]
        let colour_suffixes: [String: [String]]
        let eye_prefixes: [String: [String]]
        let eye_suffixes: [String: [String]]
        let animal_prefixes: [String]
        let animal_suffixes: [String]
        let inappropriate_names: [String]
        let clan_prefixes: [String]
        let silly_names: [String]
        let human_names: [String]
        let loner_names: [String]
    }

    private let lists: Lists

    init(url: URL) throws {
        lists = try JSONDecoder().decode(Lists.self, from: Data(contentsOf: url))
    }

    static func bundled() throws -> NameGenerator {
        guard let url = Bundle.main.url(forResource: "Sprites/names", withExtension: "json") else {
            throw SpriteError.missingSheet("names.json")
        }
        return try NameGenerator(url: url)
    }

    func generate(for cat: CatAppearance, using rng: inout some RandomNumberGenerator) -> CatName {
        let categories = [
            lists.eye_prefixes[cat.eyeColour],
            lists.colour_prefixes[cat.colour],
            lists.pelt_prefixes[cat.pattern],
        ].compactMap { $0 }.filter { !$0.isEmpty }

        var prefix = ""
        repeat {
            let byAppearance = oneIn(4, &rng) || oneIn(8, &rng)
            prefix = byAppearance && !categories.isEmpty
                ? pick(pick(categories, &rng), &rng)
                : pick(lists.normal_prefixes, &rng)
        } while prefix.isEmpty

        for _ in 0..<200 {
            let pool: [String]
            if oneIn(4, &rng) {
                if cat.isTortie, let tortie = cat.tortiePattern.flatMap({ lists.tortie_pelt_suffixes[$0] }) {
                    pool = tortie
                } else if let pelt = lists.pelt_suffixes[cat.pattern] {
                    pool = pelt + (lists.colour_suffixes[cat.colour] ?? []) + (lists.eye_suffixes[cat.eyeColour] ?? [])
                } else {
                    pool = lists.normal_suffixes
                }
            } else {
                pool = lists.normal_suffixes
            }
            let suffix = pick(pool, &rng)
            if isUsable(prefix: prefix, suffix: suffix) { return CatName(prefix: prefix, suffix: suffix) }
        }
        return CatName(prefix: prefix, suffix: pick(lists.normal_suffixes, &rng))
    }

    /// The name shown for a cat of this rank: kits, apprentices and the leader get special endings.
    func display(_ name: CatName, rank: Rank) -> String {
        let key: String? = switch rank {
        case .newborn: "newborn"
        case .kitten: "kitten"
        case .apprentice: "apprentice"
        case .medicineApprentice: "medicine cat apprentice"
        case .leader: "leader"
        default: nil
        }
        return name.prefix + (key.flatMap { lists.special_suffixes[$0] } ?? name.suffix)
    }

    /// A name for a cat born outside the Clan, which has no suffix (Clangen's `find_outsider_name`).
    func outsiderName(for origin: Cat.Origin, using rng: inout some RandomNumberGenerator) -> CatName {
        let weights: [Int] = switch origin {
        case .kittypet: [30, 50, 10, 10]
        case .rogue: [3, 7, 35, 55]
        default: [5, 15, 50, 30]
        }
        let pools = [lists.silly_names, lists.human_names, lists.loner_names, lists.normal_prefixes]
        return CatName(prefix: pick(weighted(Array(zip(pools, weights)), &rng), &rng), suffix: "")
    }

    func randomClanPrefix(excluding current: String? = nil, using rng: inout some RandomNumberGenerator) -> String {
        let pool = (lists.clan_prefixes + lists.normal_prefixes).filter { $0 != current && $0.count <= 11 }
        return pick(pool, &rng)
    }

    private func isUsable(prefix: String, suffix: String) -> Bool {
        let p = prefix.lowercased()
        let s = suffix.lowercased()
        if lists.inappropriate_names.contains(p + s) { return false }
        let pc = Array(p)
        let sc = Array(s)
        guard let last = pc.last, let first = sc.first else { return true }
        if pc.count >= 2, pc[pc.count - 2] == last, last == first { return false }
        if sc.count >= 2, last == first, first == sc[1] { return false }
        if lists.animal_prefixes.contains(prefix), lists.animal_suffixes.contains(suffix) { return false }
        if p.contains(s) || s.contains(p) { return false }
        return true
    }
}
