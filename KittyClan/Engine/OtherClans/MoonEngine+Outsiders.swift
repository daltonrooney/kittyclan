import Foundation

/// Clangen's outsiders: loners, rogues and kittypets near the Clan, lost and exiled cats, and cats who arrive.
extension MoonEngine {
    // MARK: - Leaving and returning

    /// Clangen's `become_lost`: the cat leaves the Clan as a loner or kittypet and may find its way home.
    func loseCat(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard var cat = removeFromClan(id, in: &clan, using: &rng) else { return }
        cat.isLost = true
        cat.origin = pick([.kittypet, .loner], &rng)
        cat.nextThought = .onLost
        clan.outsiders.append(cat)
    }

    /// Clangen's `exile_cat`: the cat leaves as a loner and can only come back if invited from the leader's den.
    func exileCat(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard var cat = removeFromClan(id, in: &clan, using: &rng) else { return }
        cat.isExiled = true
        cat.origin = .loner
        cat.nextThought = .onExile
        clan.outsiders.append(cat)
    }

    private func removeFromClan(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> Cat? {
        guard clan.isAlive(id) else { return nil }
        Self.removeMentor(from: id, in: &clan)
        for apprentice in clan[id]?.apprentices ?? [] {
            Self.removeMentor(from: apprentice, in: &clan)
            Self.assignMentor(to: apprentice, in: &clan, using: &rng)
        }
        guard let index = clan.index(of: id) else { return nil }
        var cat = clan.cats.remove(at: index)
        cat.lastClanRank = cat.rank
        if cat.otherClan != nil { cat.leftOtherClan = true }
        // Outsiders have no Clan rank, so their names lose "-kit", "-paw" and "-star" endings.
        cat.rank = .warrior
        if clan.leader == id { clan.leader = nil }
        if clan.deputy == id { clan.deputy = nil }
        clan.pregnancies[id] = nil
        return cat
    }

    /// Brings an outsider into the Clan, restoring a former Clan cat's rank, with their young kits.
    @discardableResult
    func welcomeBack(_ id: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [UUID] {
        guard let index = clan.outsiders.firstIndex(where: { $0.id == id }) else { return [] }
        var cat = clan.outsiders.remove(at: index)
        cat.rank = Self.returningRank(for: cat)
        cat.isLost = false
        cat.isExiled = false
        cat.isNear = true
        if cat.otherClan != nil { cat.leftOtherClan = true }
        clan.cats.append(cat)
        var joined = [id]
        let kits = clan.outsiders.filter { $0.isAlive && !$0.isExiled && $0.moons < 12 && $0.allParents.contains(id) }.map(\.id)
        for kit in kits {
            guard let k = clan.outsiders.firstIndex(where: { $0.id == kit }) else { continue }
            var child = clan.outsiders.remove(at: k)
            child.rank = Self.returningRank(for: child)
            child.isLost = false
            clan.cats.append(child)
            joined.append(kit)
        }
        for member in joined {
            if clan[member]?.rank.isApprentice == true { Self.assignMentor(to: member, in: &clan, using: &rng) }
            if clan.relationships[member] == nil {
                _ = relationships?.welcome(member, in: &clan, counts: &counts, using: &rng)
            }
        }
        return joined
    }

    /// Clangen's rank on (re)joining: a former rank if they had one, else one fitting their age,
    /// with Clangen's catch-up ceremonies for kits and apprentices who grew up outside.
    static func returningRank(for cat: Cat) -> Rank {
        var rank: Rank
        if let last = cat.lastClanRank {
            rank = switch last {
            case .leader, .deputy: cat.age == .senior ? .elder : .warrior
            case .newborn where cat.moons > 0: .kitten
            default: last
            }
        } else {
            rank = switch cat.age {
            case .newborn: .newborn
            case .kitten: .kitten
            case .adolescent: .apprentice
            case .senior: .elder
            default: .warrior
            }
        }
        if rank.isApprentice || rank.isBaby {
            if cat.moons >= 15 { rank = [.medicineApprentice: .medicineCat, .mediatorApprentice: .mediator][rank] ?? .warrior }
            else if !rank.isApprentice, cat.moons >= 6 { rank = .apprentice }
        }
        return rank
    }

    /// Clangen's `handle_lost_cats_return`: one lost cat may find its way home (1 in 20 each moon).
    func lostCatReturns(in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard oneIn(20, &rng), let cat = clan.outsiders.filter({ $0.isAlive && $0.isLost }).randomElement(using: &rng),
              !cat.rank.isBaby, cat.age != .newborn, cat.age != .kitten
        else { return [] }
        let parentName = cat.parents.first.flatMap { clan[$0] }.map { factory.names.display($0.name, rank: $0.rank) }
        let joined = welcomeBack(cat.id, in: &clan, counts: &counts, using: &rng)
        var text = cat.isFormerClanCat || parentName == nil
            ? pick([
                "After a long journey, m_c has finally returned home to c_n.",
                "m_c was found at the border, tired but happy to be home.",
                "m_c strides into camp, much to everyone's surprise. {PRONOUN/m_c/subject/CAP}{VERB/m_c/'re/'s} home!",
                "{PRONOUN/m_c/subject/CAP} met so many friends on {PRONOUN/m_c/poss} journey, but c_n is where m_c truly belongs. With a tearful goodbye, {PRONOUN/m_c/subject} {VERB/m_c/return/returns} home.",
            ], &rng)
            : "m_c approaches the Clan and asks to join, claiming to be \(parentName!)'s kitten."
        if joined.count == 2 { text += " {PRONOUN/m_c/subject/CAP} {VERB/m_c/bring/brings} along {PRONOUN/m_c/poss} kitten." }
        if joined.count > 2 { text += " {PRONOUN/m_c/subject/CAP} {VERB/m_c/bring/brings} along {PRONOUN/m_c/poss} kittens." }
        var pick = StoryPick(template: text, cats: ["m_c": cat.id])
        pick.groupCats = ["kits": Array(joined.dropFirst())]
        return [.story(pick, .join)]
    }

    // MARK: - Outsiders' moons

    /// Clangen's `one_moon_outside_cat`: outsiders age, learn and sometimes die (1 in 64).
    func outsiderMoon(in clan: inout Clan, skipping protected: UUID?, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        var events: [MoonEvent] = []
        for i in clan.outsiders.indices where clan.outsiders[i].isAlive {
            var cat = clan.outsiders[i]
            cat.moons += 1
            factory.traits.setKit(cat.age == .newborn || cat.age == .kitten, &cat.personality, using: &rng)
            if cat.age != .kitten, !(cat.isNotWorking && Int.random(in: 0..<3, using: &rng) != 0) {
                let pool = switch cat.age {
                case .adolescent: Array(2...10) + [4, 5]
                case .senior: Array(3...9) + [3, 4]
                default: Array(4...12) + [6, 7]
                }
                var gain = Double(pick(pool, &rng) + (clan.preyAndHerbs ? 0 : Int.random(in: 0...3, using: &rng)))
                if cat.social == .kittypet { gain *= 0.6 }
                cat.experience = min(321, cat.experience + max(Int(gain), 1))
            }
            if cat.age != .kitten, cat.age != .adolescent {
                cat.skills.primary?.interestOnly = false
                cat.skills.secondary?.interestOnly = false
            }
            if cat.belongsToOtherClan { Self.promoteOtherClanCat(&cat) }
            clan.outsiders[i] = cat

            guard cat.id != protected, Int.random(in: 0..<64, using: &rng) == 1 else { continue }
            let otherClanName = cat.otherClan.flatMap { clan.otherClan($0)?.name }
            let key: String
            if cat.isExiled { key = "exiled" }
            else if cat.isLost { key = "lost" }
            else if otherClanName != nil, cat.belongsToOtherClan || cat.leftOtherClan && !cat.isFormerClanCat { key = "other_clan" }
            else { key = cat.social.rawValue }
            var line = library.flatMap { ($0.outsiderDeaths[key] ?? $0.outsiderDeaths["default"])?.randomElement(using: &rng) }
            if let name = otherClanName { line = line?.replacingOccurrences(of: "o_c_n", with: name) }
            clan.sendToAfterlife(cat.id, history: line, using: &rng)
            guard cat.isNear, let line else { continue }
            events.append(.story(StoryPick(template: line, cats: ["m_c": cat.id]), .death))
        }
        return events
    }

    /// Clangen's rudimentary rank changes for other Clans' cats: apprentices at 6 moons, full members at 12.
    static func promoteOtherClanCat(_ cat: inout Cat) {
        if cat.rank.isBaby, cat.moons >= 6 { cat.rank = .apprentice }
        if cat.moons >= 12 {
            switch cat.rank {
            case .apprentice: cat.rank = .warrior
            case .medicineApprentice: cat.rank = .medicineCat
            case .mediatorApprentice: cat.rank = .mediator
            default: break
            }
        }
    }

    // MARK: - New cats

    /// Clangen's `invite_new_cats` odds for one cat: better with a welcoming reputation, worse when hostile.
    static func inviteChance(in clan: Clan) -> Int {
        let size = clan.living.filter { $0.id != clan.leader }.count
        let base = size < 10 ? 200 : size < 30 ? 300 : 700
        let rep = clan.reputation
        let chance: Int = switch rep {
        case ...30: size < 10 ? base : base + 300 / max(rep / 2, 1)
        case ...70: size < 10 ? base - rep : base
        default: base - rep
        }
        return max(chance, 1)
    }

    /// A Clangen new-cat event led by this cat, creating the cats it describes.
    func newCatEvent(by id: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent]? {
        guard let cat = clan[id], !cat.rank.isBaby, oneIn(Self.inviteChance(in: clan), &rng),
              var pick = library?.newCatEvent(for: cat, in: clan, context: eventContext(for: clan, using: &rng), using: &rng)
        else { return nil }

        guard let joined = addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) else { return nil }
        relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
        applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
        applyEventEffects(pick, in: &clan, using: &rng)
        return [.story(pick, joined ? .join : .info)]
    }

    /// Creates the cats an event's `new_cat` blocks describe and adds Clangen's notices to its text.
    /// Returns whether any joined the Clan, or nil when the event needed cats and none were made.
    @discardableResult
    func addNewCats(to pick: inout StoryPick, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> Bool? {
        guard !pick.newCats.isEmpty else { return false }
        var created: [[UUID]] = []
        var suffixes: [String] = []
        var joinedAny = false
        for (i, attributes) in pick.newCats.enumerated() {
            let (ids, joined) = createNewCats(attributes, earlier: created, event: pick, in: &clan, using: &rng)
            created.append(ids)
            guard let first = ids.first else { continue }
            pick.groupCats["n_c:\(i)"] = ids
            pick.cats["n_c:\(i)"] = first
            joinedAny = joinedAny || joined
            let key = "n_c:\(i)"
            if clan[first]?.isDead == true {
                suffixes.append("\(key)'s ghost now wanders.")
            } else if !joined, !pick.hiddenNewCats.contains(key) {
                suffixes.append("The Clan has encountered \(key).")
            }
            if joined {
                for member in ids {
                    _ = relationships?.welcome(member, in: &clan, counts: &counts, using: &rng)
                }
            }
        }
        guard !created.flatMap({ $0 }).isEmpty else { return nil }
        if !suffixes.isEmpty { pick.template += " " + suffixes.joined(separator: " ") }
        return joinedAny
    }
    /// Clangen's `create_new_cat_block`.
    private func createNewCats(_ attributes: [String], earlier: [[UUID]], event: StoryPick, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> (ids: [UUID], joined: Bool) {
        func value(_ prefix: String) -> String? {
            attributes.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        func resolve(_ reference: String) -> UUID? {
            if let index = Int(reference) { return earlier.indices.contains(index) ? earlier[index].first : nil }
            if reference.hasPrefix("n_c:"), let index = Int(reference.dropFirst(4)) { return earlier.indices.contains(index) ? earlier[index].first : nil }
            return event.cats[reference]
        }

        let meeting = attributes.contains("meeting")
        let dead = attributes.contains("dead")
        let blood = value("parent:")?.split(separator: ",").compactMap { resolve(String($0).trimmingCharacters(in: .whitespaces)) } ?? []
        var adoptive: [UUID] = []
        for reference in value("adoptive:")?.split(separator: ",") ?? [] {
            guard let parent = resolve(String(reference).trimmingCharacters(in: .whitespaces)), !adoptive.contains(parent) else { continue }
            adoptive.append(parent)
            for mate in clan[parent]?.mates ?? [] where clan.isAlive(mate) && !adoptive.contains(mate) { adoptive.append(mate) }
        }
        adoptive.removeAll(where: blood.contains)
        let mates = value("mate:")?.split(separator: ",").compactMap { resolve(String($0).trimmingCharacters(in: .whitespaces)) } ?? []

        var rank = value("status:").flatMap(Rank.init)
        var moons: Int?
        if let age = value("age:") {
            if age == "has_kits" { moons = Int.random(in: 19...120, using: &rng) }
            else if age == "mate", let mate = mates.first.flatMap({ clan[$0] }) {
                let range = mate.age.moons
                moons = Int.random(in: range.lowerBound...min(range.upperBound, 300), using: &rng)
            } else if let catAge = CatAge(rawValue: age) {
                moons = Int.random(in: catAge.moons.lowerBound...min(catAge.moons.upperBound, 300), using: &rng)
            }
        }
        let litter = attributes.contains("litter")
        if litter, rank?.isBaby != true { rank = .kitten }

        let backstories = Backstories.bundled
        var group: UUID?
        var social: NewCatSocial
        if attributes.contains("kittypet") { social = .kittypet }
        else if attributes.contains("rogue") { social = .rogue }
        else if attributes.contains("loner") { social = .loner }
        else if attributes.contains("clancat") || attributes.contains("former clancat") {
            social = attributes.contains("former clancat") ? .formerClancat : .clancat
            group = event.otherClan ?? clan.otherClans.randomElement(using: &rng)?.id
        } else if let parent = blood.first.flatMap({ clan[$0] }) {
            let isOutsider = clan.outsiders.contains { $0.id == parent.id }
            social = !isOutsider || parent.belongsToOtherClan ? .clancat : NewCatSocial(rawValue: parent.social.rawValue) ?? .loner
            if isOutsider, parent.belongsToOtherClan { group = parent.otherClan }
        } else {
            social = pick([.kittypet, .loner, .formerClancat], &rng)
        }

        var backstory: String
        if rank?.isBaby == true {
            backstory = backstories.random(from: "abandoned_backstories", using: &rng) ?? "abandoned1"
        } else if rank == .medicineCat {
            backstory = social == .clancat ? pick(["medicine_cat", "disgraced1"], &rng) : pick(["wandering_healer1", "wandering_healer2"], &rng)
        } else {
            let kind = social == .clancat || social == .formerClancat ? "former_clancat" : social.rawValue
            backstory = backstories.random(from: kind + "_backstories", using: &rng) ?? "outsider1"
        }
        let listed = value("backstory:").flatMap { backstories.expand($0.split(separator: ",").map(String.init)) }?.sorted() ?? []
        if let story = listed.randomElement(using: &rng) {
            backstory = story
            switch backstories.social(of: story) {
            case .clancat?: if social != .formerClancat { social = .clancat }
            case let other?: social = other
            case nil: break
            }
        }
        if meeting, let moons, moons <= 6, listed.isEmpty { backstory = "outsider1" }

        let sex: Cat.Sex? = attributes.contains("male") ? .male : (attributes.contains("female") || attributes.contains("can_birth")) ? .female : nil
        if attributes.contains("exists"),
           let existing = clan.outsiders.first(where: { other in
               other.isAlive && other.isNear && !other.isExiled && !other.belongsToOtherClan && social.origin == other.social
                   && (listed.isEmpty || other.backstory.map(listed.contains) == true)
                   && (sex == nil || other.sex == sex) && (moons.map { CatAge(moons: $0) == other.age } ?? true)
                   && !earlier.flatMap({ $0 }).contains(other.id)
           }) {
            if dead {
                clan.sendToAfterlife(existing.id, history: nil, using: &rng)
                return ([existing.id], false)
            }
            if meeting { return ([existing.id], false) }
            var counts: [UUID: Int] = [:]
            if let rank, let i = clan.outsiders.firstIndex(where: { $0.id == existing.id }) { clan.outsiders[i].lastClanRank = rank }
            return (welcomeBack(existing.id, in: &clan, counts: &counts, using: &rng), true)
        }

        if group == nil, social == .formerClancat || backstories.isFromOtherClan(backstory) {
            group = clan.otherClans.randomElement(using: &rng)?.id
        }
        let count = litter ? weighted([(2, 5), (3, 4), (4, 1), (5, 1)], &rng) : 1
        let litterMoons = litter ? (rank == .newborn ? 0 : Int.random(in: 1...5, using: &rng)) : nil
        var ids: [UUID] = []
        let joins = !meeting && !dead
        for _ in 0..<count {
            let finalRank = rank ?? (moons.map { CatAge(moons: $0) }.map(Self.rankForAge) ?? .warrior)
            let origin: Cat.Origin = switch social {
            case .formerClancat: pick([.kittypet, .loner, .rogue], &rng)
            case .clancat: group == nil ? .loner : .clanborn
            default: social.origin ?? .loner
            }
            var cat = factory.make(rank: finalRank, moons: litterMoons ?? moons, origin: origin, sex: sex, using: &rng)
            cat.backstory = backstory
            cat.otherClan = group
            cat.leftOtherClan = group != nil && (joins || social != .clancat)
            cat.parents = blood
            cat.adoptiveParents = adoptive
            let baby = cat.moons < 12
            let keepsOldName = attributes.contains("old_name") || (!attributes.contains("new_name") && Bool.random(using: &rng))
            if group == nil, !(baby && joins), !joins || keepsOldName {
                cat.name = factory.names.outsiderName(for: origin, using: &rng)
            }
            if !(baby && joins) { factory.maybeCollar(&cat, using: &rng) }
            if dead {
                cat.enterAfterlife(clan.afterlife(for: cat, isOutsider: !joins), moon: clan.age, using: &rng)
            }
            if joins {
                cat.rank = finalRank
                if cat.rank.isApprentice {
                    cat.skills.primary?.interestOnly = true
                    cat.skills.secondary?.interestOnly = true
                }
                if cat.isAlive { cat.nextThought = .onJoin }
                clan.cats.append(cat)
                if cat.rank.isApprentice { Self.assignMentor(to: cat.id, in: &clan, using: &rng) }
            } else {
                if cat.isAlive { cat.nextThought = .onMeeting }
                clan.outsiders.append(cat)
            }
            ids.append(cat.id)
        }
        for mate in mates { relationships?.setMates(ids[0], mate, in: &clan) }
        if joins, !(blood + adoptive).isEmpty {
            relationships?.initializeKits(ids, parents: (blood + adoptive).filter { clan.isAlive($0) }, in: &clan, using: &rng)
        }
        return (ids, joins)
    }

    static func rankForAge(_ age: CatAge) -> Rank {
        switch age {
        case .newborn: .newborn
        case .kitten: .kitten
        case .adolescent: .apprentice
        case .senior: .elder
        default: .warrior
        }
    }

    // MARK: - Leader's den

    /// Clangen's outsider roll: likelier with a good reputation; searching for a lost cat is harder.
    static func outsiderDenSucceeds(_ interaction: String, reputation: Int, using rng: inout some RandomNumberGenerator) -> Bool {
        var chance = Double(reputation) / 100 / 1.5 / 1.2
        if interaction == "search" { chance /= 2 }
        return Double.random(in: 0..<1, using: &rng) < max(chance, 0.1)
    }

    func resolveOutsiderDen(_ plan: LeaderDenPlan, outsider: UUID, actor: Cat, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let target = clan.outsiders.first(where: { $0.id == outsider }), target.isAlive, let den = library?.leaderDen else { return [] }
        let options = (plan.succeeded ? den.outsiderSuccess : den.outsiderFail).filter { outcome in
            outcome.interaction == plan.interaction
                && (outcome.reputation.contains("any") || outcome.reputation.contains(clan.reputationStanding))
                && Self.outsiderMatches(outcome.main, target)
        }
        guard let outcome = options.randomElement(using: &rng) else { return [] }
        clan.changeReputation(by: outcome.change)

        var joined: [UUID] = []
        if plan.succeeded, let i = clan.outsiders.firstIndex(where: { $0.id == outsider }) {
            switch plan.interaction {
            case "hunt":
                clan.sendToAfterlife(outsider, history: "m_c was hunted down by c_n.", using: &rng)
                _ = i
            case "drive":
                clan.outsiders[i].isNear = false
            default:
                let wasExiled = target.isExiled
                var counts: [UUID: Int] = [:]
                joined = welcomeBack(outsider, in: &clan, counts: &counts, using: &rng)
                for id in joined where !wasExiled || id != outsider {
                    guard let j = clan.index(of: id), let story = clan.cats[j].backstory else { continue }
                    if story.contains("guided") {
                        clan.cats[j].backstory = "outsider1"
                    } else if Backstories.bundled.contains(story, in: "healer_backstories"), !clan.cats[j].rank.isBaby {
                        clan.cats[j].rank = .medicineCat
                    }
                }
            }
        }
        var text = outcome.text
        if joined.count == 2 { text += " {PRONOUN/m_c/subject/CAP} {VERB/m_c/bring/brings} along {PRONOUN/m_c/poss} kitten." }
        if joined.count > 2 { text += " {PRONOUN/m_c/subject/CAP} {VERB/m_c/bring/brings} along {PRONOUN/m_c/poss} kittens." }
        return [.story(StoryPick(template: text, cats: ["m_c": outsider]), joined.isEmpty ? .info : .join)]
    }

    /// Leader's den outcome filters for outsiders, matching "exiled", "lost" and "former Clancat" too.
    private static func outsiderMatches(_ constraint: Constraint?, _ cat: Cat) -> Bool {
        guard var constraint else { return true }
        if let statuses = constraint.statuses {
            let fits = statuses.contains(cat.social.rawValue)
                || (cat.isLost && statuses.contains("lost"))
                || (cat.isExiled && statuses.contains("exiled"))
                || (cat.isFormerClanCat && statuses.contains("former Clancat"))
            guard fits else { return false }
            constraint.statuses = nil
        }
        return constraint.matches(cat)
    }

    /// Outsiders the leader's den can act on: living, still nearby, and known to the Clan.
    static func denOutsiders(in clan: Clan) -> [Cat] {
        clan.outsiders.filter { $0.isAlive && $0.isNear && !$0.belongsToOtherClan }
    }

    /// The leader's den choices for an outsider: hunt down, drive off, and invite in (search for, if lost).
    static func outsiderActions(for cat: Cat) -> [String] {
        cat.age == .newborn ? [] : ["hunt", "drive", cat.isLost ? "search" : "invite"]
    }

    /// Records this moon's leader's den choice, rolling its success now as Clangen does.
    func planLeaderDen(_ interaction: String, target: LeaderDenPlan.Target, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let actor = Self.leaderDenActor(in: clan) else { return }
        if case .outsider = target, !clan.isAlive(clan.leader) { return }
        let player = Self.temperament(of: clan)
        let succeeded: Bool = switch target {
        case .clan(let id):
            Self.leaderDenSucceeds(player: player, other: clan.otherClan(id)?.temperament ?? player, byLeader: actor.id == clan.leader, using: &rng)
        case .outsider:
            Self.outsiderDenSucceeds(interaction, reputation: clan.reputation, using: &rng)
        }
        let plan = LeaderDenPlan(target: target, interaction: interaction, actor: actor.id, succeeded: succeeded, playerTemperament: player)
        if case .clan = target { clan.leaderDenPlan = plan } else { clan.outsiderDenPlan = plan }
    }
}
