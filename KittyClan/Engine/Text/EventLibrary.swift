import Foundation

/// A Clangen event chosen for this moon: its text and the cats filling each abbreviation.
struct StoryPick: Sendable {
    enum LivesLost: Sendable { case one, some, all }

    var template: String
    var cats: [String: UUID]
    var deaths: [UUID] = []
    var livesLost = LivesLost.one
    var relationshipChanges: [RelationshipChange] = []
    /// Abbreviations that stand for several cats, e.g. `multi_cat`.
    var groupCats: [String: [UUID]] = [:]

    /// Every abbreviation with the cats it stands for.
    var allCats: [String: [UUID]] { cats.mapValues { [$0] }.merging(groupCats) { a, _ in a } }
}

/// Clangen's ceremony, death and misc event text, filtered to the features KittyClan simulates.
///
/// Events are kept only when every key, constraint and text token is understood; anything
/// else (other Clans, herbs, skills, injuries…) is dropped at load time rather than half-supported.
struct EventLibrary: Sendable {
    private let ceremonies: [String: [Ceremony]]
    private let honors: [String: [String]]
    /// Short events keyed by sub-type ("" or "old_age") then frequency.
    private let deaths: [String: [Int: [ShortEvent]]]
    private let misc: [Int: [ShortEvent]]
    let announcements: [String]
    let twoParentBirths: [String]
    let kitAmount: [String: String]

    init(directory: URL) throws {
        func load(_ path: String) throws -> Any {
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: path)))
        }
        func events(_ paths: String...) throws -> [[String: Any]] {
            try paths.flatMap { try load($0) as? [[String: Any]] ?? [] }
        }

        var ceremonies: [String: [Ceremony]] = [:]
        for name in ["apprentice", "medicine_cat_apprentice", "warrior", "medicine_cat", "deputy", "leader", "elder"] {
            ceremonies[name] = try events("ceremonies/\(name).json").compactMap(Ceremony.init)
        }
        self.ceremonies = ceremonies
        honors = try load("ceremonies/ceremony_traits.json") as? [String: [String]] ?? [:]

        func group(_ list: [ShortEvent]) -> [Int: [ShortEvent]] { Dictionary(grouping: list, by: \.frequency) }
        let deathEvents = try events("death/general.json", "death/forest.json").compactMap(ShortEvent.init)
        deaths = Dictionary(grouping: deathEvents, by: \.subType).mapValues(group)
        misc = group(try events("misc/general.json", "misc/forest.json").compactMap(ShortEvent.init).filter { $0.subType.isEmpty })

        let pregnancy = try load("pregnancy.json") as? [String: Any] ?? [:]
        announcements = pregnancy["announcement"] as? [String] ?? []
        twoParentBirths = (pregnancy["birth"] as? [String: Any])?["two_parents"] as? [String] ?? []
        kitAmount = (try load("pregnancy.en.json") as? [String: Any])?["kit_amount"] as? [String: String] ?? [:]
    }

    var ceremonyCounts: [String: Int] { ceremonies.mapValues(\.count) }
    var deathCount: Int { deaths.values.flatMap(\.values).reduce(0) { $0 + $1.count } }
    var miscCount: Int { misc.values.reduce(0) { $0 + $1.count } }

    // MARK: - Ceremonies

    static func ceremonyFile(for rank: Rank) -> String? {
        switch rank {
        case .apprentice: "apprentice"
        case .medicineApprentice: "medicine_cat_apprentice"
        case .warrior: "warrior"
        case .medicineCat: "medicine_cat"
        case .deputy: "deputy"
        case .leader: "leader"
        case .elder: "elder"
        default: nil
        }
    }

    func ceremony(for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        guard let file = Self.ceremonyFile(for: cat.rank), var pool = ceremonies[file] else { return nil }
        while !pool.isEmpty {
            let event = pool.remove(at: weighted(Array(zip(pool.indices, pool.map(\.weight))), &rng))
            guard Constraint.tagsAllow(event.tags, in: clan, cat: cat),
                  let text = event.strings.randomElement(using: &rng),
                  Constraint.namedRolesExist(in: text, clan: clan),
                  let cats = event.fill(main: cat, in: clan, using: &rng)
            else { continue }
            return StoryPick(template: text, cats: cats)
        }
        return nil
    }

    /// Clangen's `r_h`: an honor matching the cat's trait.
    func honor(for cat: Cat, using rng: inout some RandomNumberGenerator) -> String {
        honors[cat.personality.trait]?.randomElement(using: &rng) ?? "hard work"
    }

    // MARK: - Short events

    func deathEvent(for cat: Cat, oldAge: Bool, in clan: Clan, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        guard let pool = deaths[oldAge ? "old_age" : ""] else { return nil }
        return shortEvent(from: pool, for: cat, in: clan, using: &rng)
    }

    func miscEvent(for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        shortEvent(from: misc, for: cat, in: clan, using: &rng)
    }

    /// Clangen's `create_short_event`: roll a frequency, filter, pick by weight, then find an `r_c`.
    private func shortEvent(from pool: [Int: [ShortEvent]], for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        let roll = Int.random(in: 1...10, using: &rng)
        let preferred = roll <= 4 ? 4 : roll <= 7 ? 3 : roll <= 9 ? 2 : 1
        let season = clan.season.rawValue.lowercased()
        for frequency in [preferred] + [4, 3, 2, 1].filter({ $0 != preferred }) {
            var candidates = (pool[frequency] ?? []).filter { event in
                Constraint.listAllows(event.season, season)
                    && Constraint.tagsAllow(event.tags, in: clan, cat: cat)
                    && Constraint.namedRolesExist(in: event.text, clan: clan)
                    && event.main.matches(cat, allowNewborn: false)
            }
            while !candidates.isEmpty {
                let event = candidates.remove(at: weighted(Array(zip(candidates.indices, candidates.map(\.weight))), &rng))
                if let pick = event.resolve(for: cat, in: clan, using: &rng) { return pick }
            }
        }
        return nil
    }
}

// MARK: - Parsed events

private struct Ceremony: Sendable {
    let tags: [String]
    let strings: [String]
    let main: Constraint
    let others: [(abbr: String, constraint: Constraint)]
    let relationships: [RelationshipRule]
    let weight: Int

    init?(_ json: [String: Any]) {
        guard let involved = json["involved_cats"] as? [String: [String: Any]],
              let mainJSON = involved["m_c"], let main = Constraint(mainJSON),
              let strings = json["strings"] as? [String], !strings.isEmpty
        else { return nil }
        let abbrs = involved.keys.filter { $0 != "m_c" }.sorted()
        guard abbrs.allSatisfy({ ["r_c0", "r_c1", "r_c2"].contains($0) }) else { return nil }
        var others: [(String, Constraint)] = []
        for abbr in abbrs {
            guard let c = Constraint(involved[abbr]!) else { return nil }
            others.append((abbr, c))
        }
        let rules = (json["relationship_constraint"] as? [[String: Any]] ?? []).compactMap(RelationshipRule.init)
        guard rules.count == (json["relationship_constraint"] as? [Any])?.count ?? 0 else { return nil }
        let tags = json["tags"] as? [String] ?? []
        guard tags.allSatisfy(Constraint.isSupportedTag) else { return nil }

        let allowed = Set(["m_c"] + abbrs)
        self.strings = strings.filter { Constraint.textIsSupported($0, allowing: allowed) }
        guard !self.strings.isEmpty else { return nil }
        self.tags = tags
        self.main = main
        self.others = others
        relationships = rules
        weight = 1 + 2 * tags.count + involved.values.reduce(0) { $0 + $1.count } + (rules.isEmpty ? 0 : 20)
    }

    func fill(main cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> [String: UUID]? {
        guard main.matches(cat) else { return nil }
        var cats = ["m_c": cat.id]
        for (abbr, constraint) in others {
            let options = clan.living.filter { !cats.values.contains($0.id) && constraint.matches($0) }.shuffled(using: &rng)
            guard let chosen = options.first(where: { candidate in
                var trial = cats.mapValues { [$0] }
                trial[abbr] = [candidate.id]
                return relationships.allSatisfy { $0.holds(trial, clan, partial: true) }
            }) else { return nil }
            cats[abbr] = chosen.id
        }
        return relationships.allSatisfy { $0.holds(cats.mapValues { [$0] }, clan, partial: false) } ? cats : nil
    }
}

private struct ShortEvent: Sendable {
    let subType: String
    let frequency: Int
    let season: [String]
    let tags: [String]
    let text: String
    let main: Constraint
    let mainDies: Bool
    let random: Constraint?
    let randomDies: Bool
    let relationshipChanges: [RelationshipChange]
    let weight: Int

    private static let keys: Set<String> = [
        "event_id", "location", "season", "frequency", "sub_type", "tags", "event_text", "death_text",
        "m_c", "r_c", "history", "relationships", "exclude_involved", "supplies",
    ]

    init?(_ json: [String: Any]) {
        // Supply changes are ignored until KittyClan tracks prey and herbs, so only unconditional ones pass.
        let supplies = json["supplies"] as? [[String: Any]] ?? []
        guard Set(json.keys).isSubset(of: Self.keys),
              supplies.allSatisfy({ ($0["trigger"] as? [String]) == ["always"] }),
              let text = (json["event_text"] ?? json["death_text"]) as? String,
              Constraint.textIsSupported(text, allowing: ["m_c", "r_c"])
        else { return nil }
        let subTypes = json["sub_type"] as? [String] ?? []
        guard subTypes.count <= 1 else { return nil }
        let location = json["location"] as? [String] ?? ["any"]
        guard Constraint.listAllows(location, "forest", normalize: { String($0.split(separator: ":")[0]) }) else { return nil }
        let tags = json["tags"] as? [String] ?? []
        guard tags.allSatisfy(Constraint.isSupportedTag) else { return nil }

        let mainJSON = json["m_c"] as? [String: Any] ?? [:]
        guard let main = Constraint(mainJSON) else { return nil }
        let randomJSON = json["r_c"] as? [String: Any]
        if randomJSON == nil, text.contains("r_c") { return nil }
        var random: Constraint?
        if let randomJSON {
            guard let c = Constraint(randomJSON) else { return nil }
            random = c
        }
        if !main.relationshipStatus.isEmpty, random == nil { return nil }
        let changes = (json["relationships"] as? [[String: Any]] ?? []).compactMap(RelationshipChange.init)
        guard changes.count == (json["relationships"] as? [Any])?.count ?? 0 else { return nil }

        subType = subTypes.first ?? ""
        frequency = json["frequency"] as? Int ?? 4
        season = json["season"] as? [String] ?? ["any"]
        self.tags = tags
        self.text = text
        self.main = main
        mainDies = mainJSON["dies"] as? Bool ?? false
        self.random = random
        randomDies = randomJSON?["dies"] as? Bool ?? false
        relationshipChanges = changes

        var weight = 1
        if location != ["any"] { weight += 1 }
        if season != ["any"] { weight += max(0, 4 - season.count) }
        for c in [mainJSON, randomJSON ?? [:]] {
            if let ages = c["age"] as? [String], ages != ["any"] { weight += max(0, 7 - ages.count) }
            if let statuses = c["status"] as? [String], statuses != ["any"] { weight += max(0, 11 - statuses.count) }
            weight += (c["relationship_status"] as? [String])?.count ?? 0
            if let traits = c["trait"] as? [String] { weight += max(0, 54 - traits.count) }
        }
        self.weight = weight
    }

    func resolve(for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        var cats = ["m_c": cat.id]
        var deaths: [UUID] = mainDies ? [cat.id] : []
        if let random {
            let options = clan.living.filter { other in
                other.id != cat.id && random.matches(other, allowNewborn: false)
                    && main.relationshipHolds(from: cat, to: other, in: clan)
                    && random.relationshipHolds(from: other, to: cat, in: clan)
            }
            guard let other = options.randomElement(using: &rng) else { return nil }
            cats["r_c"] = other.id
            if randomDies { deaths.append(other.id) }
        }
        if cat.id == clan.leader, tags.contains("all_lives"), cat.moons < 150, Int.random(in: 0..<5, using: &rng) != 0 {
            return nil
        }
        let lives: StoryPick.LivesLost = tags.contains("all_lives") ? .all : tags.contains("some_lives") ? .some : .one
        return StoryPick(template: text, cats: cats, deaths: deaths, livesLost: lives, relationshipChanges: relationshipChanges)
    }
}
