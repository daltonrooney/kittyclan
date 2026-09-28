import Foundation

/// A Clangen event chosen for this moon: its text and the cats filling each abbreviation.
struct StoryPick: Sendable {
    enum LivesLost: Sendable { case one, some, all }

    var template: String
    var cats: [String: UUID]
    var deaths: [UUID] = []
    var livesLost = LivesLost.one
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
                var trial = cats
                trial[abbr] = candidate.id
                return relationships.allSatisfy { $0.holds(trial, clan, partial: true) }
            }) else { return nil }
            cats[abbr] = chosen.id
        }
        return relationships.allSatisfy { $0.holds(cats, clan, partial: false) } ? cats : nil
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
    let randomRelationship: [String]
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
        // Clangen reads `relationship_status` as m_c → r_c, wherever it is written.
        let relationship = (mainJSON["relationship_status"] as? [String] ?? []) + (randomJSON?["relationship_status"] as? [String] ?? [])
        guard relationship.allSatisfy(RelationshipRule.isSupported), relationship.isEmpty || random != nil else { return nil }

        subType = subTypes.first ?? ""
        frequency = json["frequency"] as? Int ?? 4
        season = json["season"] as? [String] ?? ["any"]
        self.tags = tags
        self.text = text
        self.main = main
        mainDies = mainJSON["dies"] as? Bool ?? false
        self.random = random
        randomDies = randomJSON?["dies"] as? Bool ?? false
        randomRelationship = relationship

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
                    && randomRelationship.allSatisfy { RelationshipRule.relationship($0, from: cat, to: other) }
            }
            guard let other = options.randomElement(using: &rng) else { return nil }
            cats["r_c"] = other.id
            if randomDies { deaths.append(other.id) }
        }
        if cat.id == clan.leader, tags.contains("all_lives"), cat.moons < 150, Int.random(in: 0..<5, using: &rng) != 0 {
            return nil
        }
        let lives: StoryPick.LivesLost = tags.contains("all_lives") ? .all : tags.contains("some_lives") ? .some : .one
        return StoryPick(template: text, cats: cats, deaths: deaths, livesLost: lives)
    }
}

/// An `involved_cats`, `m_c` or `r_c` constraint block, limited to keys KittyClan can evaluate.
private struct Constraint: Sendable {
    var ages: [String]?
    var statuses: [String]?
    var traits: [String]?
    var genders: [String]?
    var skillsPass = true
    var hasMentor: Bool?
    var hasCurrentApprentice: Bool?
    var hasFormerApprentice: Bool?

    init?(_ json: [String: Any]) {
        for (key, value) in json {
            switch key {
            case "age": ages = value as? [String]
            case "status":
                let list = value as? [String] ?? []
                if !list.contains("clancat"), !list.contains("any") { statuses = list }
            case "trait": traits = value as? [String]
            case "gender": genders = value as? [String]
            case "skill":
                // KittyClan cats have no skills yet, so only exclusions ("-FIGHTER,2") can pass.
                skillsPass = (value as? [String] ?? []).allSatisfy { $0.hasPrefix("-") }
            case "group":
                guard (value as? [String])?.allSatisfy({ $0 == "player_clan" }) == true else { return nil }
            case "has_mentor": hasMentor = value as? Bool
            case "has_apprentice":
                guard let spec = value as? [String: Any], Set(spec.keys).isSubset(of: ["current", "former"]) else { return nil }
                hasCurrentApprentice = spec["current"] as? Bool
                hasFormerApprentice = spec["former"] as? Bool
            case "stat":
                guard let spec = value as? [String: Any], Set(spec.keys) == ["trait"] else { return nil }
                traits = spec["trait"] as? [String]
            case "dies", "relationship_status":
                continue
            default:
                return nil
            }
        }
    }

    func matches(_ cat: Cat, allowNewborn: Bool = true) -> Bool {
        if !allowNewborn, cat.rank == .newborn, ages?.contains("newborn") != true { return false }
        return skillsPass
            && Self.listAllows(ages, cat.age.rawValue)
            && Self.listAllows(statuses, cat.rank.rawValue)
            && Self.listAllows(traits, cat.personality.trait)
            && Self.listAllows(genders, cat.sex.rawValue)
            && hasMentor.map { $0 == (cat.mentor != nil) } ?? true
            && hasCurrentApprentice.map { $0 == !cat.apprentices.isEmpty } ?? true
            && hasFormerApprentice.map { $0 == !cat.formerApprentices.isEmpty } ?? true
    }

    /// A Clangen filter list: "any", a match, or an exclusion list when any entry starts with "-".
    static func listAllows(_ list: [String]?, _ value: String, normalize: (String) -> String = { $0 }) -> Bool {
        guard let list, !list.isEmpty, !list.contains("any") else { return true }
        if list.contains(where: { $0.hasPrefix("-") }) {
            return !list.map { normalize(String($0.drop { $0 == "-" })) }.contains(value)
        }
        return list.map(normalize).contains(value)
    }

    private static let flagTags: Set<String> = [
        "classic", "no_body", "all_lives", "some_lives", "lives_remain", "high_lives", "mid_lives", "low_lives",
    ]
    private static let blockedTokens = [
        "o_c_n", "POI", "mur_c", "acc_", "_list", "multi_cat", "given_herb", "n_c", "r_c0", "r_c1", "r_c2", "r_c3",
        "p_l", "s_c", "cat_tag", "past_deputy", "mc_mate", "rc_mate", "%{",
    ]
    nonisolated(unsafe) private static let preyToken = try! Regex(#"[bdfmpw]_(tp|mp|bp)"#)

    static func isSupportedTag(_ tag: String) -> Bool {
        tag.hasPrefix("clan:") || tag.hasPrefix("-clan:") || flagTags.contains(tag)
    }

    static func textIsSupported(_ text: String, allowing abbreviations: Set<String>) -> Bool {
        for token in blockedTokens where text.contains(token) && !abbreviations.contains(token) {
            return false
        }
        return !text.contains(preyToken)
    }

    /// Text naming the leader, deputy or medicine cat needs that cat to exist.
    static func namedRolesExist(in text: String, clan: Clan) -> Bool {
        if text.contains("lead_name"), !clan.isAlive(clan.leader) { return false }
        if text.contains("dep_name"), !clan.isAlive(clan.deputy) { return false }
        if text.contains("med_name"), !clan.living.contains(where: { $0.rank == .medicineCat }) { return false }
        return true
    }

    /// Clangen's `clan:<rank>[(min:N)]` tags and leader-lives tags.
    static func tagsAllow(_ tags: [String], in clan: Clan, cat: Cat) -> Bool {
        let isLeader = cat.id == clan.leader
        let lives = clan.leaderLives
        for tag in tags {
            if tag.hasPrefix("clan:") || tag.hasPrefix("-clan:") {
                let negated = tag.hasPrefix("-")
                var body = String(tag.drop { $0 == "-" }.dropFirst("clan:".count))
                var minimum: Int?
                if let open = body.firstIndex(of: "("), let colon = body.firstIndex(of: ":"), let close = body.firstIndex(of: ")") {
                    minimum = Int(body[body.index(after: colon)..<close])
                    body = String(body[..<open])
                }
                let count: Int
                switch body {
                case "apps": count = clan.living.filter { $0.rank.isApprentice }.count
                case "warrior-like": count = clan.living.filter { [.warrior, .deputy, .leader].contains($0.rank) }.count
                default:
                    guard let rank = Rank(rawValue: body) else { return false }
                    count = clan.living.filter { $0.rank == rank }.count
                }
                let needed = minimum ?? (["leader", "deputy"].contains(body) ? 1 : 2)
                if (count >= needed) == negated { return false }
                continue
            }
            switch tag {
            case "some_lives": if isLeader, !(4...9).contains(lives) { return false }
            case "lives_remain": if !isLeader || !(2...9).contains(lives) { return false }
            case "high_lives": if !isLeader || !(7...9).contains(lives) { return false }
            case "mid_lives": if !isLeader || !(4...6).contains(lives) { return false }
            case "low_lives": if !isLeader || !(1...3).contains(lives) { return false }
            default: break
            }
        }
        return true
    }
}

/// A ceremony `relationship_constraint` between involved cats.
private struct RelationshipRule: Sendable {
    let from: [String]
    let to: [String]
    let constraints: [String]

    init?(_ json: [String: Any]) {
        from = json["cats_from"] as? [String] ?? []
        to = json["cats_to"] as? [String] ?? []
        constraints = json["constraints"] as? [String] ?? []
        guard constraints.allSatisfy(Self.isSupported) else { return nil }
    }

    static func isSupported(_ name: String) -> Bool {
        ["mates", "app/mentor", "mentor/app", "past_app/mentor", "past_mentor/app", "child/parent", "parent/child", "siblings", "littermates"]
            .contains(name)
    }

    static func relationship(_ name: String, from a: Cat, to b: Cat) -> Bool {
        switch name {
        case "mates": a.mates.contains(b.id)
        case "app/mentor": a.mentor == b.id
        case "mentor/app": b.mentor == a.id
        case "past_app/mentor": a.formerMentors.contains(b.id)
        case "past_mentor/app": b.formerMentors.contains(a.id)
        case "child/parent": a.parents.contains(b.id)
        case "parent/child": b.parents.contains(a.id)
        case "siblings": !Set(a.parents).isDisjoint(with: b.parents)
        case "littermates": !Set(a.parents).isDisjoint(with: b.parents) && a.moons == b.moons
        default: false
        }
    }

    func holds(_ cats: [String: UUID], _ clan: Clan, partial: Bool) -> Bool {
        for f in from {
            for t in to {
                guard let a = cats[f].flatMap({ clan[$0] }), let b = cats[t].flatMap({ clan[$0] }) else {
                    if partial { continue }
                    return false
                }
                if !constraints.allSatisfy({ Self.relationship($0, from: a, to: b) }) { return false }
            }
        }
        return true
    }
}
