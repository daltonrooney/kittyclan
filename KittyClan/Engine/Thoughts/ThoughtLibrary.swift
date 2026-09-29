import Foundation

/// What a thought needs to know about the Clan: who is an outsider and which group each cat is in.
struct ThoughtContext {
    let clan: Clan
    /// Loners, rogues, kittypets and lost or exiled cats; not members of other Clans.
    let outsiderIDs: Set<UUID>
    /// Living members of neighbouring Clans.
    let otherClanIDs: Set<UUID>

    init(clan: Clan) {
        self.clan = clan
        otherClanIDs = Set(clan.outsiders.filter { $0.isAlive && $0.belongsToOtherClan }.map(\.id))
        outsiderIDs = Set(clan.outsiders.map(\.id)).subtracting(otherClanIDs)
    }

    /// Clangen's `status.rank`: an outsider's is its way of life; another Clan's cat keeps its rank.
    func status(of cat: Cat) -> String {
        outsiderIDs.contains(cat.id) && !cat.belongsToOtherClan ? cat.social.rawValue : cat.rank.rawValue
    }

    /// Clangen's group: an afterlife for the dead, the player Clan, another Clan, or none for outsiders.
    func group(of cat: Cat) -> String {
        if let afterlife = cat.afterlife, cat.isDead { return afterlife.rawValue }
        if otherClanIDs.contains(cat.id) { return "other_clan" }
        return outsiderIDs.contains(cat.id) ? "no_group" : "player_clan"
    }

    func file(of cat: Cat) -> String {
        status(of: cat).replacingOccurrences(of: " ", with: "_")
    }
}

/// A thought's `m_c` or `r_c` block: what `Constraint` handles, plus the keys only thoughts use.
struct ThoughtCatFilter: Sendable {
    let base: Constraint
    let groups: [String]?
    let conditions: [String]?
    let mustBeCongenital: Bool
    let formerClanCat: Bool?
    let currentlyExiled: Bool
    let weight: Int

    init?(_ json: [String: Any]) {
        var rest = json
        var weight = 0
        func listWeight(_ list: [String]?, _ total: Int) -> Int {
            guard let list, !list.isEmpty, !list.contains("any") else { return 0 }
            return list.contains { $0.hasPrefix("-") } ? max(total - list.count, 0) : list.count
        }

        groups = rest.removeValue(forKey: "group") as? [String]
        weight += listWeight(groups, 6)

        if let health = rest.removeValue(forKey: "health") as? [String: Any] {
            guard Set(health.keys).isSubset(of: ["condition", "must_be_congenital"]) else { return nil }
            conditions = health["condition"] as? [String]
            mustBeCongenital = health["must_be_congenital"] as? Bool ?? false
            weight += (conditions ?? []).count
        } else {
            conditions = nil
            mustBeCongenital = false
        }

        if let past = rest["past_status"] as? [String], past.allSatisfy({ $0 == "clancat" || $0 == "-clancat" }) {
            rest["past_status"] = nil
            formerClanCat = !past.contains("-clancat")
        } else {
            formerClanCat = nil
        }

        if let standing = rest.removeValue(forKey: "standing") as? [String: Any] {
            guard Set(standing.keys).isSubset(of: ["group", "currently"]),
                  (standing["group"] as? [String] ?? ["player_clan"]) == ["player_clan"],
                  standing["currently"] as? [String] == ["exiled"]
            else { return nil }
            currentlyExiled = true
            weight += 20
        } else {
            currentlyExiled = false
        }

        guard let base = Constraint(rest) else { return nil }
        self.base = base
        weight += listWeight(base.statuses, 14) + listWeight(base.ages, 7)
        weight += listWeight(base.statSkills, 24) + listWeight(base.statTraits, 38)
        if base.hasMentor != nil { weight += 10 }
        self.weight = weight
    }

    func matches(_ cat: Cat, main: Cat?, in context: ThoughtContext) -> Bool {
        guard base.matches(cat, status: context.status(of: cat)) else { return false }
        if let groups, !groupAllows(groups, cat, main: main, context) { return false }
        if let conditions, !conditions.contains("any") {
            let names = Set(cat.conditions.filter { !mustBeCongenital || $0.bornWith }.map(\.name))
            if conditions.contains(where: { $0.hasPrefix("-") }) {
                if !names.isDisjoint(with: conditions.map { String($0.dropFirst()) }) { return false }
            } else if names.isDisjoint(with: conditions) {
                return false
            }
        }
        if let formerClanCat, (cat.isFormerClanCat || context.outsiderIDs.contains(cat.id) && cat.leftOtherClan) != formerClanCat { return false }
        if currentlyExiled, !(context.outsiderIDs.contains(cat.id) && cat.isExiled) { return false }
        return true
    }

    /// Clangen's `_get_cats_from_group`: one "-" entry makes the whole list exclusions.
    private func groupAllows(_ groups: [String], _ cat: Cat, main: Cat?, _ context: ThoughtContext) -> Bool {
        let group = context.group(of: cat)
        func hits(_ value: String) -> Bool {
            switch value {
            case "afterlife": Afterlife(rawValue: group) != nil
            case "match:m_c": main.map { context.group(of: $0) == group } ?? false
            default: value == group
            }
        }
        if groups.contains(where: { $0.hasPrefix("-") }) {
            return !groups.contains { hits(String($0.drop { $0 == "-" })) }
        }
        return groups.contains(where: hits)
    }
}

/// One of Clangen's thought blocks.
struct ThoughtBlock: Sendable {
    let id: String
    let strings: [String]
    let main: ThoughtCatFilter?
    /// Non-nil whenever the thought mentions `r_c`, which then has to exist.
    let random: ThoughtCatFilter?
    let relationships: [RelationshipRule]
    let seasons: [String]
    let tags: [String]
    let location: [String]?
    let weight: Int

    init?(_ json: [String: Any]) {
        guard Set(json.keys).isSubset(of: ["event_id", "strings", "involved_cats", "relationship_constraint", "season", "location", "tags"]),
              let id = json["event_id"] as? String
        else { return nil }
        let strings = (json["strings"] as? [String] ?? []).filter {
            Constraint.textIsSupported($0, allowing: ["m_c", "r_c"])
        }
        guard !strings.isEmpty else { return nil }
        let involved = json["involved_cats"] as? [String: [String: Any]] ?? [:]
        guard Set(involved.keys).isSubset(of: ["m_c", "r_c"]) else { return nil }
        var main: ThoughtCatFilter?
        if let spec = involved["m_c"] {
            guard let filter = ThoughtCatFilter(spec) else { return nil }
            main = filter
        }
        var random: ThoughtCatFilter?
        if let spec = involved["r_c"] ?? (strings.contains { $0.contains("r_c") } ? [:] : nil) {
            guard let filter = ThoughtCatFilter(spec) else { return nil }
            random = filter
        }
        let ruleJSON = json["relationship_constraint"] as? [[String: Any]] ?? []
        let rules = ruleJSON.compactMap(RelationshipRule.init)
        guard rules.count == ruleJSON.count else { return nil }
        let tags = json["tags"] as? [String] ?? []
        guard tags.allSatisfy(Constraint.isSupportedTag) else { return nil }

        self.id = id
        location = json["location"] as? [String]
        self.strings = strings
        self.main = main
        self.random = random
        relationships = rules
        seasons = json["season"] as? [String] ?? []
        self.tags = tags
        var weight = 1 + 2 * tags.count + (rules.isEmpty ? 0 : 20)
        if !seasons.isEmpty { weight += 4 * max(0, 4 - seasons.count) }
        weight += (main?.weight ?? 0) + (random?.weight ?? 0)
        self.weight = weight
    }

    func fits(_ cat: Cat, about other: Cat?, in context: ThoughtContext) -> Bool {
        let clan = context.clan
        if !Constraint.locationAllows(location, biome: clan.biome, camp: clan.camp) { return false }
        if !seasons.isEmpty, !Constraint.listAllows(seasons.map { $0.lowercased() }, clan.season.rawValue.lowercased()) { return false }
        if !Constraint.tagsAllow(tags, in: clan, cat: cat) { return false }
        if let main, !main.matches(cat, main: nil, in: context) { return false }
        if let random {
            guard let other, random.matches(other, main: cat, in: context) else { return false }
        }
        var cats = ["m_c": [cat.id]]
        if let other { cats["r_c"] = [other.id] }
        return relationships.allSatisfy { $0.holds(cats, clan, partial: other == nil && random == nil) }
    }
}

/// Clangen's thought pools (`resources/lang/en/thoughts`).
struct ThoughtLibrary: Sendable {
    /// Keyed by path without ".json", e.g. "while_alive/warrior" or "while_dead/starclan/general".
    private let files: [String: [ThoughtBlock]]
    private let snippets: SnippetCollections?

    init(directory: URL) throws {
        let root = directory.appending(path: "thoughts")
        var files: [String: [ThoughtBlock]] = [:]
        let paths = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for url in paths where url.pathExtension == "json" {
            let key = url.path.replacingOccurrences(of: root.path + "/", with: "").replacingOccurrences(of: ".json", with: "")
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] ?? []
            files[key] = json.compactMap(ThoughtBlock.init)
        }
        self.files = files
        snippets = try? SnippetCollections(url: directory.appending(path: "snippet_collections.json"))
    }

    var blockCount: Int { files.values.reduce(0) { $0 + $1.count } }
    var stringCount: Int { files.values.joined().reduce(0) { $0 + $1.strings.count } }

    /// Clangen's `_load_allowed_thoughts`.
    func pool(_ kind: ThoughtKind, for cat: Cat, in context: ThoughtContext) -> [ThoughtBlock] {
        let clan = context.clan
        let isOutsider = context.outsiderIDs.contains(cat.id)
        let file = context.file(of: cat)
        var keys: [String]
        switch kind {
        case .isGuide:
            keys = ["is_guide/\(cat.afterlife?.rawValue ?? "starclan")"]
        case .whileDead:
            let afterlife = cat.afterlife?.rawValue ?? "starclan"
            keys = ["while_dead/\(afterlife)/\(file)"]
            if cat.isExiled { keys.append("while_dead/\(afterlife)/exiled") }
            if isOutsider, cat.isFormerClanCat { keys.append("while_dead/\(afterlife)/former_clancat") }
            if cat.rank != .newborn { keys.append("while_dead/\(afterlife)/general") }
        case .whileAlive:
            if cat.rank == .newborn {
                keys = ["while_alive/newborn"]
            } else if isOutsider, cat.isLost {
                keys = ["while_alive/\(file)", "while_alive/while_lost/general"]
                if let rank = cat.lastClanRank { keys.append("while_alive/while_lost/" + rank.rawValue.replacingOccurrences(of: " ", with: "_")) }
            } else if isOutsider {
                keys = ["while_alive/\(file)", "while_alive/general"]
                if cat.isExiled { keys.append("while_alive/exiled") }
                if cat.isFormerClanCat || cat.leftOtherClan { keys.append("while_alive/former_clancat") }
            } else {
                keys = ["while_alive/\(file)", "while_alive/general", "while_alive/clancat"]
            }
        case .onRankChange:
            keys = ["on_rank_change/\(file)", "on_rank_change/general"]
        case .onDeath:
            if cat.isAlive {
                keys = ["on_death/\(clan.guideAfterlife.rawValue)/leader_life"]
            } else {
                let afterlife = cat.afterlife?.rawValue ?? "starclan"
                keys = ["on_death/\(afterlife)/" + (cat.rank == .leader && !isOutsider ? "leader_death" : "general")]
            }
        case .onMeeting:
            keys = ["on_meeting/" + (isOutsider ? "outsider" : "clancat")]
        case .onBirth:
            keys = ["on_birth/parent"]
        case .onAfterlifeChange:
            keys = ["on_afterlife_change/\(cat.afterlife?.rawValue ?? "starclan")"]
        case .onJoin, .onExile, .onLost, .onGriefTowardBody, .onGriefNoBody:
            keys = ["\(kind.rawValue)/general"]
        }
        return keys.flatMap { files[$0] ?? [] }
    }

    /// Clangen's `_get_other_cat_for_thought`: the dead may think of anyone; the living think of
    /// someone in their own group they have feelings about.
    static func randomCat(for cat: Cat, in context: ThoughtContext, using rng: inout some RandomNumberGenerator) -> Cat? {
        let clan = context.clan
        let others = (clan.cats + clan.outsiders).filter { $0.id != cat.id }
        if cat.isDead { return others.randomElement(using: &rng) }
        let group = context.group(of: cat)
        return others.filter { other in
            guard other.isAlive, !other.isLost, context.group(of: other) == group,
                  let relationship = clan.relationship(from: cat.id, to: other.id)
            else { return false }
            return relationship.romance + relationship.like + relationship.respect + relationship.comfort + relationship.trust != 0
        }
        .randomElement(using: &rng)
    }

    /// Clangen's `get_new_thought`: r_c is chosen first, then a fitting block by weight, then a line.
    /// Returns nil when nothing fits.
    func thought(
        _ kind: ThoughtKind, for cat: Cat, about other: Cat? = nil, in context: ThoughtContext,
        used: inout Set<String>, using rng: inout some RandomNumberGenerator
    ) -> Thought? {
        let other = other ?? Self.randomCat(for: cat, in: context, using: &rng)
        let fitting = pool(kind, for: cat, in: context).filter { $0.fits(cat, about: other, in: context) }
        let fresh = fitting.filter { !used.contains($0.id) }
        let options = fresh.isEmpty ? fitting : fresh
        guard !options.isEmpty else { return nil }
        let block = options[weighted(Array(zip(options.indices, options.map(\.weight))), &rng)]
        used.insert(block.id)
        guard var line = block.strings.randomElement(using: &rng) else { return nil }
        line = snippets?.expand(line, biome: context.clan.biome, using: &rng) ?? line
        return Thought(text: line, about: block.random != nil || line.contains("r_c") ? other?.id : nil)
    }
}
