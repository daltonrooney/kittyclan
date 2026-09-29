import Foundation

/// An `involved_cats`, `m_c` or `r_c` constraint block, limited to keys KittyClan can evaluate.
struct Constraint: Sendable {
    var ages: [String]?
    var statuses: [String]?
    var traits: [String]?
    var genders: [String]?
    var skills: [String]?
    /// A `stat` block: the cat needs one of the skills or traits (or both, when required).
    var statSkills: [String]?
    var statTraits: [String]?
    var statNeedsBoth = false
    var hasMentor: Bool?
    var hasCurrentApprentice: Bool?
    var hasFormerApprentice: Bool?
    /// Clangen's `past_status`: ranks the cat held before its current one.
    var pastStatuses: [String]?
    /// Clangen's `current_exp`: experience levels such as "prepared".
    var experienceLevels: [String]?
    /// Legacy short-event `relationship_status` tokens, checked by the caller against the other cat.
    var relationshipStatus: [String] = []

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
                skills = value as? [String]
            case "group":
                guard (value as? [String])?.allSatisfy({ $0 == "player_clan" }) == true else { return nil }
            case "has_mentor": hasMentor = value as? Bool
            case "has_apprentice":
                guard let spec = value as? [String: Any], Set(spec.keys).isSubset(of: ["current", "former"]) else { return nil }
                hasCurrentApprentice = spec["current"] as? Bool
                hasFormerApprentice = spec["former"] as? Bool
            case "stat":
                guard let spec = value as? [String: Any], Set(spec.keys).isSubset(of: ["skill", "trait", "must_have_both"]) else { return nil }
                statSkills = spec["skill"] as? [String]
                statTraits = spec["trait"] as? [String]
                statNeedsBoth = spec["must_have_both"] as? Bool ?? false
            case "relationship_status":
                relationshipStatus = value as? [String] ?? []
                guard relationshipStatus.allSatisfy(RelationshipRule.isSupported) else { return nil }
            case "past_status": pastStatuses = value as? [String]
            case "current_exp": experienceLevels = value as? [String]
            case "dies":
                continue
            default:
                return nil
            }
        }
    }

    /// - Parameter status: the status to match instead of the rank, e.g. an outsider's "loner".
    func matches(_ cat: Cat, status: String? = nil, allowNewborn: Bool = true) -> Bool {
        if !allowNewborn, cat.rank == .newborn, ages?.contains("newborn") != true { return false }
        return cat.skills.satisfies(skills ?? [])
            && statHolds(for: cat)
            && Self.listAllows(ages, cat.age.rawValue)
            && Self.listAllows(statuses, status ?? cat.rank.rawValue)
            && Self.listAllows(traits, cat.personality.trait)
            && Self.listAllows(genders, cat.sex.rawValue)
            && hasMentor.map { $0 == (cat.mentor != nil) } ?? true
            && hasCurrentApprentice.map { $0 == !cat.apprentices.isEmpty } ?? true
            && hasFormerApprentice.map { $0 == !cat.formerApprentices.isEmpty } ?? true
            && Self.listAllows(experienceLevels, PatrolSlot.experienceLevel(cat.experience))
            && pastStatusHolds(for: cat)
    }

    /// Clangen's `_check_cat_status_history`: any rank held before other than the current one.
    private func pastStatusHolds(for cat: Cat) -> Bool {
        guard let pastStatuses, !pastStatuses.isEmpty, !pastStatuses.contains("any") else { return true }
        let past = Set(cat.pastRanks.filter { $0 != cat.rank }.map(\.rawValue))
        if pastStatuses.contains(where: { $0.hasPrefix("-") }) {
            return past.isDisjoint(with: pastStatuses.map { String($0.drop { $0 == "-" }) })
        }
        return !past.isDisjoint(with: pastStatuses)
    }

    /// Clangen's `_check_cat_stat`.
    func statHolds(for cat: Cat) -> Bool {
        guard statSkills != nil || statTraits != nil else { return true }
        let hasSkill = !(statSkills ?? []).isEmpty && cat.skills.satisfies(statSkills!)
        let hasTrait = !(statTraits ?? []).isEmpty && Self.listAllows(statTraits, cat.personality.trait)
        return statNeedsBoth ? hasSkill && hasTrait : hasSkill || hasTrait
    }

    /// Clangen's legacy `relationship_status` check from this cat towards another.
    /// Tier words pass when no relationship exists yet.
    func relationshipHolds(from a: Cat, to b: Cat, in clan: Clan) -> Bool {
        relationshipStatus.allSatisfy { token in
            let negated = token.hasPrefix("-")
            let name = negated ? String(token.dropFirst()) : token
            let result: Bool
            if Relationship.isTierToken(name) {
                result = clan.relationship(from: a.id, to: b.id)?.satisfies(tier: name) ?? true
            } else {
                result = RelationshipRule.kinship(name, from: a, to: b, in: clan)
            }
            return result != negated
        }
    }

    /// A Clangen filter list: "any", a match, or an exclusion list when any entry starts with "-".
    static func listAllows(_ list: [String]?, _ value: String, normalize: (String) -> String = { $0 }) -> Bool {
        guard let list, !list.isEmpty, !list.contains("any") else { return true }
        if list.contains(where: { $0.hasPrefix("-") }) {
            return !list.map { normalize(String($0.drop { $0 == "-" })) }.contains(value)
        }
        return list.map(normalize).contains(value)
    }

    /// Clangen's `event_for_location`: "biome" or "biome:campA_campB" entries. Any "-" entry makes
    /// every entry an exclusion, as in Clangen, so ["forest", "-plains:camp3"] excludes forest too.
    static func locationAllows(_ list: [String]?, biome: Biome, camp: Int) -> Bool {
        guard let list, !list.isEmpty, !list.contains("any") else { return true }
        let exclusionary = list.contains { $0.hasPrefix("-") }
        for entry in list {
            let place = exclusionary ? entry.replacingOccurrences(of: "-", with: "") : entry
            let parts = place.split(separator: ":", maxSplits: 1).map(String.init)
            let camps = parts.count > 1 ? parts[1].split(separator: "_").map(String.init) : ["any"]
            if parts[0] == biome.key, camps.contains("any") || camps.contains("camp\(camp)") { return !exclusionary }
        }
        return exclusionary
    }

    private static let flagTags: Set<String> = [
        "classic", "no_body", "all_lives", "some_lives", "lives_remain", "high_lives", "mid_lives", "low_lives", "romance",
        "clan_wide",
        "adoption",
    ]
    private static let blockedTokens = [
        "POI", "mur_c", "acc_", "_list", "multi_cat", "given_herb", "n_c", "r_c0", "r_c1", "r_c2", "r_c3",
        "p_l", "s_c", "cat_tag", "past_deputy", "mc_mate", "rc_mate", "%{", "app1", "app2", "patrol_cats",
    ]
    nonisolated(unsafe) private static let preyToken = try! Regex(#"[bdfmpw]_(tp|mp|bp)"#)

    static func isSupportedTag(_ tag: String) -> Bool {
        tag.hasPrefix("clan:") || tag.hasPrefix("-clan:") || flagTags.contains(tag)
    }

    static func textIsSupported(_ text: String, allowing abbreviations: Set<String>, allowPrey: Bool = false) -> Bool {
        for token in blockedTokens where text.contains(token) && !abbreviations.contains(where: { $0.contains(token) }) {
            return false
        }
        return allowPrey || !text.contains(preyToken)
    }

    /// Text naming the leader, deputy or medicine cat needs that cat to exist.
    static func namedRolesExist(in text: String, clan: Clan) -> Bool {
        if text.contains("lead_name"), !clan.isAlive(clan.leader) { return false }
        if text.contains("dep_name"), !clan.isAlive(clan.deputy) { return false }
        if text.contains("med_name"), !clan.living.contains(where: { $0.rank == .medicineCat }) { return false }
        return true
    }

    /// Clangen's `clan:<rank>[(min:N)]` tags, leader-lives tags and the `adoption` tag.
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
            case "adoption": if cat.moons <= 14 + 5 { return false }
            default: break
            }
        }
        return true
    }
}

/// A `relationship_constraint` block (Clangen's newer format) between involved cats.
struct RelationshipRule: Sendable {
    let from: [String]
    let to: [String]
    let mutual: Bool
    let constraints: [String]

    private static let kinshipTokens: Set<String> = [
        "can_romance", "strangers", "siblings", "littermates", "mates", "parent/child", "child/parent",
        "mentor/app", "app/mentor", "past_mentor/app", "past_app/mentor",
    ]

    init?(_ json: [String: Any]) {
        from = json["cats_from"] as? [String] ?? []
        to = json["cats_to"] as? [String] ?? []
        mutual = json["mutual"] as? Bool ?? false
        constraints = json["constraints"] as? [String] ?? []
        guard constraints.allSatisfy(Self.isSupported) else { return nil }
    }

    static func isSupported(_ token: String) -> Bool {
        let name = token.hasPrefix("-") ? String(token.dropFirst()) : token
        return kinshipTokens.contains(name) || Relationship.isTierToken(name)
    }

    static func kinship(_ name: String, from a: Cat, to b: Cat, in clan: Clan) -> Bool {
        switch name {
        case "mates": a.mates.contains(b.id)
        case "app/mentor": a.mentor == b.id
        case "mentor/app": b.mentor == a.id
        case "past_app/mentor": a.formerMentors.contains(b.id)
        case "past_mentor/app": b.formerMentors.contains(a.id)
        case "child/parent": a.allParents.contains(b.id)
        case "parent/child": b.allParents.contains(a.id)
        case "siblings": !Set(a.allParents).isDisjoint(with: b.allParents)
        case "littermates": !a.parents.isEmpty && Set(a.parents) == Set(b.parents) && a.moons + a.deadFor == b.moons + b.deadFor
        case "strangers": clan.relationship(from: a.id, to: b.id) == nil
        case "can_romance": clan.isPotentialMate(a, b, forLoveInterest: true)
        default: false
        }
    }

    /// Checks the rule for resolved cats. Abbreviations that aren't filled yet pass when `partial`.
    func holds(_ cats: [String: [UUID]], _ clan: Clan, partial: Bool) -> Bool {
        holds(from: from, to: to, cats, clan, partial: partial)
            && (!mutual || holds(from: to, to: from, cats, clan, partial: partial))
    }

    private func holds(from: [String], to: [String], _ cats: [String: [UUID]], _ clan: Clan, partial: Bool) -> Bool {
        let fromCats = from.flatMap { cats[$0] ?? [] }.compactMap { clan[$0] }
        let toCats = to.flatMap { cats[$0] ?? [] }.compactMap { clan[$0] }
        let missing = from.contains { cats[$0] == nil } || to.contains { cats[$0] == nil }
        if missing { return partial }
        guard !fromCats.isEmpty, !toCats.isEmpty else { return true }

        for a in fromCats {
            let others = toCats.filter { $0.id != a.id }
            for token in constraints {
                let negated = token.hasPrefix("-")
                let name = negated ? String(token.dropFirst()) : token
                if Relationship.isTierToken(name) {
                    for b in others {
                        guard let rel = clan.relationship(from: a.id, to: b.id), rel.satisfies(tier: name) else { return false }
                    }
                } else {
                    let all = others.allSatisfy { Self.kinship(name, from: a, to: $0, in: clan) }
                    if all == negated { return false }
                }
            }
        }
        return true
    }
}

extension Clan {
    /// Clangen's `is_potential_mate`.
    func isPotentialMate(_ a: Cat, _ b: Cat, forLoveInterest: Bool = false) -> Bool {
        guard a.id != b.id, a.isAlive == b.isAlive, !areRelated(a.id, b.id) else { return false }
        if !forLoveInterest, a.moons < 14 || b.moons < 14 { return false }
        if a.age != b.age, abs(a.moons - b.moons) > 41 { return false }
        if (!a.isMateAge || !b.isMateAge), a.age != b.age { return false }
        if a.mentor == b.id || b.mentor == a.id { return false }
        return true
    }
}
