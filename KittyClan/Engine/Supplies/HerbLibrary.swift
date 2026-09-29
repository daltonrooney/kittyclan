import Foundation

/// Clangen's herbs: where and when they grow, how long they keep, and their names.
struct HerbLibrary: Sendable {
    struct Herb: Sendable {
        let name: String
        let expiration: Int
        /// 1-in-N odds of finding it on a gathering attempt, by biome key and season (0 = none).
        let rarity: [String: [String: Int]]

        func rarity(in biome: Biome, _ season: Season) -> Int {
            rarity[biome.key]?[season.rawValue.lowercased()] ?? 0
        }
    }

    let herbs: [Herb]
    private let names: [String: (one: String, many: String)]
    let storageMessages: [String: [String]]
    let herbUsed: (one: String, many: String)
    let effectText: [String: String]

    init(directory: URL) throws {
        func load(_ name: String) throws -> Any {
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "herbs/\(name).json")))
        }
        let info = try load("herb_info") as? [String: [String: Any]] ?? [:]
        herbs = info.keys.sorted().map { name in
            let entry = info[name]!
            return Herb(name: name, expiration: entry["expiration"] as? Int ?? 6, rarity: entry["rarity"] as? [String: [String: Int]] ?? [:])
        }
        let text = try load("herbs.en") as? [String: Any] ?? [:]
        var names: [String: (String, String)] = [:]
        for herb in herbs {
            if let forms = text[herb.name] as? [String: String] {
                names[herb.name] = (forms["one"] ?? herb.name, forms["many"] ?? herb.name)
            }
        }
        self.names = names
        let used = text["herb_used"] as? [String: String] ?? [:]
        herbUsed = (used["one"] ?? "m_c was given %{herb}.", used["many"] ?? "m_c was given %{herb}.")
        effectText = [
            "mortality": text["mortality_down"] as? String ?? "",
            "duration": text["duration_down"] as? String ?? "",
            "risks": text["risks_down"] as? String ?? "",
        ]
        storageMessages = (try load("med_den_messages") as? [String: Any])?["storage_status"] as? [String: [String]] ?? [:]
    }

    func herb(_ name: String) -> Herb? { herbs.first { $0.name == name } }

    func name(_ herb: String, count: Int) -> String {
        let forms = names[herb] ?? (herb.replacingOccurrences(of: "_", with: " "), herb.replacingOccurrences(of: "_", with: " "))
        return count == 1 ? forms.one : forms.many
    }

    /// "3 moss clumps and 1 cobweb".
    func describe(_ found: [String: Int]) -> String {
        let parts = found.sorted { $0.key < $1.key }.map { "\($0.value) \(name($0.key, count: $0.value))" }
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        }
    }
}

extension HerbSupply {
    /// Clangen's per-herb rating against the Clan's size: empty, low, adequate, full or excess.
    static func rating(_ total: Int, clanSize: Int) -> String {
        let required = clanSize
        let adequate = Int((Double(required) / 3).rounded())
        switch total {
        case ...0: return "empty"
        case ...adequate: return "low"
        case ...required: return "adequate"
        case ...(required * 2): return "full"
        default: return "excess"
        }
    }

    /// Clangen's overall rating, from the scarcest and most plentiful herbs.
    func overallRating(herbs: [String], clanSize: Int) -> String {
        guard total > 0 else { return "empty" }
        let totals = herbs.map { total(of: $0) }
        let average = ((totals.min() ?? 0) + (totals.max() ?? 0)) / 2
        return Self.rating(average, clanSize: clanSize)
    }
}
