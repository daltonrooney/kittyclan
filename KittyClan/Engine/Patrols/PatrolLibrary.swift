import Foundation

enum PatrolType: String, CaseIterable, Codable, Sendable {
    case hunting, border, training
    case herbGathering = "herb_gathering"

    var folder: String { self == .herbGathering ? "med" : rawValue }
}

/// An `involved_cats` slot in a patrol or outcome (`p_l`, `r_c0`, `s_c0`, `n_c0`…).
struct PatrolSlot: Sendable {
    let abbr: String
    let constraint: Constraint
    /// Which already-involved cats a stat cat may be drawn from, e.g. `["any"]` or `["-p_l"]`.
    let prior: [String]?
    let statSkills: [String]?
    let traits: [String]?
    let working: Bool?
    let experienceLevels: [String]?
    let conditions: [String]?
    let outsiderStatuses: [String]
    /// Clangen's "clancat" status: a cat of the neighbouring Clan the patrol meets.
    let wantsOtherClanCat: Bool
    /// Clangen's `past_status: ["clancat"]`: a cat who once lived in a Clan (or never did, when false).
    let wasClanCat: Bool?
    /// Set when the slot can be filled by creating a new cat.
    let create: Creation?

    struct Creation: Sendable {
        let litter: Bool
        let ages: [String]
        let genders: [String]
        let status: String?
        let skills: [String]
        /// Backstory keys to choose from, categories expanded.
        let backstories: [String]
        /// Involved cats who become the new cat's mates, blood parents and adoptive parents.
        let mates: [String]
        let bloodParents: [String]
        let adoptiveParents: [String]
    }

    /// Clangen's stat-cat bonus: 5 per tier of the matching skill, or 10 for a matching trait.
    func successBonus(for cat: Cat) -> Int {
        if let statSkills { return 5 * cat.skills.requirementTier(statSkills) }
        return traits == nil ? 0 : 10
    }

    private static let outsiderRanks: Set<String> = ["loner", "rogue", "kittypet"]

    init?(abbr: String, _ json: [String: Any]) {
        self.abbr = abbr
        var rest = json
        prior = rest.removeValue(forKey: "prior_abbreviation") as? [String]

        let stat = rest["stat"] as? [String: Any]
        statSkills = stat?["skill"] as? [String]
        traits = stat?["trait"] as? [String]

        if let health = rest.removeValue(forKey: "health") as? [String: Any] {
            guard Set(health.keys).isSubset(of: ["working", "condition"]) else { return nil }
            working = health["working"] as? Bool
            conditions = health["condition"] as? [String]
        } else {
            working = nil
            conditions = nil
        }
        experienceLevels = rest.removeValue(forKey: "current_exp") as? [String]

        let statuses = rest["status"] as? [String] ?? []
        outsiderStatuses = statuses.filter(Self.outsiderRanks.contains)
        wantsOtherClanCat = statuses.contains("clancat")
        if statuses.contains("lost") || statuses.contains("guide") { return nil }
        if !outsiderStatuses.isEmpty { rest["status"] = nil }
        if let past = rest["past_status"] as? [String], past.allSatisfy({ $0 == "clancat" || $0 == "-clancat" }) {
            rest["past_status"] = nil
            wasClanCat = !past.contains("-clancat")
        } else {
            wasClanCat = nil
        }

        if let spec = rest.removeValue(forKey: "can_create_new_cat") as? [String: Any] {
            guard Set(spec.keys).isSubset(of: ["become_litter", "assign_mate", "assign_blood_parent", "assign_adoptive_parent"]) else { return nil }
            var backstories: [String] = []
            if let list = rest["backstory"] as? [String], !list.contains(where: { $0.hasPrefix("-") }) {
                guard let expanded = Backstories.bundled.expand(list) else { return nil }
                backstories = expanded.sorted()
            }
            create = Creation(
                litter: spec["become_litter"] as? Bool ?? false,
                ages: rest["age"] as? [String] ?? [],
                genders: rest["gender"] as? [String] ?? [],
                status: wantsOtherClanCat ? "clancat" : outsiderStatuses.randomElement() ?? statuses.first,
                skills: (stat?["skill"] as? [String] ?? []).filter { !$0.hasPrefix("-") },
                backstories: backstories,
                mates: spec["assign_mate"] as? [String] ?? [],
                bloodParents: spec["assign_blood_parent"] as? [String] ?? [],
                adoptiveParents: spec["assign_adoptive_parent"] as? [String] ?? []
            )
        } else {
            create = nil
        }
        guard let constraint = Constraint(rest) else { return nil }
        self.constraint = constraint
    }

    /// - Parameter otherClan: the neighbouring Clan the patrol may meet.
    func matches(_ cat: Cat, isOutsider: Bool, otherClan: UUID? = nil) -> Bool {
        if !outsiderStatuses.isEmpty {
            guard isOutsider, !cat.belongsToOtherClan, outsiderStatuses.contains(cat.origin.rawValue) else { return false }
        }
        if wantsOtherClanCat {
            guard isOutsider, cat.belongsToOtherClan, otherClan == nil || cat.otherClan == otherClan else { return false }
        }
        if let wasClanCat, (cat.isFormerClanCat || cat.leftOtherClan) != wasClanCat { return false }
        if let working, working == cat.isNotWorking { return false }
        if let levels = experienceLevels, !levels.contains(Self.experienceLevel(cat.experience)) { return false }
        if let conditions {
            let names = cat.conditions.map(\.name)
            if conditions.contains("any") { if names.isEmpty { return false } }
            else if conditions.contains(where: { $0.hasPrefix("-") }) {
                if names.contains(where: { conditions.contains("-" + $0) }) { return false }
            } else if !names.contains(where: conditions.contains) { return false }
        }
        return constraint.matches(cat, allowNewborn: false)
    }

    /// Clangen's experience level names.
    static func experienceLevel(_ exp: Int) -> String {
        switch exp {
        case 0: "untrained"
        case 1...50: "learning"
        case 51...110: "prepared"
        case 111...170: "capable"
        case 171...240: "proficient"
        case 241...320: "adept"
        default: "masterful"
        }
    }

    var weight: Int {
        var w = 0
        if let statuses = constraint.statuses { w += statuses.count }
        if let ages = constraint.ages { w += ages.count }
        if let traits { w += traits.count }
        if let statSkills { w += statSkills.first?.hasPrefix("-") == true ? SkillPath.allCases.count - statSkills.count : statSkills.count }
        if constraint.hasMentor != nil { w += 10 }
        return w
    }
}

/// A patrol outcome block: the cats it targets.
struct PatrolTargets: Sendable {
    let cats: [String]
    /// Death or scar history text, where `m_c` is the cat it belongs to.
    let history: String?

    init?(_ json: [String: Any]) {
        guard let cats = json["cats"] as? [String] else { return nil }
        self.cats = cats
        history = json["history"] as? String
    }
}

struct PatrolOutcome: Sendable {
    let strings: [String]
    let frequency: Int
    let expGained: Int
    let slots: [PatrolSlot]
    let requiredCatTypes: [String: [Int]]
    let rules: [RelationshipRule]
    let relationshipChanges: [RelationshipChange]
    let conditions: [(cats: [String], names: [String])]
    let deaths: [PatrolTargets]
    let lost: [PatrolTargets]
    let meet: [PatrolTargets]
    let joins: [(cats: [String], statuses: [String], changeName: Bool)]
    let preySize: String?
    let relationsChange: Int
    let reputationChange: Int
    /// Herb blocks: "random_herbs" or a herb name, with a size such as "medium".
    let herbs: [(type: String, size: String)]
    let tags: [String]
    let season: [String]
    let art: String?
    let poi: PoiRequirement?
    let weight: Int

    private static let keys: Set<String> = [
        "poi", "strings", "frequency", "exp_gained", "relationship_changes", "involved_cats", "supply", "outcome_art",
        "outcome_art_clean", "reputation_changes", "condition", "required_cat_types", "death", "meet", "join",
        "location", "lost", "relationship_constraint", "tags", "season", "patrol_temperament",
    ]

    init?(_ json: [String: Any], patrolSlots: Set<String>) {
        guard Set(json.keys).isSubset(of: Self.keys) else { return nil }

        var slots: [PatrolSlot] = []
        for (abbr, spec) in json["involved_cats"] as? [String: [String: Any]] ?? [:] {
            guard let slot = PatrolSlot(abbr: abbr, spec) else { return nil }
            slots.append(slot)
        }
        self.slots = slots.sorted { $0.abbr < $1.abbr }
        poi = PoiRequirement(json["poi"] as? [String: Any])
        let allowed = patrolSlots.union(slots.map(\.abbr) + (poi == nil ? [] : ["POI"]))
        strings = (json["strings"] as? [String] ?? []).filter { PatrolLibrary.textIsSupported($0, abbreviations: allowed) }
        guard !strings.isEmpty else { return nil }

        frequency = json["frequency"] as? Int ?? 4
        expGained = json["exp_gained"] as? Int ?? 0
        requiredCatTypes = json["required_cat_types"] as? [String: [Int]] ?? [:]
        let ruleJSON = json["relationship_constraint"] as? [[String: Any]] ?? []
        rules = ruleJSON.compactMap(RelationshipRule.init)
        let changeJSON = json["relationship_changes"] as? [[String: Any]] ?? []
        relationshipChanges = changeJSON.compactMap(RelationshipChange.init)
        guard rules.count == ruleJSON.count, changeJSON.count == relationshipChanges.count else { return nil }

        conditions = (json["condition"] as? [[String: Any]] ?? []).compactMap { block in
            guard let cats = block["cats"] as? [String], let names = block["condition"] as? [String] else { return nil }
            return (cats, names)
        }
        deaths = (json["death"] as? [[String: Any]] ?? []).compactMap(PatrolTargets.init)
        lost = (json["lost"] as? [[String: Any]] ?? []).compactMap(PatrolTargets.init)
        meet = (json["meet"] as? [[String: Any]] ?? []).compactMap(PatrolTargets.init)
        joins = (json["join"] as? [[String: Any]] ?? []).compactMap { block in
            guard let cats = block["cats"] as? [String] else { return nil }
            return (cats, block["new_status"] as? [String] ?? [], block["change_name"] as? Bool ?? false)
        }

        let reputation = json["reputation_changes"] as? [String: Any]
        relationsChange = reputation?["other_clan"] as? Int ?? 0
        reputationChange = reputation?["outsider"] as? Int ?? 0

        let supply = json["supply"] as? [[String: Any]] ?? []
        preySize = supply.first { $0["type"] as? String == "freshkill" }
            .flatMap { ($0["adjust"] as? String)?.replacingOccurrences(of: "increase_", with: "") }
        herbs = supply.compactMap { block in
            guard let type = block["type"] as? String, type != "freshkill",
                  let adjust = block["adjust"] as? String, adjust.hasPrefix("increase_")
            else { return nil }
            return (type, String(adjust.dropFirst("increase_".count)))
        }

        tags = json["tags"] as? [String] ?? []
        guard tags.allSatisfy(PatrolLibrary.isSupportedTag) else { return nil }
        season = json["season"] as? [String] ?? []
        art = (json["outcome_art_clean"] ?? json["outcome_art"]) as? String

        var weight = 1
        if !season.isEmpty, !season.contains("any") { weight += 4 * max(0, 4 - season.count) }
        weight += 2 * tags.count + slots.reduce(0) { $0 + $1.weight }
        if !rules.isEmpty { weight += 20 }
        weight += 5 * requiredCatTypes.count + (poi?.weight ?? 0)
        self.weight = max(weight, 1)
    }
}

struct PatrolEvent: Sendable {
    let id: String
    let types: [PatrolType]
    let frequency: Int
    let chanceOfSuccess: Int
    let requiredCatTypes: [String: [Int]]
    let slots: [PatrolSlot]
    let rules: [RelationshipRule]
    let tags: [String]
    let season: [String]
    let art: String?
    let intro: [String]
    let decline: [String]
    let success: [PatrolOutcome]
    let fail: [PatrolOutcome]
    let antagSuccess: [PatrolOutcome]
    let antagFail: [PatrolOutcome]
    let location: [String]
    let poi: PoiRequirement?
    let weight: Int
    /// The prey size most success outcomes bring home, used to balance hunts by season.
    let dominantPrey: String?

    var isRomance: Bool { tags.contains("romance") }
    var givesHerbs: Bool { (success + fail).contains { !$0.herbs.isEmpty } }

    private static let keys: Set<String> = [
        "event_id", "poi", "types", "location", "season", "tags", "patrol_art", "patrol_art_clean", "required_cat_types",
        "frequency", "chance_of_success", "involved_cats", "relationship_constraint", "patrol_temperament",
        "intro_strings", "decline_strings", "success_outcomes", "fail_outcomes", "antag_success_outcomes", "antag_fail_outcomes",
    ]

    init?(_ json: [String: Any]) {
        guard Set(json.keys).isSubset(of: Self.keys), let id = json["event_id"] as? String else { return nil }
        self.id = id
        location = json["location"] as? [String] ?? []
        types = (json["types"] as? [String] ?? []).compactMap(PatrolType.init)
        guard !types.isEmpty else { return nil }

        var slots: [PatrolSlot] = []
        for (abbr, spec) in json["involved_cats"] as? [String: [String: Any]] ?? [:] {
            guard let slot = PatrolSlot(abbr: abbr, spec) else { return nil }
            slots.append(slot)
        }
        self.slots = slots.sorted { $0.abbr < $1.abbr }
        let ruleJSON = json["relationship_constraint"] as? [[String: Any]] ?? []
        rules = ruleJSON.compactMap(RelationshipRule.init)
        guard rules.count == ruleJSON.count else { return nil }
        tags = json["tags"] as? [String] ?? []
        guard tags.allSatisfy(PatrolLibrary.isSupportedTag) else { return nil }

        poi = PoiRequirement(json["poi"] as? [String: Any])
        let slotNames = Set(["p_l"] + slots.map(\.abbr) + (poi == nil ? [] : ["POI"]))
        intro = (json["intro_strings"] as? [String] ?? []).filter { PatrolLibrary.textIsSupported($0, abbreviations: slotNames) }
        decline = (json["decline_strings"] as? [String] ?? []).filter { PatrolLibrary.textIsSupported($0, abbreviations: slotNames) }
        func outcomes(_ key: String) -> [PatrolOutcome] {
            (json[key] as? [[String: Any]] ?? []).compactMap { PatrolOutcome($0, patrolSlots: slotNames) }
        }
        success = outcomes("success_outcomes")
        fail = outcomes("fail_outcomes")
        antagSuccess = outcomes("antag_success_outcomes")
        antagFail = outcomes("antag_fail_outcomes")
        guard !intro.isEmpty, !decline.isEmpty, !success.isEmpty, !fail.isEmpty else { return nil }

        frequency = json["frequency"] as? Int ?? 4
        chanceOfSuccess = json["chance_of_success"] as? Int ?? 50
        requiredCatTypes = json["required_cat_types"] as? [String: [Int]] ?? [:]
        season = json["season"] as? [String] ?? []
        art = (json["patrol_art_clean"] ?? json["patrol_art"]) as? String

        var sizes: [String: Int] = [:]
        var dominant: String?
        for outcome in success {
            guard let size = outcome.preySize else { continue }
            sizes[size, default: 0] += 1
            if sizes[size]! >= sizes[dominant ?? "", default: 0] { dominant = size }
        }
        dominantPrey = dominant

        var weight = 1
        if !season.isEmpty, !season.contains("any") { weight += 2 * max(0, 4 - season.count) }
        if !location.isEmpty, !location.contains("any") { weight += 2 * max(0, 6 - location.count) }
        weight += 2 * tags.count + slots.reduce(0) { $0 + $1.weight }
        weight += 2 * max(0, requiredCatTypes.count - 1) + 20 * rules.count + (poi?.weight ?? 0)
        self.weight = max(weight, 1)
    }
}

/// Clangen's general and per-biome patrols, plus the new-cat and other-Clan patrols.
struct PatrolLibrary: @unchecked Sendable {
    private let patrols: [String: [PatrolEvent]]
    let newCatPatrols: [String: [PatrolEvent]]
    let otherClanPatrols: [String: [PatrolEvent]]
    let prey: [String: [String]]
    let places: PointsOfInterest?
    private let artDirectory: URL?

    init(directory: URL, artDirectory: URL?) throws {
        func load(_ path: String) -> [PatrolEvent] {
            guard let data = try? Data(contentsOf: directory.appending(path: "patrols/\(path)")),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return list.compactMap(PatrolEvent.init)
        }
        var patrols: [String: [PatrolEvent]] = [:]
        for type in PatrolType.allCases {
            for biome in Biome.allCases {
                for season in Season.allCases.map({ $0.rawValue.lowercased() }) + ["any"] {
                    patrols["\(biome.key)/\(type.folder)/\(season)"] = load("\(biome.key)/\(type.folder)/\(season).json")
                }
            }
            patrols["\(type.folder)/general"] = load("general/\(type.folder).json")
        }
        self.patrols = patrols
        newCatPatrols = ["": load("new_cat.json"), "welcoming": load("new_cat_welcoming.json"), "hostile": load("new_cat_hostile.json")]
        otherClanPatrols = ["": load("other_clan.json"), "ally": load("other_clan_ally.json"), "hostile": load("other_clan_hostile.json")]
        prey = (try? JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "patrols/prey.json")))) as? [String: [String]] ?? [:]
        places = try? PointsOfInterest(directory: directory)
        self.artDirectory = artDirectory
    }

    static func bundled() throws -> PatrolLibrary {
        guard let text = Bundle.main.url(forResource: "Text", withExtension: nil) else { throw SpriteError.missingSheet("Text") }
        return try PatrolLibrary(directory: text, artDirectory: Bundle.main.url(forResource: "PatrolArt", withExtension: nil))
    }

    /// Patrols for a type this season: the general file plus the biome's "any" and season files,
    /// limited to the Clan's biome and camp.
    func patrols(for type: PatrolType, season: Season, biome: Biome = .forest, camp: Int = 1) -> [PatrolEvent] {
        let folder = type.folder
        let all = (patrols["\(folder)/general"] ?? []) + (patrols["\(biome.key)/\(folder)/any"] ?? [])
            + (patrols["\(biome.key)/\(folder)/\(season.rawValue.lowercased())"] ?? [])
        return all.filter { Constraint.locationAllows($0.location, biome: biome, camp: camp) }
    }

    var count: Int { Set(patrols.values.flatMap { $0.map(\.id) }).count }

    /// The URL of a patrol art image, if it was bundled.
    func artURL(_ name: String?) -> URL? {
        guard let name, let artDirectory else { return nil }
        let url = artDirectory.appending(path: name.lowercased().replacingOccurrences(of: "/", with: "__") + ".png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func introArt(for type: PatrolType) -> String {
        switch type {
        case .hunting: "hunt_general_intro"
        case .border: "bord_general_intro"
        case .training: "train_general_intro"
        case .herbGathering: "med_general_intro"
        }
    }

    static func isSupportedTag(_ tag: String) -> Bool {
        Constraint.isSupportedTag(tag) || ["romance", "halloween", "april_fools", "new_years"].contains(tag)
    }

    private static let blocked = [
        "POI", "acc_", "given_herb", "mur_c", "multi_cat", "%{", "n_c:", "patrol_cats", "some_patrol",
    ]
    nonisolated(unsafe) private static let abbreviationPattern = try! Regex(#"\b(p_l|[rsn]_c\d?|m_c)\b"#)

    /// Text may only name cats the patrol or outcome defines, and no unsupported features.
    static func textIsSupported(_ text: String, abbreviations: Set<String>) -> Bool {
        if blocked.contains(where: { text.contains($0) && !abbreviations.contains($0) }) { return false }
        for match in text.matches(of: abbreviationPattern) {
            let token = String(text[match.range])
            if !abbreviations.contains(token) { return false }
        }
        return true
    }
}
