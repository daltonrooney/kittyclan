import Foundation

/// A patrol in progress: the chosen Clangen patrol, its cats, and both possible outcomes.
struct PatrolSession: Sendable {
    let type: PatrolType
    let cats: [UUID]
    /// The neighbouring Clan this patrol may meet (`o_c_n`).
    let otherClan: UUID?
    let patrol: PatrolEvent
    /// Abbreviation → cats, e.g. `p_l`, `r_c0`, `patrol_cats`, `apprentice`.
    var involved: [String: [UUID]]
    let intro: String
    let introArt: String?
    let success: (outcome: PatrolOutcome, cats: [String: [UUID]])
    let fail: (outcome: PatrolOutcome, cats: [String: [UUID]])
    let antagSuccess: (outcome: PatrolOutcome, cats: [String: [UUID]])?
    let antagFail: (outcome: PatrolOutcome, cats: [String: [UUID]])?

    var canAntagonize: Bool { antagSuccess != nil && antagFail != nil }
}

struct PatrolResult: Sendable {
    let text: String
    let results: [String]
    let art: String?
    let succeeded: Bool
}

enum PatrolChoice: Sendable { case proceed, decline, antagonize }

/// Clangen's patrols (`events_module/patrol`), without skills, other Clans, herb stores or places.
struct PatrolEngine: Sendable {
    let library: PatrolLibrary
    let engine: MoonEngine
    let template: TextTemplate

    private static let patrolRanks: Set<Rank> = [.warrior, .deputy, .leader, .apprentice, .medicineCat, .medicineApprentice]
    /// Clangen's `[prey.patrol_balance]`: tiny to huge prey weights by biome and season.
    private static let preyWeights: [Biome: [Season: [Int]]] = {
        let forest: [Season: [Int]] = [.newleaf: [2, 5, 5, 2, 1], .greenleaf: [1, 3, 6, 4, 2], .leafFall: [2, 4, 5, 3, 1], .leafBare: [3, 6, 4, 2, 0]]
        var mountainous = forest
        mountainous[.leafFall] = [2, 6, 4, 2, 1]
        let beach: [Season: [Int]] = [.newleaf: [2, 5, 5, 2, 1], .greenleaf: [2, 5, 5, 2, 1], .leafFall: [2, 5, 5, 2, 1], .leafBare: [2, 6, 4, 2, 1]]
        return [.forest: forest, .mountainous: mountainous, .plains: forest, .beach: beach]
    }()
    private static let preySizes = ["tiny", "small", "medium", "large", "huge"]

    /// Cats who can go on patrol right now.
    static func eligible(in clan: Clan) -> [Cat] {
        clan.living.filter { Self.patrolRanks.contains($0.rank) && !$0.isNotWorking && !clan.patrolledThisMoon.contains($0.id) }
    }

    // MARK: - Starting a patrol

    /// Picks a patrol for these cats. A medicine cat always makes it an herb-gathering patrol.
    /// The Clan only changes (cats marked as patrolled, new outsiders) when a patrol is found.
    func start(_ catIDs: [UUID], type requested: PatrolType?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> PatrolSession? {
        var working = clan
        guard let session = begin(catIDs, type: requested, in: &working, using: &rng) else { return nil }
        clan = working
        return session
    }

    private func begin(_ catIDs: [UUID], type requested: PatrolType?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> PatrolSession? {
        let cats = catIDs.compactMap { clan[$0] }
        guard (1...6).contains(cats.count) else { return nil }
        let hasHealer = cats.contains { [.medicineCat, .medicineApprentice].contains($0.rank) }
        let type: PatrolType = hasHealer ? .herbGathering
            : (requested == .herbGathering || requested == nil ? pick([.hunting, .border, .training], &rng) : requested!)

        var involved = Self.groups(for: cats)
        involved["p_l"] = [patrolLeader(cats, using: &rng)]
        involved["patrol_cats"] = catIDs
        if cats.count >= 3 {
            let count = Int.random(in: min(2, cats.count)...min(5, cats.count - 1), using: &rng)
            involved["some_patrol"] = Array(catIDs.shuffled(using: &rng).prefix(count))
        }

        if clan.otherClans.isEmpty { clan.otherClans = engine.generateOtherClans(for: clan, using: &rng) }
        let otherClan = clan.otherClans.randomElement(using: &rng)
        var candidates = library.patrols(for: type, season: clan.season, biome: clan.biome, camp: clan.camp)
        if type == .hunting { candidates = balanceHunting(candidates, clan: clan, using: &rng) }
        if let otherClan {
            candidates += library.otherClanPatrols[""] ?? []
            if otherClan.standing != .neutral { candidates += library.otherClanPatrols[otherClan.standing.rawValue] ?? [] }
        }
        candidates += outsiderPatrols(in: clan, using: &rng)
        candidates = candidates.filter { $0.types.contains(type) && Constraint.locationAllows($0.location, biome: clan.biome, camp: clan.camp) }
        if type == .herbGathering, candidates.contains(where: \.givesHerbs) { candidates = candidates.filter(\.givesHerbs) }

        let romance = candidates.filter(\.isRomance)
        let normal = candidates.filter { !$0.isRomance }
        var found: (PatrolEvent, [String: [UUID]])?
        if let pick = choose(romance, involved: involved, otherClan: otherClan?.id, clan: clan, using: &rng), romanceRoll(pick.0, cats: pick.1, clan: clan, using: &rng) {
            found = pick
        }
        guard let (patrol, patrolCats) = found ?? choose(normal, involved: involved, otherClan: otherClan?.id, clan: clan, using: &rng) else { return nil }
        involved = patrolCats
        involved = createCats(for: patrol.slots, involved: involved, otherClan: otherClan?.id, in: &clan, using: &rng)

        guard let success = chooseOutcome(patrol.success, involved: involved, otherClan: otherClan?.id, clan: clan, using: &rng),
              let fail = chooseOutcome(patrol.fail, involved: involved, otherClan: otherClan?.id, clan: clan, using: &rng),
              let introText = patrol.intro.randomElement(using: &rng)
        else { return nil }
        let antagSuccess = chooseOutcome(patrol.antagSuccess, involved: involved, otherClan: otherClan?.id, clan: clan, using: &rng)
        let antagFail = chooseOutcome(patrol.antagFail, involved: involved, otherClan: otherClan?.id, clan: clan, using: &rng)

        clan.patrolledThisMoon.formUnion(catIDs)
        let art = library.artURL(patrol.art) != nil ? patrol.art : PatrolLibrary.introArt(for: type)
        return PatrolSession(
            type: type, cats: catIDs, otherClan: otherClan?.id, patrol: patrol, involved: involved,
            intro: resolve(introText, involved, clan: clan, otherClan: otherClan?.id, using: &rng), introArt: art,
            success: success, fail: fail,
            antagSuccess: antagSuccess, antagFail: antagFail
        )
    }

    /// Clangen's outsider patrols: likelier for small Clans, and hostile or welcoming ones by reputation.
    private func outsiderPatrols(in clan: Clan, using rng: inout some RandomNumberGenerator) -> [PatrolEvent] {
        let small = clan.living.count < 20
        let (odds, extra): (Int, String?) = switch clan.reputation {
        case ...30: (small ? 2 : 32, "hostile")
        case ...70: (small ? 2 : 4, nil)
        default: (2, "welcoming")
        }
        guard oneIn(odds, &rng) else { return [] }
        return (library.newCatPatrols[""] ?? []) + (extra.flatMap { library.newCatPatrols[$0] } ?? [])
    }

    /// Rank lists Clangen's `required_cat_types` refers to.
    private static func groups(for cats: [Cat]) -> [String: [UUID]] {
        var groups: [String: [UUID]] = [:]
        for cat in cats {
            groups[cat.rank.rawValue, default: []].append(cat.id)
            if [.medicineCat, .medicineApprentice].contains(cat.rank) { groups["healer cats", default: []].append(cat.id) }
            if cat.rank.isApprentice { groups["all apprentices", default: []].append(cat.id) }
            if [.warrior, .deputy, .leader].contains(cat.rank), cat.age != .adolescent {
                groups["normal adult", default: []].append(cat.id)
            }
        }
        return groups
    }

    /// Clangen's patrol leader: the oldest or most experienced of the highest-ranked cats.
    private func patrolLeader(_ cats: [Cat], using rng: inout some RandomNumberGenerator) -> UUID {
        let pools: [[Cat]] = [
            cats.filter { $0.rank == .medicineCat }, cats.filter { $0.rank == .medicineApprentice },
            cats.filter { $0.rank == .leader }, cats.filter { $0.rank == .deputy }, cats.filter { $0.rank == .warrior }, cats,
        ]
        let pool = pools.first { !$0.isEmpty }!
        let byMoons = Bool.random(using: &rng)
        return pool.max { byMoons ? $0.moons < $1.moons : $0.experience < $1.experience }!.id
    }

    private func balanceHunting(_ patrols: [PatrolEvent], clan: Clan, using rng: inout some RandomNumberGenerator) -> [PatrolEvent] {
        let weights = Self.preyWeights[clan.biome]?[clan.season] ?? [1, 1, 1, 1, 1]
        let size = weighted(Array(zip(Self.preySizes, weights)), &rng)
        let matching = patrols.filter { $0.dominantPrey == size }
        return matching.isEmpty ? patrols : matching
    }

    /// Clangen's `_decide_if_romantic`: 1 in 16, likelier for compatible cats who already like each other.
    private func romanceRoll(_ patrol: PatrolEvent, cats: [String: [UUID]], clan: Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        guard let relationships = engine.relationships else { return false }
        var chance = 16
        for rule in patrol.rules where rule.constraints.contains("can_romance") {
            for a in rule.from.flatMap({ cats[$0] ?? [] }).compactMap({ clan[$0] }) {
                for b in rule.to.flatMap({ cats[$0] ?? [] }).compactMap({ clan[$0] }) where a.id != b.id {
                    switch relationships.compatibility(a, b) {
                    case .positive: chance -= 5
                    case .negative: chance += 5
                    case .neutral: break
                    }
                    let rel = clan.relationship(from: a.id, to: b.id) ?? Relationship()
                    for value in RelationshipValue.allCases { chance += rel[value] > 0 ? -1 : 1 }
                }
            }
        }
        return oneIn(max(chance, 1), &rng)
    }

    // MARK: - Picking events (Clangen's get_valid_event)

    private func choose(_ patrols: [PatrolEvent], involved: [String: [UUID]], otherClan: UUID?, clan: Clan, using rng: inout some RandomNumberGenerator) -> (PatrolEvent, [String: [UUID]])? {
        pickByFrequency(patrols, frequency: \.frequency, weight: \.weight, using: &rng) { patrol, rng in
            guard generalConstraints(season: patrol.season, required: patrol.requiredCatTypes, tags: patrol.tags, involved: involved, clan: clan) else { return nil }
            return fill(patrol.slots, rules: patrol.rules, involved: involved, otherClan: otherClan, clan: clan, using: &rng).map { (patrol, $0) }
        }
    }

    private func chooseOutcome(_ outcomes: [PatrolOutcome], involved: [String: [UUID]], otherClan: UUID?, clan: Clan, using rng: inout some RandomNumberGenerator) -> (outcome: PatrolOutcome, cats: [String: [UUID]])? {
        guard !outcomes.isEmpty else { return nil }
        return pickByFrequency(outcomes, frequency: \.frequency, weight: \.weight, using: &rng) { outcome, rng in
            guard generalConstraints(season: outcome.season, required: outcome.requiredCatTypes, tags: outcome.tags, involved: involved, clan: clan) else { return nil }
            return fill(outcome.slots, rules: outcome.rules, involved: involved, otherClan: otherClan, clan: clan, using: &rng).map { (outcome, $0) }
        }
    }

    /// Rolls a frequency (40/30/20/10% for 4/3/2/1), then tries events of that frequency by weight,
    /// moving to more common and then rarer frequencies when nothing fits.
    private func pickByFrequency<Event, Result, RNG: RandomNumberGenerator>(
        _ events: [Event], frequency: KeyPath<Event, Int>, weight: KeyPath<Event, Int>,
        using rng: inout RNG, accept: (Event, inout RNG) -> Result?
    ) -> Result? {
        let roll = Int.random(in: 1...10, using: &rng)
        let first = roll <= 4 ? 4 : roll <= 7 ? 3 : roll <= 9 ? 2 : 1
        let order = [first] + Array((first + 1)...max(first + 1, 4)).filter { $0 <= 4 } + Array((1..<first).reversed())
        for f in order {
            var pool = events.filter { $0[keyPath: frequency] == f }
            while !pool.isEmpty {
                let index = weighted(Array(zip(pool.indices, pool.map { $0[keyPath: weight] })), &rng)
                if let result = accept(pool.remove(at: index), &rng) { return result }
            }
        }
        return nil
    }

    private func generalConstraints(season: [String], required: [String: [Int]], tags: [String], involved: [String: [UUID]], clan: Clan) -> Bool {
        guard Constraint.listAllows(season, clan.season.rawValue.lowercased()) else { return false }
        for (key, range) in required where range.count == 2 {
            let n = involved[key]?.count ?? 0
            if range[1] == -1, n == 0 { continue }
            if range[0] > n || n > range[1] { return false }
        }
        let date = Calendar.current.dateComponents([.month, .day], from: .now)
        for tag in tags {
            switch tag {
            case "halloween": if !((date.month == 10 && date.day! >= 21) || (date.month == 11 && date.day! <= 7)) { return false }
            case "april_fools": if !(date.month == 4 && date.day == 1) { return false }
            case "new_years": if !(date.month == 1 && date.day == 1) { return false }
            default: break
            }
        }
        guard let leader = involved["p_l"]?.first.flatMap({ clan[$0] }) else { return true }
        return Constraint.tagsAllow(tags.filter { $0 != "romance" && !["halloween", "april_fools", "new_years"].contains($0) }, in: clan, cat: leader)
    }

    /// Clangen's `find_cats`: fills each slot from the patrol (or outsiders for `n_c`), checking relationships.
    private func fill(_ slots: [PatrolSlot], rules: [RelationshipRule], involved: [String: [UUID]], otherClan: UUID?, clan: Clan, using rng: inout some RandomNumberGenerator) -> [String: [UUID]]? {
        guard rules.allSatisfy({ $0.holds(involved, clan, partial: true) }) else { return nil }
        var cats = involved
        let patrol = involved["patrol_cats"] ?? []
        var interactable = patrol

        for slot in slots {
            var candidates: [UUID]
            let isNewCatSlot = slot.abbr.hasPrefix("n_c")
            if let existing = cats[slot.abbr] {
                candidates = existing
            } else if let prior = slot.prior {
                if prior.contains("any") {
                    candidates = interactable
                } else if prior.allSatisfy({ $0.hasPrefix("-") }) {
                    let excluded = Set(prior.flatMap { cats[String($0.dropFirst())] ?? [] })
                    candidates = interactable.filter { !excluded.contains($0) }
                } else {
                    candidates = prior.flatMap { cats[$0] ?? [] }
                }
            } else if isNewCatSlot {
                let used = Set(cats.values.joined())
                candidates = clan.outsiders.filter { $0.isAlive && !used.contains($0.id) }.map(\.id)
            } else {
                let singles = Set(cats.filter { Self.isRole($0.key) }.flatMap(\.value))
                candidates = interactable.filter { !singles.contains($0) }
            }

            let fitting = candidates.shuffled(using: &rng).filter { id in
                guard let cat = clan[id] else { return false }
                return slot.matches(cat, isOutsider: clan.outsiders.contains { $0.id == id }, otherClan: otherClan)
            }
            let chosen = fitting.first { id in
                var trial = cats
                trial[slot.abbr] = [id]
                return rules.allSatisfy { $0.holds(trial, clan, partial: true) }
            }
            if let chosen {
                cats[slot.abbr] = [chosen]
                interactable.removeAll { $0 == chosen }
            } else if slot.create == nil {
                return nil
            }
        }
        return rules.allSatisfy({ $0.holds(cats, clan, partial: true) }) ? cats : nil
    }

    /// Clangen's `updated_create_new_cat`: creates outsiders (or the neighbouring Clan's cats) for
    /// `n_c` slots that couldn't be filled by a cat the Clan already knows.
    private func createCats(for slots: [PatrolSlot], involved: [String: [UUID]], otherClan: UUID?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [String: [UUID]] {
        var involved = involved
        let backstories = Backstories.bundled
        for slot in slots where involved[slot.abbr] == nil {
            guard let spec = slot.create else { continue }
            func cats(_ abbrs: [String]) -> [UUID] { abbrs.flatMap { involved[$0] ?? [] } }
            let mates = cats(spec.mates).compactMap { clan[$0] }
            var age = mates.map(\.age).randomElement(using: &rng) ?? spec.ages.compactMap(CatAge.init).randomElement(using: &rng)
            if spec.litter, age.map({ $0 != .newborn && $0 != .kitten }) ?? true { age = nil }

            var social: NewCatSocial
            if let status = spec.status, let known = NewCatSocial(rawValue: status) {
                social = known
            } else if let story = spec.backstories.first, let implied = backstories.social(of: story) {
                social = implied
            } else if age == nil, !spec.litter {
                social = Bool.random(using: &rng) ? .clancat : pick([.loner, .rogue, .kittypet], &rng)
            } else {
                social = .loner
            }
            let group = social == .clancat || slot.wasClanCat == true ? otherClan ?? clan.otherClans.randomElement(using: &rng)?.id : nil
            if group == nil, social == .clancat { social = .loner }
            let origin: Cat.Origin = social == .clancat ? .clanborn : social.origin ?? .loner
            let blood = cats(spec.bloodParents).prefix(2)
            let adoptive = cats(spec.adoptiveParents).filter { !blood.contains($0) }

            var made: [Cat] = []
            if spec.litter {
                let moons = age == .newborn ? 0 : age == .kitten ? Int.random(in: 1...5, using: &rng) : Int.random(in: 0...5, using: &rng)
                for _ in 0..<Int.random(in: 2...6, using: &rng) {
                    var kit = engine.factory.make(rank: moons == 0 ? .newborn : .kitten, moons: moons, origin: origin, using: &rng)
                    engine.factory.maybeCollar(&kit, using: &rng)
                    made.append(kit)
                }
            } else {
                let age = age ?? (social == .clancat ? Self.otherClanAge(using: &rng) : .adult)
                let sex = spec.genders.compactMap(Cat.Sex.init).randomElement(using: &rng)
                let moons = Int.random(in: min(age.moons.lowerBound, 300)...min(age.moons.upperBound, 300), using: &rng)
                var cat: Cat
                if social == .clancat {
                    cat = engine.factory.make(rank: MoonEngine.rankForAge(age), moons: moons, origin: origin, sex: sex, using: &rng)
                } else {
                    cat = engine.factory.makeJoiner(origin: origin, sex: sex, using: &rng)
                    cat.moons = moons
                }
                if let (path, tier) = spec.skills.randomElement(using: &rng).flatMap(CatSkills.requirement) {
                    let t = max(tier, 1)
                    cat.skills.primary = Skill(
                        path: path, points: Int.random(in: ((t - 1) * 10)...((t - 1) * 10 + 9), using: &rng),
                        interestOnly: [.newborn, .kitten, .adolescent].contains(cat.age)
                    )
                }
                made.append(cat)
            }
            for i in made.indices {
                let baby = made[i].age == .newborn || made[i].age == .kitten
                made[i].backstory = spec.backstories.randomElement(using: &rng) ?? Self.backstory(for: social, baby: baby, using: &rng)
                made[i].otherClan = group
                made[i].leftOtherClan = group != nil && social != .clancat
                made[i].parents = Array(blood)
                made[i].adoptiveParents = adoptive
                for mate in mates {
                    made[i].mates.append(mate.id)
                    if let j = clan.index(of: mate.id) {
                        clan.cats[j].mates.append(made[i].id)
                    } else if let j = clan.outsiders.firstIndex(where: { $0.id == mate.id }) {
                        clan.outsiders[j].mates.append(made[i].id)
                    }
                }
            }
            clan.outsiders += made
            involved[slot.abbr] = made.map(\.id)
        }
        return involved
    }

    /// Clangen's `_assign_backstory` for a patrol's new cat with no backstory given.
    private static func backstory(for social: NewCatSocial, baby: Bool, using rng: inout some RandomNumberGenerator) -> String {
        let category = switch social {
        case .clancat, .formerClancat: baby ? "baby_clancat_backstories" : "former_clancat_backstories"
        default: (baby ? "baby_" : "") + social.rawValue + "_backstories"
        }
        return Backstories.bundled.random(from: category, using: &rng) ?? "outsider1"
    }

    /// An age for another Clan's cat with no age or rank given: any rank but leader or deputy.
    private static func otherClanAge(using rng: inout some RandomNumberGenerator) -> CatAge {
        let rank = pick([Rank.kitten, .apprentice, .medicineApprentice, .mediatorApprentice, .warrior, .medicineCat, .mediator, .elder], &rng)
        return CatAge(moons: CatFactory.randomMoons(for: rank, using: &rng))
    }

    // MARK: - Finishing a patrol

    /// Resolves the player's choice and applies the outcome to the Clan.
    func finish(_ session: PatrolSession, choice: PatrolChoice, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> PatrolResult {
        if choice == .decline {
            let text = session.patrol.decline.randomElement(using: &rng) ?? "The patrol turns back."
            return PatrolResult(text: resolve(text, session.involved, clan: clan, otherClan: session.otherClan, using: &rng), results: [], art: nil, succeeded: false)
        }

        let antagonize = choice == .antagonize && session.canAntagonize
        let successOutcome = antagonize ? session.antagSuccess! : session.success
        let failOutcome = antagonize ? session.antagFail! : session.fail
        let succeeded = rollSuccess(session, successOutcome, clan: clan, using: &rng)
        let (outcome, outcomeCats) = succeeded ? successOutcome : failOutcome

        var cats = session.involved.merging(outcomeCats) { _, new in new }
        cats = createCats(for: outcome.slots, involved: cats, otherClan: session.otherClan, in: &clan, using: &rng)
        let text = resolve(outcome.strings.randomElement(using: &rng) ?? "", cats, clan: clan, otherClan: session.otherClan, using: &rng)

        var results: [String] = []
        results += join(outcome, cats: cats, in: &clan, using: &rng)
        results += kill(outcome, cats: cats, in: &clan, using: &rng)
        results += meet(outcome, cats: cats, in: &clan)
        results += lose(outcome, cats: cats, in: &clan, using: &rng)
        results += injure(outcome, cats: cats, in: &clan, using: &rng)
        results += bringHome(outcome, patrol: session.cats, cats: cats, in: &clan, using: &rng)
        if let other = session.otherClan, let name = clan.otherClan(other)?.name, outcome.relationsChange != 0 {
            clan.changeRelations(with: other, by: outcome.relationsChange)
            results.append("Relations with \(name) have \(outcome.relationsChange > 0 ? "improved" : "worsened").")
        }
        if outcome.reputationChange != 0 {
            clan.changeReputation(by: outcome.reputationChange)
            results.append("Your Clan's reputation towards outsiders has \(outcome.reputationChange > 0 ? "improved" : "worsened").")
        }
        gainExperience(outcome, patrol: session.cats, in: &clan, using: &rng)
        mentorInfluence(session.cats, in: &clan, using: &rng)
        if !outcome.relationshipChanges.isEmpty {
            engine.relationships?.apply(outcome.relationshipChanges, cats: cats, in: &clan, using: &rng)
            results.append("Relationships between cats in the Clan have changed.")
        }

        let entry = LogEntry(kind: .patrol, text: text, cats: session.cats)
        if clan.history.isEmpty { clan.history.append(MoonLog(moon: clan.age, entries: [])) }
        clan.history[clan.history.count - 1].entries.append(entry)

        let art = library.artURL(outcome.art) != nil ? outcome.art : nil
        return PatrolResult(text: text, results: results, art: art, succeeded: succeeded)
    }

    /// Clangen's `calculate_success` for classic mode, with +10 for each trait-matched stat cat.
    private func rollSuccess(_ session: PatrolSession, _ success: (outcome: PatrolOutcome, cats: [String: [UUID]]), clan: Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        let cats = session.cats.compactMap { clan[$0] }
        let n = Double(cats.count)
        let totalExp = Double(cats.reduce(0) { $0 + $1.experience })
        var chance = session.patrol.chanceOfSuccess + Int((1 + 0.1 * n) * totalExp / (n * 2))
        chance = min(chance, 90)
        for slot in success.outcome.slots {
            guard let id = success.cats[slot.abbr]?.first, let cat = clan[id] else { continue }
            chance += slot.successBonus(for: cat)
        }
        if chance >= 120 { chance = 115 }
        return Int.random(in: 0..<120, using: &rng) < chance
    }

    private func targets(_ abbrs: [String], _ cats: [String: [UUID]]) -> [UUID] {
        var result: [UUID] = []
        for abbr in abbrs {
            if abbr.hasPrefix("-") {
                let removed = Set(cats[String(abbr.dropFirst())] ?? [])
                result.removeAll(where: removed.contains)
            } else {
                result += (cats[abbr] ?? []).filter { !result.contains($0) }
            }
        }
        return result
    }

    private func names(_ ids: [UUID], _ clan: Clan) -> String {
        template.list(ids.compactMap { clan[$0] })
    }

    private func join(_ outcome: PatrolOutcome, cats: [String: [UUID]], in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [String] {
        var results: [String] = []
        for block in outcome.joins {
            var joined: [UUID] = []
            for id in targets(block.cats, cats) {
                guard let index = clan.outsiders.firstIndex(where: { $0.id == id }) else { continue }
                var cat = clan.outsiders.remove(at: index)
                if cat.otherClan != nil { cat.leftOtherClan = true }
                if let status = block.statuses.compactMap(Rank.init).randomElement(using: &rng) {
                    cat.rank = status
                } else {
                    cat.rank = switch cat.age {
                    case .newborn: .newborn
                    case .kitten: .kitten
                    case .adolescent: .apprentice
                    case .senior: .elder
                    default: .warrior
                    }
                }
                if block.changeName || cat.name.suffix.isEmpty && cat.age != .adolescent && !cat.rank.isBaby {
                    cat.name = engine.factory.names.generate(for: cat.appearance, using: &rng)
                }
                clan.cats.append(cat)
                joined.append(cat.id)
                if cat.rank.isApprentice {
                    cat.skills.primary?.interestOnly = true
                    cat.skills.secondary?.interestOnly = true
                    clan.cats[clan.cats.count - 1] = cat
                    MoonEngine.assignMentor(to: cat.id, in: &clan, using: &rng)
                }
                var counts: [UUID: Int] = [:]
                _ = engine.relationships?.welcome(cat.id, in: &clan, counts: &counts, using: &rng)
            }
            if !joined.isEmpty { results.append("\(names(joined, clan)) joined the Clan.") }
        }
        return results
    }

    private func kill(_ outcome: PatrolOutcome, cats: [String: [UUID]], in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [String] {
        var results: [String] = []
        for block in outcome.deaths {
            var died: [UUID] = []
            for id in targets(block.cats, cats) {
                if clan.outsiders.contains(where: { $0.id == id }) {
                    clan.sendToAfterlife(id, history: block.history ?? "m_c died on a patrol.", using: &rng)
                    continue
                }
                guard clan.isAlive(id) else { continue }
                if clan.leader == id {
                    if outcome.tags.contains("all_lives") {
                        clan.leaderLives = 1
                    } else if outcome.tags.contains("some_lives"), clan.leaderLives > 3 {
                        clan.leaderLives -= Int.random(in: 2...(clan.leaderLives - 1), using: &rng) - 1
                    }
                }
                let events = engine.loseLifeOrDie(id, cause: .misfortune, history: block.history ?? "m_c died on a patrol.", in: &clan, using: &rng)
                if events.contains(where: { if case .died = $0 { true } else { false } }) {
                    died.append(id)
                } else if let cat = clan[id] {
                    results.append("\(engine.factory.names.display(cat.name, rank: cat.rank)) lost a life.")
                }
            }
            if !died.isEmpty { results.append("\(names(died, clan)) died.") }
        }
        return results
    }

    private func meet(_ outcome: PatrolOutcome, cats: [String: [UUID]], in clan: inout Clan) -> [String] {
        outcome.meet.compactMap { block in
            let met = targets(block.cats, cats).filter { id in clan.outsiders.contains { $0.id == id } }
            return met.isEmpty ? nil : "The patrol met \(names(met, clan))."
        }
    }

    /// A lost cat leaves the Clan and becomes an outsider.
    private func lose(_ outcome: PatrolOutcome, cats: [String: [UUID]], in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [String] {
        var results: [String] = []
        for block in outcome.lost {
            var lost: [UUID] = []
            for id in targets(block.cats, cats) where clan.isAlive(id) {
                engine.loseCat(id, in: &clan, using: &rng)
                lost.append(id)
            }
            if !lost.isEmpty { results.append("\(names(lost, clan)) \(lost.count == 1 ? "has" : "have") been lost.") }
        }
        return results
    }

    /// Patrol conditions are non-lethal, as they are in Clangen as shipped.
    private func injure(_ outcome: PatrolOutcome, cats: [String: [UUID]], in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [String] {
        guard let library = engine.conditions else { return [] }
        var results: [String] = []
        for block in outcome.conditions {
            let pool = block.names.flatMap { ConditionLibrary.injuryGroups[$0] ?? [$0] }
            for id in targets(block.cats, cats) where clan.isAlive(id) {
                guard let cat = clan[id], let name = pool.filter({ !cat.has($0) }).randomElement(using: &rng) else { continue }
                let got: Bool = switch library.conditions[name]?.kind {
                case .injury: engine.getInjured(id, name, lethal: false, in: &clan, using: &rng)
                case .illness: engine.getIll(id, name, lethal: false, in: &clan, using: &rng)
                case .permanent: engine.getPermanent(id, name, in: &clan, using: &rng)
                case nil: false
                }
                if got { results.append("\(names([id], clan)) got: \(library.displayName(name)).") }
            }
        }
        return results
    }

    private static let preyModifiers: [String: Double] = ["tiny": 0.5, "small": 1, "medium": 1.8, "large": 2.4, "huge": 3.2]
    private static let herbSizes: [String: Int] = ["tiny": 2, "small": 3, "medium": 4, "large": 6, "huge": 8]
    private static let hunterExperienceBonus: [String: Double] = [
        "untrained": 0.1, "learning": 1, "prepared": 2, "capable": 3, "proficient": 4, "adept": 5, "masterful": 6,
    ]

    /// Prey and herbs the patrol brings back. With prey and herbs on they go into the Clan's stores;
    /// skilled hunters bring back more, and observant cats find more herbs.
    private func bringHome(_ outcome: PatrolOutcome, patrol: [UUID], cats: [String: [UUID]], in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [String] {
        var results: [String] = []
        let members = patrol.compactMap { clan[$0] }
        if let size = outcome.preySize, let modifier = Self.preyModifiers[size] {
            if clan.preyAndHerbs {
                var bonus = 0
                var best = 0
                for cat in members {
                    guard let tier = cat.skills.tier(of: .HUNTER), tier > 0 else { continue }
                    best = max(best, tier)
                    bonus += Int((Self.hunterExperienceBonus[PatrolSlot.experienceLevel(cat.experience)] ?? 0) * (Double(tier) / 10 + 1))
                }
                var gained = 4 * modifier * Double(members.count) + Double(bonus)
                if best > 0 { gained = Double(Int(gained * (Double(best) / 20 + 1))) }
                clan.freshKill.add(gained.rounded())
                clan.freshKill.log.append("\(Int(gained.rounded())) pieces of prey were caught on a patrol.")
            }
            results.append("A \(size) amount of prey is brought to camp.")
        }
        guard clan.preyAndHerbs, !outcome.herbs.isEmpty, let herbLibrary = engine.herbLibrary else { return results }
        var found: [String: Int] = [:]
        for block in outcome.herbs {
            let quantity = members.reduce(0) { total, cat in
                total + (Self.herbSizes[block.size] ?? 3) + Int.random(in: -1...1, using: &rng) + (cat.skills.tier(of: .SENSE) ?? 0)
            }
            if block.type == "random_herbs" {
                guard let leader = cats["p_l"]?.first.flatMap({ clan[$0] }) else { continue }
                found.merge(engine.findHerbs(by: leader, limit: quantity, in: clan, using: &rng), uniquingKeysWith: +)
            } else if herbLibrary.herb(block.type) != nil, quantity > 0 {
                found[block.type, default: 0] += quantity
            }
        }
        for (herb, amount) in found { clan.herbs.add(herb, amount) }
        if found.isEmpty {
            results.append("Despite searching, no herbs were found.")
        } else {
            let herbs = herbLibrary.describe(found)
            let total = found.values.reduce(0, +)
            results.append("\(herbs.prefix(1).uppercased() + herbs.dropFirst()) \(total == 1 ? "was" : "were") gathered.")
            clan.herbs.log.append("\(herbs.prefix(1).uppercased() + herbs.dropFirst()) \(total == 1 ? "was" : "were") gathered on patrol.")
        }
        return results
    }

    /// Classic mode: warriors gain experience from successful patrols; smaller patrols learn more.
    private func gainExperience(_ outcome: PatrolOutcome, patrol: [UUID], in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard outcome.expGained > 0 else { return }
        let n = Double(patrol.count)
        let masterful = patrol.contains { (clan[$0]?.experience ?? 0) >= 321 }
        let gained = max(Double(2 * outcome.expGained + (masterful ? 10 : 0)) * (1 - 0.1 * n), 1)
        for id in patrol {
            guard let i = clan.index(of: id), !clan.cats[i].rank.isApprentice else { continue }
            let whole = Int(gained)
            let extra = Double.random(in: 0..<1, using: &rng) < gained - Double(whole) ? 1 : 0
            clan.cats[i].experience = min(321, clan.cats[i].experience + whole + extra)
        }
    }

    /// Clangen's `mentor_influence`: an apprentice patrolling with their mentor grows a little more like them.
    private func mentorInfluence(_ patrol: [UUID], in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        for id in patrol {
            guard let mentorID = clan[id]?.mentor, patrol.contains(mentorID) else { continue }
            engine.mentorPersonalityInfluence(on: id, from: mentorID, in: &clan, using: &rng)
            engine.mentorSkillInfluence(on: id, from: mentorID, in: &clan, using: &rng)
        }
    }

    // MARK: - Text

    /// Role placeholders (`p_l`, `r_c0`, `s_c1`, `n_c0`…), as opposed to groups like `patrol_cats`.
    static func isRole(_ abbr: String) -> Bool {
        abbr == "p_l" || (abbr.count == 4 && ["r_c", "s_c", "n_c"].contains(String(abbr.prefix(3))) && abbr.last!.isNumber)
    }

    private func resolve(_ text: String, _ involved: [String: [UUID]], clan: Clan, otherClan: UUID?, using rng: inout some RandomNumberGenerator) -> String {
        var cats: [String: Cat] = [:]
        for (abbr, ids) in involved where ids.count == 1 && Self.isRole(abbr) {
            if let cat = clan[ids[0]] { cats[abbr] = cat }
        }
        var extras: [String: String] = [:]
        for (abbr, options) in library.prey where text.contains(abbr) {
            extras[abbr] = options.randomElement(using: &rng)
        }
        return template.resolve(text, cats: cats, clan: clan, otherClan: clan.otherClan(otherClan)?.name, extras: extras)
    }
}
