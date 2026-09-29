import Foundation

/// A Clangen `future_event`: another event to try some moons later with some of the same cats.
struct FutureEventSpec: Sendable {
    let eventType: String
    let subTypes: [String]
    let delay: ClosedRange<Int>
    /// New abbreviation → abbreviation in the original event, e.g. "mur_c" → "m_c".
    let carried: [String: String]

    init?(_ json: [String: Any]) {
        guard let type = json["event_type"] as? String,
              let subTypes = (json["pool"] as? [String: Any])?["sub_type"] as? [String]
        else { return nil }
        let delay = json["moon_delay"] as? [Int] ?? [1, 1]
        eventType = type
        self.subTypes = subTypes
        self.delay = (delay.first ?? 1)...max(delay.first ?? 1, delay.last ?? 1)
        carried = (json["involved_cats"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    }
}

/// A Clangen event chosen for this moon: its text and the cats filling each abbreviation.
struct StoryPick: Sendable {
    enum LivesLost: Sendable { case one, some, all }

    var template: String
    var cats: [String: UUID]
    var deaths: [UUID] = []
    var livesLost = LivesLost.one
    var relationshipChanges: [RelationshipChange] = []
    var injuries: [InjuryBlock] = []
    var supplies: [SupplyBlock] = []
    /// The neighbouring Clan the text calls `o_c_n`, and how the event changes relations with it.
    var otherClan: UUID?
    var relationsChange = 0
    var reputationChange = 0
    /// New-cat event blocks (`n_c:0`, `n_c:1`…), each a list of Clangen attributes.
    var newCats: [[String]] = []
    /// `n_c:i` entries whose "The Clan has encountered…" notice is left out.
    var hiddenNewCats: Set<String> = []
    /// Abbreviations that stand for several cats, e.g. `multi_cat`.
    var groupCats: [String: [UUID]] = [:]
    /// Clangen's `no_body` tag: nobody finds the body, which changes how cats grieve.
    var noBody = false
    var tags: [String] = []
    var futureEvents: [FutureEventSpec] = []
    /// Abbreviations left out of the log's cat links, e.g. a secret murderer.
    var excludedCats: Set<String> = []
    /// Death-history text by abbreviation; `m_c` in each means the cat it belongs to.
    var deathHistories: [String: String] = [:]
    /// The event's `new_accessory` list: `m_c` gains one of these ("WILD", "PLANT", "COLLAR" or ids).
    var newAccessory: [String] = []

    /// The history text for a cat who died in this event, and the other cat involved.
    func deathHistory(for id: UUID) -> (text: String?, involved: UUID?) {
        guard let abbr = allCats.first(where: { $0.value.contains(id) })?.key else { return (nil, nil) }
        let other = abbr == "m_c" ? cats["r_c"] : cats["m_c"]
        return (deathHistories[abbr], other == id ? nil : other)
    }

    /// Every abbreviation with the cats it stands for.
    var allCats: [String: [UUID]] { cats.mapValues { [$0] }.merging(groupCats) { a, _ in a } }
}

/// Clangen's war notices (`events/war.json`).
struct WarText: Sendable {
    let trigger: [String]
    let progress: [String: [String]]
    let conclusion: [String]
}

/// A leader's den outcome (`events/leader_den`).
struct LeaderDenOutcome: Sendable {
    let interaction: String
    let text: String
    let change: Int
    let main: Constraint?
    let playerTemperament: [String]
    let otherTemperament: [String]
    let reputation: [String]

    init?(_ json: [String: Any]) {
        guard let interaction = json["interaction_type"] as? String, let text = json["event_text"] as? String else { return nil }
        self.interaction = interaction
        self.text = text
        change = (json["rel_change"] ?? json["rep_change"]) as? Int ?? 0
        var main = json["m_c"] as? [String: Any] ?? [:]
        main["new_thought"] = nil
        main["kit_thought"] = nil
        self.main = Constraint(main)
        playerTemperament = json["player_clan_temper"] as? [String] ?? ["any"]
        otherTemperament = json["other_clan_temper"] as? [String] ?? ["any"]
        reputation = json["reputation"] as? [String] ?? ["any"]
    }
}

struct LeaderDenText: Sendable {
    let clanSuccess: [LeaderDenOutcome]
    let clanFail: [LeaderDenOutcome]
    let outsiderSuccess: [LeaderDenOutcome]
    let outsiderFail: [LeaderDenOutcome]
}

/// An event `supplies` block: a condition on the prey pile or herb stores, and how it changes them.
struct SupplyBlock: Sendable {
    /// "freshkill", "all_herb", "any_herb" or a herb name.
    let type: String
    let triggers: [String]
    /// e.g. "reduce_half", "increase_10", or "" for no change.
    let adjust: String

    init?(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        self.type = type
        triggers = json["trigger"] as? [String] ?? ["always"]
        adjust = json["adjust"] as? String ?? ""
    }
}

/// An event `injury` block: which cats get hurt, the possible injuries (or injury groups), and scar options.
struct InjuryBlock: Sendable {
    let cats: [String]
    let injuries: [String]
    let scars: [String]

    init?(_ json: [String: Any]) {
        guard let cats = json["cats"] as? [String], let injuries = json["injuries"] as? [String] else { return nil }
        self.cats = cats
        self.injuries = injuries
        scars = json["scars"] as? [String] ?? []
    }

    /// Clangen refuses events that would mangle a missing tail or tear a missing ear.
    func allows(_ cat: Cat) -> Bool {
        let scars = Set(cat.appearance.scars)
        if injuries.contains("mangled tail"), !scars.isDisjoint(with: ["NOTAIL", "HALFTAIL"]) { return false }
        if injuries.contains("torn ear"), scars.contains("NOEAR") { return false }
        return true
    }
}

/// Clangen's ceremony, death and misc event text, filtered to the features KittyClan simulates.
///
/// Events are kept only when every key, constraint and text token is understood; anything
/// else is dropped at load time rather than half-supported.
struct EventLibrary: Sendable {
    private let ceremonies: [String: [Ceremony]]
    private let honors: [String: [String]]
    /// Short events keyed by sub-type ("" or "old_age") then frequency.
    private let deaths: [String: [Int: [ShortEvent]]]
    /// Keyed by sub-type ("" or "war") then frequency.
    private let misc: [String: [Int: [ShortEvent]]]
    private let miscBySubType: [String: [Int: [ShortEvent]]]
    /// Misc events with the "accessory" sub-type, keyed by their other sub-type ("", "ceremony" or "war") then frequency.
    private let accessoryEvents: [String: [Int: [ShortEvent]]]
    private let injuryEvents: [String: [Int: [ShortEvent]]]
    let war: WarText
    let leaderDen: LeaderDenText
    private let newCatEvents: [String: [Int: [ShortEvent]]]
    let outsiderDeaths: [String: [String]]
    let announcements: [String]
    let twoParentBirths: [String]
    let kitAmount: [String: String]
    /// The `event_id` of every ceremony and short event that loaded.
    let eventIDs: Set<String>

    init(directory: URL) throws {
        func load(_ path: String) throws -> Any {
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: path)))
        }
        func events(_ paths: String...) throws -> [[String: Any]] {
            try paths.flatMap { try load($0) as? [[String: Any]] ?? [] }
        }

        var ceremonies: [String: [Ceremony]] = [:]
        for name in ["apprentice", "medicine_cat_apprentice", "mediator_apprentice", "warrior", "medicine_cat", "mediator", "deputy", "leader", "elder"] {
            ceremonies[name] = try events("ceremonies/\(name).json").compactMap(Ceremony.init)
        }
        self.ceremonies = ceremonies
        honors = try load("ceremonies/ceremony_traits.json") as? [String: [String]] ?? [:]

        func group(_ list: [ShortEvent]) -> [Int: [ShortEvent]] { Dictionary(grouping: list, by: \.frequency) }
        /// General events plus every biome's own file; a biome file's untagged events stay in that biome.
        func parse(_ type: String) throws -> [ShortEvent] {
            let general = try events("\(type)/general.json")
            let biomes = try Biome.allCases.flatMap { biome in
                try events("\(type)/\(biome.key).json").map { json in
                    var json = json
                    if (json["location"] as? [String] ?? ["any"]).contains("any") { json["location"] = [biome.key] }
                    return json
                }
            }
            return (general + biomes).compactMap(ShortEvent.init)
        }
        let deathEvents = try parse("death").filter { $0.plain }
        deaths = Dictionary(grouping: deathEvents, by: \.subType).mapValues(group)
        func bySubType(_ list: [ShortEvent]) -> [String: [Int: [ShortEvent]]] {
            Dictionary(grouping: list.filter { ["", "war"].contains($0.subType) }, by: \.subType).mapValues(group)
        }
        let miscEvents = try parse("misc")
        misc = bySubType(miscEvents.filter { !$0.isAccessory })
        miscBySubType = Dictionary(grouping: miscEvents.filter(\.plain), by: \.subType).mapValues(group)
        accessoryEvents = Dictionary(grouping: miscEvents.filter(\.isAccessory), by: \.subType).mapValues(group)
        injuryEvents = bySubType(try parse("injury").filter { $0.plain })

        newCatEvents = bySubType(try parse("new_cat").filter { $0.plain && !$0.newCats.isEmpty })
        outsiderDeaths = try load("outsider_deaths/outsider_deaths.json") as? [String: [String]] ?? [:]

        let warJSON = try load("war/war.json") as? [String: Any] ?? [:]
        let progress = (warJSON["progress_events"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String] }
        war = WarText(
            trigger: warJSON["trigger_events"] as? [String] ?? [],
            progress: progress,
            conclusion: warJSON["conclusion_events"] as? [String] ?? []
        )
        func den(_ path: String) throws -> [LeaderDenOutcome] {
            (try load("leader_den/\(path).json") as? [[String: Any]] ?? []).compactMap(LeaderDenOutcome.init)
        }
        leaderDen = LeaderDenText(
            clanSuccess: try den("success/other_clan"), clanFail: try den("fail/other_clan"),
            outsiderSuccess: try den("success/outsider"), outsiderFail: try den("fail/outsider")
        )

        let pregnancy = try load("pregnancy.json") as? [String: Any] ?? [:]
        announcements = pregnancy["announcement"] as? [String] ?? []
        twoParentBirths = (pregnancy["birth"] as? [String: Any])?["two_parents"] as? [String] ?? []
        kitAmount = (try load("pregnancy.en.json") as? [String: Any])?["kit_amount"] as? [String: String] ?? [:]

        let shortEvents = [deaths, misc, miscBySubType, accessoryEvents, injuryEvents, newCatEvents]
            .flatMap { $0.values.flatMap { $0.values.flatMap { $0.map(\.id) } } }
        eventIDs = Set(ceremonies.values.flatMap { $0.map(\.id) } + shortEvents)
    }

    var ceremonyCounts: [String: Int] { ceremonies.mapValues(\.count) }
    var deathCount: Int { deaths.values.flatMap(\.values).reduce(0) { $0 + $1.count } }
    var miscCount: Int { misc.values.flatMap(\.values).reduce(0) { $0 + $1.count } }
    var accessoryEventCount: Int { accessoryEvents.values.flatMap(\.values).reduce(0) { $0 + $1.count } }
    var injuryCount: Int { injuryEvents.values.flatMap(\.values).reduce(0) { $0 + $1.count } }
    var newCatCount: Int { newCatEvents.values.flatMap(\.values).reduce(0) { $0 + $1.count } }

    // MARK: - Ceremonies

    static func ceremonyFile(for rank: Rank) -> String? {
        switch rank {
        case .apprentice: "apprentice"
        case .medicineApprentice: "medicine_cat_apprentice"
        case .warrior: "warrior"
        case .medicineCat: "medicine_cat"
        case .mediator: "mediator"
        case .mediatorApprentice: "mediator_apprentice"
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

    typealias SupplyCheck = ([SupplyBlock]) -> Bool

    /// What a short event may refer to: a neighbouring Clan (the enemy on war draws) and supply levels.
    struct Context {
        var otherClan: OtherClan?
        var war = false
        var warGoingWell = false
        var supplies: SupplyCheck = { $0.isEmpty }
    }

    func deathEvent(for cat: Cat, oldAge: Bool, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        if oldAge { return deaths["old_age"].flatMap { shortEvent(from: $0, for: cat, in: clan, context: context, using: &rng) } }
        return draw(deaths, for: cat, in: clan, context: context, using: &rng)
    }

    func miscEvent(for cat: Cat, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        draw(misc, for: cat, in: clan, context: context, using: &rng)
    }

    /// Clangen's accessory events for `gain_accessories`; a cat who just had a ceremony draws ceremony ones.
    func accessoryEvent(for cat: Cat, ceremony: Bool, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        if ceremony {
            return accessoryEvents["ceremony"].flatMap { shortEvent(from: $0, for: cat, in: clan, context: context, using: &rng) }
        }
        return draw(accessoryEvents, for: cat, in: clan, context: context, using: &rng)
    }

    func injuryEvent(for cat: Cat, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        draw(injuryEvents, for: cat, in: clan, context: context, using: &rng)
    }

    /// Clangen's new-cat events: who arrives, and whether they join or are only met.
    func newCatEvent(for cat: Cat, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        draw(newCatEvents, for: cat, in: clan, context: context, using: &rng)
    }

    /// War draws use war events; when none fits, KittyClan falls back to an ordinary event.
    /// How many misc events of a sub-type loaded.
    func miscCount(subType: String) -> Int { miscBySubType[subType]?.values.reduce(0) { $0 + $1.count } ?? 0 }
    var murderCount: Int { deaths["murder"]?.values.reduce(0) { $0 + $1.count } ?? 0 }

    /// A murder story for this victim and murderer (Clangen's `murder` death events).
    func murderEvent(victim: Cat, murderer: UUID, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        deaths["murder"].flatMap { shortEvent(from: $0, for: victim, fixed: ["r_c": murderer], in: clan, context: context, using: &rng) }
    }

    /// A misc event of the given sub-types with some cats already chosen, e.g. a murder being revealed.
    func miscEvent(subTypes: [String], for cat: Cat, fixed: [String: UUID], in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        let pools = subTypes.compactMap { miscBySubType[$0] }
        let pool = pools.reduce(into: [Int: [ShortEvent]]()) { result, pool in result.merge(pool) { $0 + $1 } }
        return shortEvent(from: pool, for: cat, fixed: fixed, in: clan, context: context, using: &rng)
    }

    private func draw(_ pools: [String: [Int: [ShortEvent]]], for cat: Cat, in clan: Clan, context: Context, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        if context.war, let pool = pools["war"], let pick = shortEvent(from: pool, for: cat, in: clan, context: context, using: &rng) {
            return pick
        }
        var peaceful = context
        peaceful.war = false
        return pools[""].flatMap { shortEvent(from: $0, for: cat, in: clan, context: peaceful, using: &rng) }
    }

    /// Clangen's `create_short_event`: roll a frequency, filter, pick by weight, then find an `r_c`.
    private func shortEvent(
        from pool: [Int: [ShortEvent]], for cat: Cat, fixed: [String: UUID] = [:], in clan: Clan, context: Context,
        using rng: inout some RandomNumberGenerator
    ) -> StoryPick? {
        let roll = Int.random(in: 1...10, using: &rng)
        let preferred = roll <= 4 ? 4 : roll <= 7 ? 3 : roll <= 9 ? 2 : 1
        let season = clan.season.rawValue.lowercased()
        for frequency in [preferred] + [4, 3, 2, 1].filter({ $0 != preferred }) {
            var candidates = (pool[frequency] ?? []).filter { event in
                Constraint.listAllows(event.season, season)
                    && Constraint.tagsAllow(event.tags, in: clan, cat: cat)
                    && Constraint.namedRolesExist(in: event.text, clan: clan)
                    && event.main.matches(cat, allowNewborn: false)
                    && event.injuries.allSatisfy { !$0.cats.contains("m_c") || $0.allows(cat) }
                    && context.supplies(event.supplies)
                    && (event.newAccessory.isEmpty || cat.appearance.accessories.count < 3)
                    && event.fits(context, clan: clan)
            }
            while !candidates.isEmpty {
                let event = candidates.remove(at: weighted(Array(zip(candidates.indices, candidates.map(\.weight))), &rng))
                if var pick = event.resolve(for: cat, fixed: fixed, in: clan, using: &rng) {
                    pick.otherClan = context.otherClan?.id
                    return pick
                }
            }
        }
        return nil
    }
}

// MARK: - Parsed events

private struct Ceremony: Sendable {
    let id: String
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
        id = json["event_id"] as? String ?? ""
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
            let involved = cats.compactMapValues { clan[$0] }
            let options = constraint.candidates(in: clan, involved: involved)
                .filter { !cats.values.contains($0.id) && constraint.matches($0, involved: involved) }
                .shuffled(using: &rng)
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
    let id: String
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
    let injuries: [InjuryBlock]
    let supplies: [SupplyBlock]
    let newCats: [[String]]
    let hiddenNewCats: Set<String>
    let needsOtherClan: Bool
    let otherClanStandings: [String]
    let otherClanTemperaments: [String]
    let relationsChange: Int
    let reputationStandings: [String]
    let reputationChange: Int
    let deathHistories: [String: String]
    let isAccessory: Bool
    let newAccessory: [String]
    let location: [String]
    let excludedCats: Set<String>
    let futureEvents: [FutureEventSpec]
    let weight: Int

    /// Neither an accessory event nor one that gives an accessory.
    var plain: Bool { !isAccessory && newAccessory.isEmpty }

    private static let keys: Set<String> = [
        "event_id", "location", "season", "frequency", "sub_type", "tags", "event_text", "death_text",
        "m_c", "r_c", "history", "relationships", "exclude_involved", "supplies", "injury", "other_clan", "outsider",
        "new_cat", "new_accessory", "future_event",
    ]

    /// New-cat attributes KittyClan can create.
    private static func isSupported(_ attribute: String) -> Bool {
        let simple: Set<String> = [
            "male", "female", "can_birth", "new_name", "old_name", "kittypet", "loner", "rogue", "clancat", "former clancat",
            "meeting", "exists", "unknown", "dead", "litter",
        ]
        if simple.contains(attribute) { return true }
        if attribute.hasPrefix("backstory:") {
            return Backstories.bundled.expand(attribute.dropFirst("backstory:".count).split(separator: ",").map(String.init)) != nil
        }
        return ["status:", "age:", "parent:", "adoptive:", "mate:"].contains { attribute.hasPrefix($0) }
    }

    /// Clangen's `other_clan` and `outsider` filters.
    func fits(_ context: EventLibrary.Context, clan: Clan) -> Bool {
        guard Constraint.locationAllows(location, biome: clan.biome, camp: clan.camp) else { return false }
        if needsOtherClan {
            guard let other = context.otherClan else { return false }
            if !otherClanStandings.isEmpty, !otherClanStandings.contains(other.standing.rawValue) { return false }
            if !otherClanTemperaments.isEmpty {
                let excluded = otherClanTemperaments.filter { $0.hasPrefix("-") }.map { String($0.dropFirst()) }
                let included = otherClanTemperaments.filter { !$0.hasPrefix("-") }
                if !Set(excluded).isDisjoint(with: other.temperament) { return false }
                if !included.isEmpty, Set(included).isDisjoint(with: other.temperament) { return false }
            }
            if context.war, relationsChange < 0, context.warGoingWell { return false }
        }
        if !reputationStandings.isEmpty, !reputationStandings.contains("any"), !reputationStandings.contains(clan.reputationStanding) {
            return false
        }
        return true
    }

    init?(_ json: [String: Any]) {
        let supplyJSON = json["supplies"] as? [[String: Any]] ?? []
        let supplies = supplyJSON.compactMap(SupplyBlock.init)
        guard Set(json.keys).isSubset(of: Self.keys), supplies.count == supplyJSON.count,
              let text = (json["event_text"] ?? json["death_text"]) as? String,
              let blocks = Optional(json["new_cat"] as? [[String]] ?? []),
              blocks.allSatisfy({ $0.allSatisfy(Self.isSupported) }),
              let newAccessory = Optional(json["new_accessory"] as? [String] ?? []),
              Constraint.textIsSupported(text, allowing: Set(
                  ["m_c", "r_c", "o_c_n", "mur_c"] + blocks.indices.flatMap { ["n_c:\($0)", "n_c_pre:\($0)"] }
                      + (newAccessory.isEmpty ? [] : ["acc_singular", "acc_plural"])
              ))
        else { return nil }
        self.newAccessory = newAccessory
        newCats = blocks
        let excluded = json["exclude_involved"] as? [String] ?? []
        excludedCats = Set(excluded)
        hiddenNewCats = Set(blocks.indices.map { "n_c:\($0)" }.filter { key in
            excluded.contains(key) || blocks[Int(key.dropFirst(4))!].contains("unknown")
        })
        var subTypes = json["sub_type"] as? [String] ?? []
        isAccessory = subTypes.contains("accessory")
        subTypes.removeAll { $0 == "accessory" }
        if subTypes.contains("murder") { subTypes = ["murder"] }
        let futureJSON = json["future_event"] as? [[String: Any]] ?? []
        futureEvents = futureJSON.compactMap(FutureEventSpec.init)
        guard futureEvents.count == futureJSON.count else { return nil }
        let otherClanJSON = json["other_clan"] as? [String: Any]
        needsOtherClan = otherClanJSON != nil || text.contains("o_c_n") || subTypes == ["war"]
        otherClanStandings = (otherClanJSON?["current_rep"] as? [String] ?? []).filter { $0 != "any" }
        otherClanTemperaments = otherClanJSON?["temperament"] as? [String] ?? []
        relationsChange = otherClanJSON?["changed"] as? Int ?? 0
        let outsiderJSON = json["outsider"] as? [String: Any]
        reputationStandings = outsiderJSON?["current_rep"] as? [String] ?? []
        reputationChange = outsiderJSON?["changed"] as? Int ?? 0
        guard subTypes.count <= 1 else { return nil }
        let location = json["location"] as? [String] ?? ["any"]
        self.location = location
        let tags = json["tags"] as? [String] ?? []
        guard tags.allSatisfy(Constraint.isSupportedTag) else { return nil }

        let mainJSON = json["m_c"] as? [String: Any] ?? [:]
        guard let main = Constraint(mainJSON) else { return nil }
        let randomJSON = json["r_c"] as? [String: Any]
        if randomJSON == nil, text.replacingOccurrences(of: "mur_c", with: "").contains("r_c") { return nil }
        var random: Constraint?
        if let randomJSON {
            guard let c = Constraint(randomJSON) else { return nil }
            random = c
        }
        if !main.relationshipStatus.isEmpty, random == nil { return nil }
        let changes = (json["relationships"] as? [[String: Any]] ?? []).compactMap(RelationshipChange.init)
        guard changes.count == (json["relationships"] as? [Any])?.count ?? 0 else { return nil }
        let injuries = (json["injury"] as? [[String: Any]] ?? []).compactMap(InjuryBlock.init)
        guard injuries.count == (json["injury"] as? [Any])?.count ?? 0,
              injuries.allSatisfy({ Set($0.cats).isSubset(of: ["m_c", "r_c"] + blocks.indices.map { "n_c:\($0)" }) })
        else { return nil }

        id = json["event_id"] as? String ?? ""
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
        self.injuries = injuries
        self.supplies = supplies
        var histories: [String: String] = [:]
        for block in json["history"] as? [[String: Any]] ?? [] {
            guard let death = block["death"] as? String else { continue }
            for abbr in block["cats"] as? [String] ?? [] { histories[abbr] = death }
        }
        deathHistories = histories

        var weight = 1
        if !otherClanStandings.isEmpty { weight += (3 - otherClanStandings.count) * 5 }
        if location != ["any"] { weight += 1 }
        if season != ["any"] { weight += max(0, 4 - season.count) }
        for c in [mainJSON, randomJSON ?? [:]] {
            if let ages = c["age"] as? [String], ages != ["any"] { weight += max(0, 7 - ages.count) }
            if let statuses = c["status"] as? [String], statuses != ["any"] { weight += max(0, 11 - statuses.count) }
            weight += (c["relationship_status"] as? [String])?.count ?? 0
            if let traits = c["trait"] as? [String] { weight += max(0, 54 - traits.count) }
            if c["backstory"] != nil { weight += 1 }
        }
        self.weight = weight
    }

    /// - Parameter fixed: cats already chosen, e.g. the murderer as `r_c` or the victim as `mur_c`.
    func resolve(for cat: Cat, fixed: [String: UUID] = [:], in clan: Clan, using rng: inout some RandomNumberGenerator) -> StoryPick? {
        var cats = ["m_c": cat.id].merging(fixed.filter { $0.key != "r_c" }) { a, _ in a }
        var deaths: [UUID] = mainDies ? [cat.id] : []
        if text.contains("mur_c"), cats["mur_c"] == nil { return nil }
        if let random {
            let romance = tags.contains("romance")
            let involved = ["m_c": cat]
            let options = random.candidates(in: clan, involved: involved).filter { other in
                (fixed["r_c"].map { other.id == $0 } ?? !cats.values.contains(other.id))
                    && other.id != cat.id && random.matches(other, allowNewborn: false, involved: involved)
                    && (other.isAlive || !randomDies && injuries.allSatisfy { !$0.cats.contains("r_c") })
                    && main.relationshipHolds(from: cat, to: other, in: clan)
                    && random.relationshipHolds(from: other, to: cat, in: clan)
                    && injuries.allSatisfy { !$0.cats.contains("r_c") || $0.allows(other) }
                    && (!romance || clan.isPotentialMate(cat, other, forLoveInterest: true))
            }
            guard let other = options.randomElement(using: &rng) else { return nil }
            cats["r_c"] = other.id
            if randomDies { deaths.append(other.id) }
        }
        if cat.id == clan.leader, tags.contains("all_lives"), cat.moons < 150, Int.random(in: 0..<5, using: &rng) != 0 {
            return nil
        }
        let lives: StoryPick.LivesLost = tags.contains("all_lives") ? .all : tags.contains("some_lives") ? .some : .one
        return StoryPick(template: text, cats: cats, deaths: deaths, livesLost: lives, relationshipChanges: relationshipChanges, injuries: injuries, supplies: supplies,
                         relationsChange: relationsChange, reputationChange: reputationChange,
                         newCats: newCats, hiddenNewCats: hiddenNewCats, noBody: tags.contains("no_body"), tags: tags,
                         futureEvents: futureEvents, excludedCats: excludedCats, deathHistories: deathHistories,
                         newAccessory: newAccessory)
    }
}
