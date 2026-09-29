import Foundation

/// One of Clangen's coming-out events (`events/transition.json`): the cat takes one of the event's
/// new gender identities, and the Clan (or a cat close to them) reacts.
struct TransitionEvent: Sendable {
    let id: String
    let strings: [String]
    let location: [String]
    let season: [String]
    let main: ThoughtCatFilter
    let others: [(abbr: String, filter: ThoughtCatFilter)]
    let rules: [RelationshipRule]
    let changes: [RelationshipChange]
    let newGenders: [GenderAlign]
    /// Accessories `m_c` may gain: ids, or "WILD", "PLANT" or "COLLAR".
    let accessories: [String]
    let weight: Int

    private static let keys: Set<String> = [
        "event_id", "frequency", "location", "season", "strings", "involved_cats", "relationship_constraint",
        "relationship_changes", "new_gender", "gain_accessory",
    ]

    init?(_ json: [String: Any]) {
        guard Set(json.keys).isSubset(of: Self.keys), let id = json["event_id"] as? String,
              let involved = json["involved_cats"] as? [String: [String: Any]],
              let mainJSON = involved["m_c"], let main = ThoughtCatFilter(mainJSON)
        else { return nil }
        var others: [(String, ThoughtCatFilter)] = []
        for abbr in involved.keys.filter({ $0 != "m_c" }).sorted() {
            guard abbr.hasPrefix("r_c"), let filter = ThoughtCatFilter(involved[abbr]!) else { return nil }
            others.append((abbr, filter))
        }
        let ruleJSON = json["relationship_constraint"] as? [[String: Any]] ?? []
        let rules = ruleJSON.compactMap(RelationshipRule.init)
        let changeJSON = json["relationship_changes"] as? [[String: Any]] ?? []
        let changes = changeJSON.compactMap(RelationshipChange.init)
        let accessoryJSON = json["gain_accessory"] as? [[String: Any]] ?? []
        guard rules.count == ruleJSON.count, changes.count == changeJSON.count,
              accessoryJSON.allSatisfy({ $0["cats"] as? [String] == ["m_c"] })
        else { return nil }

        let allowed = Set(["m_c"] + others.map(\.0))
        strings = (json["strings"] as? [String] ?? []).filter { Constraint.textIsSupported($0, allowing: allowed) }
        newGenders = (json["new_gender"] as? [String] ?? []).map(GenderAlign.init)
        guard !strings.isEmpty, !newGenders.isEmpty else { return nil }

        self.id = id
        location = json["location"] as? [String] ?? []
        season = json["season"] as? [String] ?? []
        self.main = main
        self.others = others
        self.rules = rules
        self.changes = changes
        accessories = accessoryJSON.flatMap { $0["accessory"] as? [String] ?? [] }

        var weight = 1
        if !location.isEmpty { weight += 4 * (6 - location.count) }
        if !season.isEmpty { weight += 4 * (4 - season.count) }
        weight += involved.values.reduce(0) { $0 + Self.catWeight($1) }
        if !rules.isEmpty { weight += 20 }
        self.weight = max(1, weight)
    }

    /// Clangen's `TextPoolEvent.involved_cat_weight` for one cat.
    private static func catWeight(_ json: [String: Any]) -> Int {
        func count(_ list: [String]?, total: Int) -> Int {
            guard let list, let first = list.first else { return 0 }
            return first.hasPrefix("-") ? total - list.count : list.count
        }
        var weight = count(json["status"] as? [String], total: Rank.allCases.count)
            + count(json["age"] as? [String], total: CatAge.allCases.count)
            + count(json["group"] as? [String], total: 6)
        if let stat = json["stat"] as? [String: Any] {
            var statWeight = count(stat["skill"] as? [String], total: SkillPath.allCases.count)
                + count(stat["trait"] as? [String], total: 38)
            if stat["must_have_both"] as? Bool == true { statWeight *= 2 }
            weight += statWeight
        }
        if let backstories = json["backstory"] as? [String], let first = backstories.first {
            weight += first.hasPrefix("-") ? backstories.count : max(40 - backstories.count, 1)
        }
        if json["has_mentor"] != nil { weight += 10 }
        return weight
    }

    /// Clangen's `find_cats` for this event: fills each `r_c` from every cat, living or dead, in the
    /// groups it names (living Clan cats when it names none).
    func fill(main cat: Cat, in context: ThoughtContext, using rng: inout some RandomNumberGenerator) -> [String: UUID]? {
        let clan = context.clan
        guard Constraint.locationAllows(location, biome: clan.biome, camp: clan.camp),
              Constraint.listAllows(season, clan.season.rawValue.lowercased()),
              main.matches(cat, main: nil, in: context)
        else { return nil }
        var cats = ["m_c": cat.id]
        for (abbr, filter) in others {
            let pool = filter.groups == nil ? clan.living : clan.cats + clan.outsiders
            let options = pool.filter { !cats.values.contains($0.id) && filter.matches($0, main: cat, in: context) }.shuffled(using: &rng)
            guard let chosen = options.first(where: { candidate in
                var trial = cats.mapValues { [$0] }
                trial[abbr] = [candidate.id]
                return rules.allSatisfy { $0.holds(trial, clan, partial: true) }
            }) else { return nil }
            cats[abbr] = chosen.id
        }
        return rules.allSatisfy { $0.holds(cats.mapValues { [$0] }, clan, partial: false) } ? cats : nil
    }
}

extension EventLibrary {
    /// Clangen's `get_valid_event` without frequencies: events by weight until one fits the cat.
    func transitionEvent(for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> (TransitionEvent, [String: UUID])? {
        let context = ThoughtContext(clan: clan)
        var pool = transitions.filter { $0.accessories.isEmpty || cat.appearance.accessories.count < 3 }
        while !pool.isEmpty {
            let event = pool.remove(at: weighted(Array(zip(pool.indices, pool.map(\.weight))), &rng))
            if let cats = event.fill(main: cat, in: context, using: &rng) { return (event, cats) }
        }
        return nil
    }
}
