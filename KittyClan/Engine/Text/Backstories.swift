import Foundation

/// Clangen's backstory keys and the categories that group them (`resources/dicts/backstories.json`).
struct Backstories: Sendable {
    /// Category name → backstory keys, e.g. "loner_backstories" → ["loner1", …].
    let categories: [String: [String]]
    /// Category names in file order, which decides the short label of a backstory in several categories.
    let categoryOrder: [String]
    /// Old backstory keys and their current names.
    let conversion: [String: String]
    let all: Set<String>

    init(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        categories = (json["backstory_categories"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String] }
        conversion = (json["conversion"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        all = Set(categories.values.joined())
        let raw = String(decoding: data, as: UTF8.self)
        categoryOrder = categories.keys.sorted {
            (raw.range(of: "\"\($0)\"")?.lowerBound ?? raw.endIndex) < (raw.range(of: "\"\($1)\"")?.lowerBound ?? raw.endIndex)
        }
    }

    /// The bundled catalog, or an empty one when the text resources are missing.
    static let bundled: Backstories = {
        guard let url = Bundle.main.url(forResource: "Text", withExtension: nil)?.appending(path: "backstories.json"),
              let data = try? Data(contentsOf: url), let catalog = try? Backstories(data: data)
        else { return Backstories(empty: ()) }
        return catalog
    }()

    private init(empty: Void) {
        categories = [:]
        categoryOrder = []
        conversion = [:]
        all = []
    }

    subscript(category: String) -> [String] { categories[category] ?? [] }

    /// Backstory keys and categories expanded to keys, or nil when an entry is neither.
    func expand(_ entries: some Sequence<String>) -> Set<String>? {
        var result = Set<String>()
        for entry in entries {
            let key = entry.trimmingCharacters(in: .whitespaces)
            if all.contains(key) { result.insert(key) } else if let stories = categories[key] { result.formUnion(stories) } else { return nil }
        }
        return result
    }

    /// The first category holding the backstory, e.g. "former_clancat_backstories".
    func category(of backstory: String) -> String? {
        categoryOrder.first { categories[$0]?.contains(backstory) == true }
    }

    func contains(_ backstory: String, in category: String) -> Bool {
        categories[category]?.contains(backstory) == true
    }

    func random(from category: String, using rng: inout some RandomNumberGenerator) -> String? {
        categories[category]?.randomElement(using: &rng)
    }

    /// Clangen's `_get_random_backstory_from_status`: "clanborn" for Clan cats, otherwise a
    /// loner, rogue or kittypet backstory, with the `baby_` pools for kits.
    func random(for origin: Cat.Origin, baby: Bool, using rng: inout some RandomNumberGenerator) -> String {
        switch origin {
        case .founder: return "clan_founder"
        case .clanborn: return "clanborn"
        case .loner, .rogue, .kittypet:
            let category = (baby ? "baby_" : "") + origin.rawValue + "_backstories"
            return random(from: category, using: &rng) ?? "outsider1"
        }
    }

    /// The way of life a backstory implies, following Clangen's `create_new_cat_block`:
    /// Clan-born and former Clan cat backstories mean a Clan cat.
    func social(of backstory: String) -> NewCatSocial? {
        if contains(backstory, in: "baby_clancat_backstories") || contains(backstory, in: "former_clancat_backstories") { return .clancat }
        if contains(backstory, in: "baby_loner_backstories") || contains(backstory, in: "loner_backstories") { return .loner }
        if contains(backstory, in: "baby_kittypet_backstories") || contains(backstory, in: "kittypet_backstories") { return .kittypet }
        if contains(backstory, in: "rogue_backstories") { return .rogue }
        return nil
    }

    /// Whether a new cat with this backstory comes from a neighbouring Clan.
    func isFromOtherClan(_ backstory: String) -> Bool {
        contains(backstory, in: "former_clancat_backstories") || contains(backstory, in: "baby_clancat_backstories")
    }
}

/// Who a cat created by an event or patrol was before: Clangen's `CatSocial` plus "former clancat".
enum NewCatSocial: String, Sendable {
    case loner, rogue, kittypet, clancat
    case formerClancat = "former clancat"

    var origin: Cat.Origin? {
        switch self {
        case .loner: .loner
        case .rogue: .rogue
        case .kittypet: .kittypet
        case .clancat, .formerClancat: nil
        }
    }
}
