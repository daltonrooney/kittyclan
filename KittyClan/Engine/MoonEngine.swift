import Foundation

/// Advances a Clan by one moon, following the order of Clangen's `events.one_moon`.
struct MoonEngine: Sendable {
    let factory: CatFactory
    let narrator: any Narrator
    var library: EventLibrary?
    var relationships: RelationshipEngine?
    var conditions: ConditionLibrary?
    var herbLibrary: HerbLibrary?
    var ceremonies: LeaderCeremonyLibrary?

    private static let canHaveKits: Set<Rank> = [.leader, .deputy, .medicineCat, .warrior, .elder]
    private static let litterWeights: [CatAge: [Int]] = [
        .youngAdult: [8, 10, 17, 12, 6, 2],
        .adult: [9, 13, 15, 8, 2, 0],
        .seniorAdult: [10, 15, 5, 2, 0, 0],
        .senior: [4, 3, 1, 0, 0, 0],
    ]

    func advance(_ clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        var events: [MoonEvent] = []
        clan.age += 1
        clan.patrolledThisMoon = []
        for id in clan.pregnancies.keys { clan.pregnancies[id]?.moons += 1 }
        afterlifeMoon(in: &clan, using: &rng)
        if clan.otherClans.isEmpty { clan.otherClans = generateOtherClans(for: clan, using: &rng) }
        events += checkWar(in: &clan, using: &rng)
        let denTarget: UUID? = if case .outsider(let id)? = clan.outsiderDenPlan?.target { id } else { nil }
        events += resolveLeaderDen(in: &clan, using: &rng)
        var interactions: [UUID: Int] = [:]
        events += lostCatReturns(in: &clan, counts: &interactions, using: &rng)
        freshKillMoon(in: &clan, using: &rng)

        var someoneJoined = false
        for id in clan.living.map(\.id) {
            guard let i = clan.index(of: id), clan.cats[i].isAlive else { continue }
            var skip: Set<String> = []

            let previousAge = clan.cats[i].age
            clan.cats[i].moons += 1
            if clan.cats[i].rank == .newborn, clan.cats[i].moons >= 1 { clan.cats[i].rank = .kitten }
            if clan.cats[i].age != previousAge {
                let traits = factory.traits
                traits.wobble(&clan.cats[i].personality, by: 2, using: &rng)
                traits.setKit(clan.cats[i].rank.isBaby, &clan.cats[i].personality, using: &rng)
            }

            events += hunger(for: id, in: &clan, using: &rng)
            guard clan.isAlive(id) else { continue }
            if let cat = clan[id], cat.isIll || cat.isInjured {
                events += progressConditions(for: id, skip: &skip, in: &clan, using: &rng)
                guard clan.isAlive(id) else { continue }
                events += outbreak(from: id, in: &clan, using: &rng)
            }
            guard let i = clan.index(of: id), clan.cats[i].rank != .newborn else { continue }

            gainApprenticeExperience(i, in: &clan, using: &rng)
            events += ceremonies(for: id, in: &clan, using: &rng)
            progressSkills(id, in: &clan, using: &rng)
            if clan[id]?.isDisabled == true {
                events += progressDisabilities(for: id, skip: &skip, in: &clan, using: &rng)
                guard clan.isAlive(id) else { continue }
            }
            events += pregnancy(for: id, in: &clan, using: &rng)
            guard clan.isAlive(id) else { continue }
            if let relationships {
                events += relationships.moon(for: id, in: &clan, counts: &interactions, using: &rng)
            }
            if let cat = clan[id], cat.isIll || cat.isInjured {
                // Clangen skips death rolls while a cat is unwell; the 300-moon limit still applies.
                if cat.moons >= 300 { events += die(id, cause: .oldAge, in: &clan, using: &rng) }
                continue
            }

            if !someoneJoined {
                if library != nil {
                    if let arrival = newCatEvent(by: id, in: &clan, counts: &interactions, using: &rng) {
                        events += arrival
                        someoneJoined = true
                    }
                } else if let joined = invite(by: id, in: &clan, using: &rng) {
                    events += joined
                    someoneJoined = true
                    for newcomer in joined.flatMap(\.newcomers) {
                        events += relationships?.welcome(newcomer, in: &clan, counts: &interactions, using: &rng) ?? []
                    }
                }
            }
            if oneIn(30, &rng), let cat = clan[id],
               var pick = library?.miscEvent(for: cat, in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
               addNewCats(to: &pick, in: &clan, counts: &interactions, using: &rng) != nil {
                relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
                applyEventEffects(pick, in: &clan, using: &rng)
                applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
                events.append(.story(pick, .info))
            }
            if Bool.random(using: &rng) {
                events += deathRolls(for: id, in: &clan, using: &rng)
                if clan.isAlive(id) { events += rollIllness(for: id, in: &clan, using: &rng) }
            } else {
                events += rollIllness(for: id, in: &clan, using: &rng)
                if clan.isAlive(id) { events += deathRolls(for: id, in: &clan, using: &rng) }
            }
        }
        events += outsiderMoon(in: &clan, skipping: denTarget, using: &rng)
        herbMoon(in: &clan, using: &rng)
        if clan.preyAndHerbs {
            updateNutrition(in: &clan)
            if Self.preyNeeded(in: clan) > clan.freshKill.total { events.append(.lowPrey) }
        }

        for cat in clan.living where cat.rank.isApprentice && cat.mentor == nil {
            if let mentor = Self.assignMentor(to: cat.id, in: &clan, using: &rng) {
                events.append(.newMentor(apprentice: cat.id, mentor: mentor))
            }
        }
        events += promoteDeputy(in: &clan, using: &rng)

        let entries = events.map { narrator.entry($0, in: clan, using: &rng) }
        for (event, entry) in zip(events, entries) {
            if case .story(let pick, .interaction) = event, let a = pick.cats["m_c"], let b = pick.cats["r_c"] {
                clan.updateRelationship(from: a, to: b) { $0.addLog(entry.text) }
            }
        }
        clan.history.append(MoonLog(moon: clan.age, entries: entries))
    }

    /// The Clan and supply levels an event may refer to this draw.
    func eventContext(for clan: Clan, using rng: inout some RandomNumberGenerator) -> EventLibrary.Context {
        let (other, war) = otherClanForEvent(in: clan, using: &rng)
        return EventLibrary.Context(
            otherClan: other, war: war, warGoingWell: clan.war.trend == .relUp,
            supplies: supplyCheck(for: clan, using: &rng)
        )
    }

    /// Supply, relations and reputation changes from a short event.
    func applyEventEffects(_ pick: StoryPick, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        applySupplies(pick.supplies, in: &clan, using: &rng)
        if let other = pick.otherClan, pick.relationsChange != 0 { clan.changeRelations(with: other, by: pick.relationsChange) }
        if pick.reputationChange != 0 { clan.changeReputation(by: pick.reputationChange) }
    }

    // MARK: - Experience

    /// Apprentices gain experience each moon until they're ready to graduate.
    private func gainApprenticeExperience(_ i: Int, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        let cat = clan.cats[i]
        guard cat.rank.isApprentice, cat.experience <= 50 else { return }
        if cat.isNotWorking, Int.random(in: 0..<3, using: &rng) != 0 { return }
        let pool = cat.rank == .medicineApprentice ? Array(2...7) + [2, 3] : Array(3...12) + [5, 6]
        let base = Double(pick(pool, &rng) + Int.random(in: 0...3, using: &rng))
        let modifier = clan.isAlive(cat.mentor) && clan[cat.mentor]?.isNotWorking == false ? 1.0 : 0.7
        let gain = max(base * modifier, 1)
        let whole = Int(gain)
        clan.cats[i].experience = min(321, cat.experience + whole + (Double.random(in: 0..<1, using: &rng) < gain - Double(whole) ? 1 : 0))
    }

    // MARK: - Ceremonies

    private func ceremonies(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }

        let oldName = factory.names.display(cat.name, rank: cat.rank)

        if cat.rank == .deputy, !clan.isAlive(clan.leader) {
            setRank(.leader, for: id, in: &clan, using: &rng)
            clan.leader = id
            clan.deputy = nil
            crownLeader(id, in: &clan, using: &rng)
            return [.becameLeader(id, oldName: oldName)]
        }

        if [.warrior, .deputy].contains(cat.rank), cat.apprentices.isEmpty, cat.moons > 114 {
            let odds = 100 - 0.7 * Double(cat.moons)
            if cat.moons > 140 || odds <= 1 || Double.random(in: 0..<1, using: &rng) < 1 / odds {
                if clan.deputy == id { clan.deputy = nil }
                setRank(.elder, for: id, in: &clan, using: &rng)
                return [.retired(id)]
            }
        }

        if cat.rank == .kitten, cat.moons == CatAge.adolescent.moons.lowerBound {
            let rank: Rank = becomesMedicineApprentice(cat, in: clan, using: &rng) ? .medicineApprentice : .apprentice
            setRank(rank, for: id, in: &clan, using: &rng)
            return [.apprenticed(id, mentor: clan[id]?.mentor, oldName: oldName)]
        }

        if cat.rank.isApprentice {
            let maxAge = cat.rank == .medicineApprentice ? 30 : 25
            if (cat.experience > 50 && cat.moons >= 10) || cat.moons >= maxAge {
                graduationInfluence(on: id, from: cat.mentor, in: &clan, using: &rng)
                setRank(cat.rank == .medicineApprentice ? .medicineCat : .warrior, for: id, in: &clan, using: &rng)
                return [.graduated(id, oldName: oldName)]
            }
        }
        return []
    }

    /// Clangen's `_is_suitable_medcat_app`, without personality and skill modifiers.
    private func becomesMedicineApprentice(_ cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        let healers = clan.living.filter { $0.rank == .medicineCat }
        let apprentices = clan.living.filter { $0.rank == .medicineApprentice }
        var chance = 41.0
        if healers.isEmpty {
            chance /= 7.125
        } else if Double(healers.filter { $0.age == .senior }.count) / Double(healers.count) > 0.3 {
            chance /= 2.22
        } else {
            chance *= 2.22
        }
        if apprentices.isEmpty { chance /= 1.8 }
        if apprentices.count > 1 { chance *= 1 + 0.2 * Double(apprentices.count - 1) }
        let drawn: Set<SkillPath> = [.OMEN, .PROPHET, .HEALER, .STAR, .DREAM, .CLAIRVOYANT, .GHOST, .CAMP]
        if let path = cat.skills.primary?.path, drawn.contains(path) { chance /= 2 }
        if let path = cat.skills.secondary?.path, drawn.contains(path) { chance /= 4 }
        if cat.isDisabled { chance /= 2 }
        return oneIn(max(1, Int(chance)), &rng)
    }

    /// Changes rank and keeps mentor links valid, like Clangen's `rank_change`.
    func setRank(_ rank: Rank, for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let i = clan.index(of: id) else { return }
        clan.cats[i].rank = rank
        factory.traits.setKit(rank.isBaby, &clan.cats[i].personality, using: &rng)
        if !rank.isApprentice { Self.removeMentor(from: id, in: &clan) }
        for apprentice in clan.cats[i].apprentices where !Self.canMentor(clan[id], clan[apprentice]) {
            Self.removeMentor(from: apprentice, in: &clan)
            Self.assignMentor(to: apprentice, in: &clan, using: &rng)
        }
        if rank.isApprentice { Self.assignMentor(to: id, in: &clan, using: &rng) }
    }

    // MARK: - Mentors

    static func canMentor(_ mentor: Cat?, _ apprentice: Cat?) -> Bool {
        guard let mentor, let apprentice, mentor.isAlive, mentor.id != apprentice.id else { return false }
        switch apprentice.rank {
        case .apprentice: return [.leader, .deputy, .warrior].contains(mentor.rank)
        case .medicineApprentice: return mentor.rank == .medicineCat
        default: return false
        }
    }

    /// Picks a random valid mentor, preferring cats without an apprentice.
    @discardableResult
    static func assignMentor(to id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> UUID? {
        guard let apprentice = clan[id], apprentice.mentor == nil || !canMentor(clan[apprentice.mentor], apprentice) else {
            return nil
        }
        removeMentor(from: id, in: &clan)
        let valid = clan.living.filter { canMentor($0, apprentice) }
        let free = valid.filter { $0.apprentices.isEmpty && !$0.isNotWorking }
        guard let mentor = (free.isEmpty ? valid : free).randomElement(using: &rng),
              let a = clan.index(of: id), let m = clan.index(of: mentor.id)
        else { return nil }
        clan.cats[a].mentor = mentor.id
        clan.cats[m].apprentices.append(id)
        return mentor.id
    }

    static func removeMentor(from id: UUID, in clan: inout Clan) {
        guard let a = clan.index(of: id), let mentorID = clan.cats[a].mentor else { return }
        clan.cats[a].mentor = nil
        clan.cats[a].formerMentors.append(mentorID)
        if let m = clan.index(of: mentorID) {
            clan.cats[m].apprentices.removeAll { $0 == id }
            clan.cats[m].formerApprentices.append(id)
        }
    }

    private func promoteDeputy(in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        if !clan.isAlive(clan.leader), !clan.isAlive(clan.deputy) {
            let warriors = clan.living.filter { $0.rank == .warrior }
            if let heir = warriors.randomElement(using: &rng) {
                let oldName = factory.names.display(heir.name, rank: heir.rank)
                setRank(.leader, for: heir.id, in: &clan, using: &rng)
                clan.leader = heir.id
                crownLeader(heir.id, in: &clan, using: &rng)
                return [.becameLeader(heir.id, oldName: oldName)] + promoteDeputy(in: &clan, using: &rng)
            }
        }
        guard !clan.isAlive(clan.deputy) || clan[clan.deputy]?.rank != .deputy else { return [] }
        clan.deputy = nil
        let warriors = clan.living.filter { $0.rank == .warrior }
        let mentors = warriors.filter { !$0.apprentices.isEmpty || !$0.formerApprentices.isEmpty }
        guard let pick = (mentors.isEmpty ? warriors : mentors).randomElement(using: &rng) else {
            return [.noDeputy]
        }
        setRank(.deputy, for: pick.id, in: &clan, using: &rng)
        clan.deputy = pick.id
        return [.deputyAppointed(pick.id)]
    }

    // MARK: - Mates and kits

    private func canHaveKits(_ cat: Cat?, in clan: Clan) -> Bool {
        guard let cat, cat.isAlive, !cat.isNotWorking, cat.birthCooldown == 0, cat.moons >= 15, cat.isMateAge else { return false }
        return Self.canHaveKits.contains(cat.rank) && clan.pregnancies[cat.id] == nil
    }

    private func pregnancy(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let i = clan.index(of: id) else { return [] }

        if var record = clan.pregnancies[id] {
            let mother = clan.cats[i]
            if record.moons == 1 {
                let weights = Self.litterWeights[mother.age] ?? Self.litterWeights[.adult]!
                record.litterSize = max(1, weighted(Array(zip(1...6, weights)), &rng))
                clan.pregnancies[id] = record
                return []
            }
            guard record.moons >= 2 else { return [] }
            clan.pregnancies[id] = nil
            clan.cats[i].birthCooldown = 6
            guard let father = clan[record.otherParent] else { return [] }

            var kits: [Cat] = []
            var usedPrefixes = Set<String>()
            for _ in 0..<record.litterSize {
                var kit = factory.makeKit(mother: mother, father: father, using: &rng)
                for _ in 0..<10 where usedPrefixes.contains(kit.name.prefix) {
                    kit.name = factory.names.generate(for: kit.appearance, using: &rng)
                }
                usedPrefixes.insert(kit.name.prefix)
                kits.append(kit)
            }
            clan.cats += kits
            relationships?.initializeKits(kits.map(\.id), parents: [id, father.id], in: &clan, using: &rng)
            for kit in kits { rollCongenital(for: kit.id, in: &clan, using: &rng) }
            var events: [MoonEvent] = [.born(mother: id, father: father.id, kits: kits.map(\.id))]
            if oneIn(40, &rng) { events += loseLifeOrDie(id, cause: .childbirth, in: &clan, using: &rng) }
            return events
        }

        if clan.cats[i].birthCooldown > 0 {
            clan.cats[i].birthCooldown -= 1
            return []
        }

        let cat = clan.cats[i]
        guard cat.sex == .female, canHaveKits(cat, in: clan) else { return [] }
        let partners = cat.mates.compactMap { clan[$0] }.filter { $0.sex == .male && canHaveKits($0, in: clan) }
        guard let father = partners.randomElement(using: &rng) else { return [] }

        let size = clan.living.count
        var odds = 39.0
        if size < 10 { odds = (odds * 0.5).rounded(.down) }
        if size > 30 { odds = (odds * Double(size) / 30).rounded(.down) }
        let children = clan.cats.filter { $0.parents.contains(id) }.count
        odds += (odds * Double(children) * 0.1).rounded(.down)
        guard oneIn(Int(odds), &rng) else { return [] }

        clan.pregnancies[id] = Pregnancy(otherParent: father.id)
        return [.expecting(mother: id)]
    }

    // MARK: - New cats

    private func invite(by id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent]? {
        guard let cat = clan[id], !cat.rank.isBaby else { return nil }
        let size = clan.living.filter { $0.id != clan.leader }.count
        let base = size < 10 ? 200 : size < 30 ? 300 : 700
        let chance = clan.reputation > 70 ? base - clan.reputation : base
        guard oneIn(chance, &rng) else { return nil }

        let kind = weighted([("loner", 40), ("kittypet", 30), ("rogue", 15), ("litter", 15)], &rng)
        if kind == "litter" {
            let count = weighted([(2, 5), (3, 4), (4, 1), (5, 1)], &rng)
            let moons = Int.random(in: 1...5, using: &rng)
            let kits = (0..<count).map { _ in factory.make(rank: .kitten, moons: moons, origin: .loner, using: &rng) }
            clan.cats += kits
            for kit in kits { rollCongenital(for: kit.id, odds: 8, in: &clan, using: &rng) }
            return [.litterFound(kits.map(\.id), foundBy: id)]
        }
        let origin: Cat.Origin = kind == "kittypet" ? .kittypet : kind == "rogue" ? .rogue : .loner
        let joiner = factory.makeJoiner(origin: origin, using: &rng)
        clan.cats.append(joiner)
        rollCongenital(for: joiner.id, odds: 100, in: &clan, using: &rng)
        return [.joined(joiner.id, foundBy: id)]
    }

    // MARK: - Death

    private func deathRolls(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id], cat.isAlive else { return [] }
        let badWar = clan.war.isGoingBadly
        if clan.leader == id, !cat.isNotWorking, oneIn(badWar ? 15 : 50, &rng) {
            return die(id, cause: .misfortune, in: &clan, using: &rng)
        }
        let oldAge = pow(1.0045, Double(cat.moons - 150)) - 1
        if cat.moons >= 300 || (oldAge > 0 && Double.random(in: 0..<1, using: &rng) <= oldAge) {
            return die(id, cause: .oldAge, in: &clan, using: &rng)
        }
        if !cat.isNotWorking, oneIn(badWar ? 170 : 500, &rng) {
            return die(id, cause: .misfortune, in: &clan, using: &rng)
        }
        return rollInjury(for: id, in: &clan, using: &rng)
    }

    /// Picks a Clangen death event for the cat if one fits, otherwise a plain death.
    private func die(_ id: UUID, cause: DeathCause, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        var counts: [UUID: Int] = [:]
        guard let cat = clan[id],
              var pick = library?.deathEvent(for: cat, oldAge: cause == .oldAge, in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
              pick.deaths.contains(id),
              addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) != nil
        else { return loseLifeOrDie(id, cause: cause, history: cause == .oldAge ? "m_c died of old age." : nil, in: &clan, using: &rng) }

        relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
        applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
        applyEventEffects(pick, in: &clan, using: &rng)
        var events: [MoonEvent] = [.story(pick, .death)]
        for victim in pick.deaths {
            let lives: Int = if victim != clan.leader {
                1
            } else {
                switch pick.livesLost {
                case .one: 1
                case .all: clan.leaderLives
                case .some: clan.leaderLives > 3 ? Int.random(in: 2..<(clan.leaderLives - 1), using: &rng) : 1
                }
            }
            if victim == clan.leader {
                clan.leaderLives -= lives - 1
                if let i = clan.index(of: victim) {
                    clan.cats[i].deaths += Array(repeating: DeathRecord(text: DeathRecord.multiLives, moon: clan.age), count: lives - 1)
                }
            }
            let (history, involved) = pick.deathHistory(for: victim)
            let outcome = loseLifeOrDie(victim, cause: cause, history: history, involved: involved, in: &clan, using: &rng)
            events += outcome.filter { if case .died = $0 { false } else { true } }
        }
        return events
    }

    /// Leaders lose one of their lives instead of dying, until the last one.
    /// - Parameters:
    ///   - history: Clangen death-history text, with `m_c` for this cat and `r_c` for `involved`.
    func loseLifeOrDie(
        _ id: UUID, cause: DeathCause, history: String? = nil, involved: UUID? = nil,
        in clan: inout Clan, using rng: inout some RandomNumberGenerator
    ) -> [MoonEvent] {
        guard let i = clan.index(of: id) else { return [] }
        clan.cats[i].conditions.removeAll { $0.kind != .permanent }
        let history = history ?? Self.defaultHistory[cause]
        if clan.leader == id {
            clan.leaderLives -= 1
            if clan.leaderLives > 0 {
                clan.cats[i].deaths.append(DeathRecord(text: history ?? "m_c lost a life.", involved: involved, moon: clan.age))
                return [.leaderLostLife(id, livesLeft: clan.leaderLives)]
            }
        }
        clan.sendToAfterlife(id, history: history, involved: involved, using: &rng)
        clan.pregnancies[id] = nil
        Self.removeMentor(from: id, in: &clan)
        for apprentice in clan.cats[i].apprentices {
            Self.removeMentor(from: apprentice, in: &clan)
            Self.assignMentor(to: apprentice, in: &clan, using: &rng)
        }
        if clan.leader == id { clan.leaderLives = 0 }
        return [.died(id, cause)]
    }

    /// Death history used when no event supplies one.
    static let defaultHistory: [DeathCause: String] = [
        .oldAge: "m_c died of old age.",
        .childbirth: "m_c died while kitting.",
    ]
}
