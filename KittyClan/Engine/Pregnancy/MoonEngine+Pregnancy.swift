import Foundation

/// Clangen's pregnancy events (`events_module/pregnancy`): who has kits with whom, the
/// `pregnant` and `recovering from birth` conditions, and births.
extension MoonEngine {
    static let canHaveKits: Set<Rank> = [.leader, .deputy, .medicineCat, .mediator, .warrior, .elder]
    /// Clangen's `one_kit_possibility` … `max_kit_possibility`: weights for litters of 1 to 6.
    static let litterWeights: [CatAge: [Int]] = [
        .youngAdult: [8, 10, 17, 12, 6, 2],
        .adult: [9, 13, 15, 8, 2, 0],
        .seniorAdult: [10, 15, 5, 2, 0, 0],
        .senior: [4, 3, 1, 0, 0, 0],
    ]
    static let birthCooldown = 6

    // MARK: - Each moon

    /// Clangen's `handle_having_kits`: moves a pregnancy along, or rolls for new kits.
    func pregnancy(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let i = clan.index(of: id) else { return [] }
        if let record = clan.pregnancies[id] {
            if record.moons == 1 { return pregnancyMoonOne(id, in: &clan, using: &rng) }
            if record.moons >= 2 { return giveBirth(id, in: &clan, using: &rng) }
            return []
        }
        guard !clan.cats[i].isNotWorking else { return [] }
        if clan.cats[i].birthCooldown > 0 { clan.cats[i].birthCooldown -= 1 }

        let cat = clan.cats[i]
        guard canHaveKits(cat, in: clan) else { return [] }
        let (partner, isAffair) = secondParent(for: cat, in: clan, using: &rng)
        if partner == nil, !clan.singleParentage { return [] }
        var adopt = false
        if let partner {
            guard canHaveKits(partner, in: clan) else { return [] }
            if partner.sex == cat.sex, !clan.sameSexBirth {
                guard clan.sameSexAdoption else { return [] }
                adopt = true
            }
        }
        guard oneIn(kitChance(cat, partner, isAffair: isAffair, in: clan), &rng) else { return [] }
        if adopt, let partner { return adoptLitter(by: id, with: partner.id, in: &clan, using: &rng) }
        return conceive(id, with: partner?.id, in: &clan, using: &rng)
    }

    /// Clangen's `check_if_can_have_kits`, including `check_parent_rank`.
    func canHaveKits(_ cat: Cat?, in clan: Clan) -> Bool {
        guard let cat, clan.isAlive(cat.id), cat.birthCooldown == 0, !cat.has("recovering from birth"),
              cat.moons >= 15, cat.isMateAge
        else { return false }
        let rankAllows = Self.canHaveKits.contains(cat.rank)
            || cat.mates.contains { clan[$0].map { Self.canHaveKits.contains($0.rank) } ?? false }
        guard rankAllows else { return false }
        return !cat.mates.isEmpty || clan.singleParentage || clan.unmatedParentage || clan.affairs
    }

    // MARK: - The second parent

    /// Clangen's `get_second_parent`: usually a mate, but with `affair` or `unmated parentage`
    /// on, a cat the parent loves (or a random fling). Returns whether it's an affair.
    ///
    /// Clangen lets a cat whose mates are all the same sex have an affair even with `affair`
    /// off; here a mated cat only strays when affairs are allowed.
    func secondParent(for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> (Cat?, isAffair: Bool) {
        var mate: Cat?
        if !cat.mates.isEmpty {
            let mates = cat.mates.compactMap { clan[$0] }
            mate = (clan.sameSexBirth ? mates : mates.filter { $0.sex != cat.sex }).randomElement(using: &rng)
            if !clan.affairs { return (mate, false) }
        } else if !clan.unmatedParentage {
            return (nil, false)
        }

        if let partner = romanticPartner(for: cat, mate: mate, in: clan, using: &rng) { return (partner, true) }

        var chance = cat.mates.isEmpty ? 10 : 50
        let biggest = clan.biggestFamily
        if clan.isBig(family: biggest), !biggest.contains(cat.id) { chance = Int(Double(chance) * 0.8) }
        guard oneIn(chance, &rng) else { return (mate, false) }
        let flings = clan.living.filter { other in
            clan.isPotentialMate(other, cat, forLoveInterest: true)
                && (clan.sameSexBirth || other.sex != cat.sex)
                && !cat.mates.contains(other.id)
                && (clan.relationship(from: cat.id, to: other.id).map { $0[.like] > -20 } ?? false)
                && (clan.relationship(from: other.id, to: cat.id)?[.like] ?? 0) > -20
        }
        if let fling = flings.randomElement(using: &rng) { return (fling, true) }
        return (mate, false)
    }

    /// Clangen's `_determine_highest_romantic_relation`: the cat this one loves most may father
    /// kits, likelier the more they're loved compared with the mate.
    private func romanticPartner(for cat: Cat, mate: Cat?, in clan: Clan, using rng: inout some RandomNumberGenerator) -> Cat? {
        var best: (cat: Cat, romance: Int)?
        for other in clan.cats {
            guard let romance = clan.relationship(from: cat.id, to: other.id)?[.romance], romance > (best?.romance ?? 0),
                  !other.mates.contains(cat.id), clan.isPotentialMate(other, cat, forLoveInterest: true)
            else { continue }
            best = (other, romance)
        }
        guard let partner = best?.cat else { return nil }
        let chance = if let mate {
            Self.loveAffairChance(mateLove: averageRomance(cat.id, mate.id, in: clan), affairLove: averageRomance(cat.id, partner.id, in: clan))
        } else {
            Self.coparentingChance(averageRomance(cat.id, partner.id, in: clan))
        }
        guard chance == 0 || oneIn(chance, &rng) else { return nil }
        return clan.sameSexBirth || partner.sex != cat.sex ? partner : nil
    }

    private func averageRomance(_ a: UUID, _ b: UUID, in clan: Clan) -> Double {
        Double((clan.relationship(from: a, to: b)?[.romance] ?? 0) + (clan.relationship(from: b, to: a)?[.romance] ?? 0)) / 2
    }

    /// Clangen's `_get_love_affair_chance`, as a 1-in-N chance.
    static func loveAffairChance(mateLove: Double, affairLove: Double) -> Int {
        let difference = mateLove - affairLove
        if difference < 0 {
            let gap = -difference
            return 10 - (gap > 30 ? 7 : gap > 20 ? 6 : gap > 15 ? 5 : gap > 10 ? 4 : 0)
        }
        if difference > 0 {
            return 30 + (difference > 30 ? 8 : difference > 20 ? 5 : difference > 15 ? 3 : difference > 10 ? 5 : 0)
        }
        return 15
    }

    /// Clangen's `_get_unmated_coparenting_chance`, as a 1-in-N chance.
    static func coparentingChance(_ love: Double) -> Int {
        15 - (love > 50 ? 12 : love > 40 ? 10 : love > 30 ? 7 : love > 10 ? 5 : 0)
    }

    /// Clangen's `get_balanced_kit_chance`, as a 1-in-N chance. Every cat who can have kits rolls each moon.
    func kitChance(_ first: Cat, _ second: Cat?, isAffair: Bool = false, in clan: Clan) -> Int {
        var odds = !first.mates.isEmpty && !isAffair ? 80 : 130
        if !clan.singleParentage || !clan.unmatedParentage { odds = Int(Double(odds) * 0.7) }
        if !clan.affairs { odds = Int(Double(odds) * 0.7) }
        let size = clan.living.count
        if size < 10 { odds = Int(Double(odds) * 0.5) } else if size > 30 { odds = Int(Double(odds) * Double(size) / 30) }
        if let second {
            switch RelationshipEngine.compatibility(first, second) {
            case .positive: odds = Int(Double(odds) * 0.85)
            case .negative: odds = Int(Double(odds) * 1.15)
            case .neutral: break
            }
            let there = clan.relationship(from: first.id, to: second.id), back = clan.relationship(from: second.id, to: first.id)
            for value in [RelationshipValue.romance, .comfort, .trust] {
                let average = Double((there?[value] ?? 0) + (back?[value] ?? 0)) / 2
                let cut = average >= 85 ? 0.3 : average >= 55 ? 0.2 : average >= 35 ? 0.1 : 0
                odds -= Int(Double(odds) * cut)
            }
        }
        if size > 0, clan.living.map(\.moons).reduce(0, +) / size > 80 { odds = Int(Double(odds) * 0.8) }
        odds += Int(Double(odds) * Double(clan.children(of: first.id).count) * 0.1)
        let biggest = clan.biggestFamily
        if biggest.count > 1, biggest.contains(first.id) || second.map({ biggest.contains($0.id) }) == true {
            odds = Int(Double(odds) * 1.7)
        }
        if Double(clan.relatives(of: first.id, cousins: !clan.firstCousinMates).count) < Double(size) / 15 {
            odds = Int(Double(odds) * 0.7)
        }
        if second == nil, !clan.singleParentage, clan.isBig(family: biggest) { odds = Int(Double(odds) * 0.9) }
        return max(1, odds)
    }

    // MARK: - Becoming pregnant

    /// Clangen's `handle_zero_moon_pregnant`: one of the pair becomes pregnant, or a single tom
    /// (or, with `same sex birth`, half of single cats) brings home a litter from nowhere.
    func conceive(_ id: UUID, with partnerID: UUID?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        let partner = clan[partnerID]
        if let partner, !clan.isAlive(partner.id) || partner.birthCooldown > 0 { return [] }
        if clan.pregnancies[id] != nil || partnerID.map({ clan.pregnancies[$0] != nil }) == true { return [] }

        let carrier: UUID, other: UUID?
        if clan.sameSexBirth {
            if partner == nil, Bool.random(using: &rng) { return secretKittens(id, in: &clan, using: &rng) }
            (carrier, other) = (id, partnerID)
        } else if partner == nil, cat.sex == .male {
            return secretKittens(id, in: &clan, using: &rng)
        } else if cat.sex == .male, let partner, partner.sex == .female {
            (carrier, other) = (partner.id, id)
        } else {
            (carrier, other) = (id, partnerID)
        }
        clan.pregnancies[carrier] = Pregnancy(otherParent: other)
        return pregnancyNotice(carrier, other: other, in: &clan, using: &rng)
    }

    /// Clangen's `_handle_pregnancy_notice`: the announcement, which may hint at an affair, and
    /// the `pregnant` condition (minor three times in four).
    private func pregnancyNotice(_ id: UUID, other: UUID?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        let mates = cat.mates.compactMap { clan[$0] }
        let femaleMates = mates.filter { $0.sex == .female }, maleMates = mates.filter { $0.sex != .female }
        var key = "announcement"
        var randomCat = other
        if let other, cat.mates.contains(other) {
            key = "announcement"
        } else if clan.unmatedParentage, mates.isEmpty {
            key = "announcement_surprise"
            randomCat = nil
        } else if clan.affairs, other != nil, let mate = maleMates.first {
            key = pick(["announcement_affair", "announcement"], &rng)
            clan.pregnancies[id]?.affairKnown = key == "announcement_affair"
            randomCat = mate.id
        } else if clan.affairs, other != nil, let mate = femaleMates.first {
            key = "announcement_affair_samesex"
            randomCat = mate.id
        }

        let severity = weighted([("minor", 3), ("major", 1)], &rng)
        getInjured(id, "pregnant", severity: severity, in: &clan, using: &rng)
        guard let text = library?.pregnancy else { return [.expecting(mother: id)] }
        let lines = (text.lines[key] ?? []).filter { randomCat != nil || !$0.contains("r_c") }
        guard let line = lines.randomElement(using: &rng) else { return [.expecting(mother: id)] }
        let template = line + (text.lines["\(severity)_severity"]?.randomElement(using: &rng) ?? "")
        var cats = ["m_c": id]
        if let randomCat, template.contains("r_c") { cats["r_c"] = randomCat }
        return [.story(StoryPick(template: template, cats: cats), .birth)]
    }

    /// Clangen's `_retrieve_secret_kittens`: kits with this cat as their only known parent.
    private func secretKittens(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        let backstory = pick(["halfclan2", "outsider_roots2"], &rng)
        let kits = makeLitter(litterSize(for: cat, using: &rng), birthParent: cat, other: nil, backstory: backstory, in: &clan, using: &rng)
        let line = library?.pregnancy.strings["pregnant_secret"] ?? "%{name} brought a %{insert} back to camp, but refused to talk about their origin."
        var pick = StoryPick(template: line.replacing("%{name}", with: "m_c").replacing("%{insert}", with: kitAmount(kits.count)), cats: ["m_c": id])
        pick.groupCats[Self.bornKitsKey] = kits
        return [.story(pick, .birth)]
    }

    /// Cats in a birth event who aren't named in its text.
    static let bornKitsKey = "\u{1}kits"

    // MARK: - Expecting

    /// Clangen's `handle_one_moon_pregnant`: the litter's size is settled, the queen guesses it,
    /// and a minor pregnancy becomes major.
    private func pregnancyMoonOne(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        let amount = litterSize(for: cat, using: &rng)
        clan.pregnancies[id]?.litterSize = amount

        let guess = weighted([("correct", 4), ("incorrect", 1), ("unsure", 1)], &rng)
        let small = amount <= 3
        let key = switch guess {
        case "correct": small ? "small" : "large"
        case "incorrect": small ? "large" : "small"
        default: "unsure"
        }
        var template = library?.pregnancy.litterGuess[key]?.randomElement(using: &rng) ?? ""
        if let i = clan.index(of: id) {
            if let c = clan.cats[i].conditions.firstIndex(where: { $0.name == "pregnant" && $0.kind == .injury }) {
                if clan.cats[i].conditions[c].severity == "minor" {
                    clan.cats[i].conditions[c].severity = "major"
                    template += library?.pregnancy.lines["major_severity"]?.randomElement(using: &rng) ?? ""
                }
            } else {
                getInjured(id, "pregnant", severity: "major", in: &clan, using: &rng)
            }
        }
        guard !template.isEmpty else { return [] }
        return [.story(StoryPick(template: template, cats: ["m_c": id]), .birth)]
    }

    func litterSize(for cat: Cat, using rng: inout some RandomNumberGenerator) -> Int {
        let weights = Self.litterWeights[cat.age] ?? Self.litterWeights[.adult]!
        return max(1, weighted(Array(zip(1...6, weights)), &rng))
    }

    // MARK: - Birth

    /// Clangen's `handle_two_moon_pregnant`: the kits are born. The queen may die (the
    /// `pregnant` condition's mortality in expanded mode, 1 in 40 in classic), and otherwise
    /// swaps `pregnant` for `recovering from birth`. Affairs may come out, and co-parents may
    /// or may not get along.
    private func giveBirth(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let record = clan.pregnancies[id], let cat = clan[id] else { return [] }
        let other = clan[record.otherParent]

        var adoptive: [UUID] = []
        var cheatedMate: Cat?
        var mateClaimedKits = false
        var secretAffair = false
        if let other, !cat.mates.isEmpty, !cat.mates.contains(other.id) {
            cheatedMate = livingMate(of: cat, in: clan)
            if let cheatedMate {
                if record.affairKnown != true, Bool.random(using: &rng) {
                    secretAffair = true
                    adoptive.append(cheatedMate.id)
                } else if claimsAffairKits(cheatedMate, of: cat, in: clan, using: &rng) {
                    mateClaimedKits = true
                    adoptive.append(cheatedMate.id)
                }
            }
        }
        let backstory = other == nil ? pick(["halfclan1", "outsider_roots1"], &rng) : nil
        let kits = makeLitter(max(1, record.litterSize), birthParent: cat, other: other, adoptive: adoptive, backstory: backstory, in: &clan, using: &rng)
        clan.pregnancies[id] = nil
        if let i = clan.index(of: id) { clan.cats[i].birthCooldown = Self.birthCooldown }

        let text = library?.pregnancy
        var outcome = birthOutcome(of: cat, with: other, secretAffair: secretAffair, in: clan, using: &rng)
        var lines = [outcome.line(text, &rng)]
        if let cheatedMate, other != nil, !secretAffair {
            let key = mateClaimedKits ? "mate_claims_kits" : "mate_disowns_kits"
            if let line = text?.strings[key] {
                lines.append(line.replacing("r_c", with: "mc_mate"))
                outcome.cats["mc_mate"] = cheatedMate.id
            }
        }

        var events: [MoonEvent] = []
        let mortality = clan.preyAndHerbs ? cat.condition("pregnant", .injury)?.mortality ?? 40 : 40
        let dies = mortality <= 0 || oneIn(mortality, &rng)
        if dies {
            let key = clan.leader == id && clan.leaderLives > 1 ? "lead_death" : "death"
            lines.append(birthLine(key, text, for: cat, in: clan, using: &rng))
            events = loseLifeOrDie(id, cause: .childbirth, in: &clan, using: &rng).filter { if case .died = $0 { false } else { true } }
        } else {
            let hadBloodLoss = cat.has("blood loss")
            getInjured(id, "recovering from birth", eventTriggered: true, in: &clan, using: &rng)
            if !hadBloodLoss, clan[id]?.has("blood loss") == true {
                lines.append(birthLine("difficult_birth", text, for: cat, in: clan, using: &rng))
            }
        }
        if clan.isAlive(id), let i = clan.index(of: id) {
            clan.cats[i].conditions.removeAll { $0.name == "pregnant" && $0.kind == .injury }
        }

        birthRelationshipChanges(cat, other, kits: kits, outcome: outcome, secretAffair: secretAffair, in: &clan)
        if let i = clan.index(of: id), clan.cats[i].isAlive { clan.cats[i].nextThought = .onBirth }
        if let other, let o = clan.index(of: other.id), clan.cats[o].isAlive { clan.cats[o].nextThought = .onBirth }

        var story: MoonEvent
        let template = lines.compactMap { $0 }.joined(separator: " ")
            .replacing("%{insert}", with: kitAmount(kits.count)).replacing("{insert}", with: kitAmount(kits.count))
        if text == nil || template.isEmpty {
            story = .born(mother: id, father: other?.id, kits: kits)
        } else {
            var pick = StoryPick(template: template, cats: outcome.cats.filter { $0.key == "m_c" || template.contains($0.key) })
            pick.groupCats[Self.bornKitsKey] = kits
            story = .story(pick, .birth)
        }
        events.insert(story, at: 0)

        if let cheatedMate, !mateClaimedKits, !secretAffair {
            events += affairBreakup(cheating: id, mate: cheatedMate.id, in: &clan, using: &rng)
            if let other, outcome.otherAffairKnown, let otherMate = other.mates.first(where: { $0 != id && clan.isAlive($0) }) {
                events += affairBreakup(cheating: other.id, mate: otherMate, in: &clan, using: &rng)
            }
        }
        return events
    }

    /// Which birth text fits, and the cats it names.
    struct BirthOutcome {
        var key: String
        var cats: [String: UUID]
        var coparenting: Bool?
        var otherAffairKnown = false

        func line(_ text: PregnancyText?, _ rng: inout some RandomNumberGenerator) -> String? {
            let lines = (text?.birth[key] ?? []).filter { line in
                ["r_c", "mc_mate", "rc_mate"].allSatisfy { !line.contains($0) || cats[$0] != nil }
            }
            return lines.randomElement(using: &rng)
        }
    }

    /// Clangen's `_handle_main_birth_event`.
    private func birthOutcome(of cat: Cat, with other: Cat?, secretAffair: Bool, in clan: Clan, using rng: inout some RandomNumberGenerator) -> BirthOutcome {
        var cats = ["m_c": cat.id]
        guard let other else { return BirthOutcome(key: "unmated_parent", cats: cats) }
        cats["r_c"] = other.id
        let isMate = cat.mates.contains(other.id)
        if isMate, clan.isAlive(other.id) { return BirthOutcome(key: "two_parents", cats: cats) }
        if isMate, other.isDead { return BirthOutcome(key: "dead_mate", cats: cats) }
        if isMate { return BirthOutcome(key: "outside_mate", cats: cats) }
        if cat.mates.isEmpty, other.mates.isEmpty, other.isAlive {
            let positive = Bool.random(using: &rng)
            return BirthOutcome(key: positive ? "both_unmated_pos" : "both_unmated_neg", cats: cats, coparenting: positive)
        }
        if !clan.sameSexBirth, cat.mates.contains(where: { clan[$0]?.sex == .female }) {
            if let mate = livingMate(of: cat, in: clan) { cats["mc_mate"] = mate.id }
            return BirthOutcome(key: "affair_mated_samesex", cats: cats)
        }
        if !cat.mates.isEmpty, other.isAlive {
            if let mate = livingMate(of: cat, in: clan) {
                cats["mc_mate"] = mate.id
                return BirthOutcome(key: secretAffair ? "affair_mated_secret" : "affair_mated", cats: cats)
            }
            if let dead = cat.mates.first(where: { clan[$0]?.isDead == true }) { cats["mc_mate"] = dead }
            return BirthOutcome(key: "affair_mated_dead_mate", cats: cats)
        }
        if !other.mates.isEmpty, !other.mates.contains(cat.id), other.isAlive {
            guard let otherMate = livingMate(of: other, in: clan) else { return BirthOutcome(key: "both_unmated_pos", cats: cats) }
            cats["rc_mate"] = otherMate.id
            let known = Bool.random(using: &rng)
            return BirthOutcome(key: known ? "affair" : "affair_secret", cats: cats, otherAffairKnown: known)
        }
        cats["r_c"] = nil
        return BirthOutcome(key: "unmated_parent", cats: cats)
    }

    /// A death or difficult-birth line, leaving out ones about a medicine cat helping when none
    /// can: there's no medicine cat, or the queen or her mate is one.
    private func birthLine(_ key: String, _ text: PregnancyText?, for cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> String? {
        let healers = clan.living.filter(\.isHealer).map(\.id)
        let noHelp = healers.isEmpty || cat.isHealer || cat.mates.contains(where: healers.contains)
        let lines = (text?.birth[key] ?? []).filter { !noHelp || !$0.contains("medicine cat") }
        return (lines.isEmpty ? text?.birth[key] ?? [] : lines).randomElement(using: &rng)
    }

    private func livingMate(of cat: Cat, in clan: Clan) -> Cat? {
        cat.mates.lazy.compactMap { clan[$0] }.first { $0.isAlive }
    }

    /// Clangen's `_check_should_claim_affair_kits`: a loving mate may raise the kits anyway.
    private func claimsAffairKits(_ mate: Cat, of cat: Cat, in clan: Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        let romance = clan.relationship(from: mate.id, to: cat.id)?[.romance] ?? 0
        let bonus = romance >= 85 ? 40 : romance >= 65 ? 20 : romance >= 45 ? 0 : romance >= 25 ? -20 : -30
        return Int.random(in: 1...100, using: &rng) <= min(max(40 + bonus, 0), 100)
    }

    /// Clangen's `_handle_on_birth_relationship_changes`.
    private func birthRelationshipChanges(_ cat: Cat, _ other: Cat?, kits: [UUID], outcome: BirthOutcome, secretAffair: Bool, in clan: inout Clan) {
        guard let other else { return }
        let affairHurt: [RelationshipValue: Int] = [.romance: -50, .trust: -30, .like: -40]
        let affairLog = library?.pregnancy.strings["affair_rel_log"] ?? "m_c found out that r_c cheated on {PRONOUN/m_c/object} and had kits with another cat."
        func hurt(_ mates: [UUID], by cheater: UUID) {
            for mate in mates where clan.isAlive(mate) {
                change(from: mate, to: cheater, affairHurt, log: affairLog, positive: false, in: &clan)
            }
        }
        if !cat.mates.isEmpty, !cat.mates.contains(other.id), !secretAffair { hurt(cat.mates, by: cat.id) }
        if !other.mates.isEmpty, !other.mates.contains(cat.id), outcome.otherAffairKnown { hurt(other.mates, by: other.id) }

        guard cat.mates.isEmpty, other.mates.isEmpty, other.isAlive, let positive = outcome.coparenting else { return }
        if !positive {
            for kit in kits {
                clan.updateRelationship(from: other.id, to: kit) { $0.add(.comfort, -10) }
            }
        }
        let sign = positive ? 1 : -1
        let values: [RelationshipValue: Int] = [.romance: 20 * sign, .comfort: 30 * sign, .trust: 25 * sign]
        let key = positive ? "coparenting_rel_log_pos" : "coparenting_rel_log_neg"
        let log = library?.pregnancy.strings[key] ?? ""
        for (a, b) in [(cat.id, other.id), (other.id, cat.id)] {
            change(from: a, to: b, values, log: log, positive: positive, in: &clan)
        }
    }

    /// Clangen's `change_relationship_values` with a log line where `m_c` is the cat whose
    /// feelings change and `r_c` the cat they're about.
    private func change(from: UUID, to: UUID, _ values: [RelationshipValue: Int], log: String, positive: Bool, in clan: inout Clan) {
        var entry: String?
        if !log.isEmpty, let template = (narrator as? ClangenNarrator)?.template, let a = clan[from], let b = clan[to] {
            entry = template.resolve(log, cats: ["m_c": a, "r_c": b], clan: clan) + (positive ? " (positive effect)" : " (negative effect)")
        }
        for (value, amount) in values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if let relationships {
                relationships.change(from: from, to: to, [value], by: amount, log: nil, in: &clan)
            } else {
                clan.updateRelationship(from: from, to: to) { $0.add(value, amount) }
            }
        }
        if let entry { clan.updateRelationship(from: from, to: to) { $0.addLog(entry) } }
    }

    /// Clangen's `_handle_affair_discovery_breakup`: a mate who learns of the affair and won't
    /// raise the kits usually leaves.
    private func affairBreakup(cheating: UUID, mate: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard clan[mate]?.mates.contains(cheating) == true, Double.random(in: 0..<1, using: &rng) <= 0.8,
              let relationships
        else { return [] }
        relationships.breakUp(mate, cheating, fight: true, in: &clan, using: &rng)
        guard let line = relationships.library.breakups["affair_discovery_breakup"]?.randomElement(using: &rng) else { return [] }
        return [.story(StoryPick(template: line, cats: ["m_c": mate, "r_c": cheating]), .relationship)]
    }

    // MARK: - Kits

    /// Clangen's `get_kits` for a birth: kits with one or two blood parents, whom the parents'
    /// other mates help raise when they're all mates together.
    @discardableResult
    func makeLitter(
        _ count: Int, birthParent: Cat, other: Cat?, adoptive extra: [UUID] = [], backstory: String?,
        in clan: inout Clan, using rng: inout some RandomNumberGenerator
    ) -> [UUID] {
        var kits: [Cat] = []
        var usedPrefixes = Set<String>()
        for _ in 0..<count {
            var kit = factory.makeKit(parents: [birthParent] + [other].compactMap { $0 }, theyThem: clan.theyThemDefault, using: &rng)
            for _ in 0..<10 where usedPrefixes.contains(kit.name.prefix) {
                kit.name = factory.names.generate(for: kit.appearance, using: &rng)
            }
            usedPrefixes.insert(kit.name.prefix)
            if let backstory { kit.backstory = backstory }
            kits.append(kit)
        }
        clan.cats += kits
        let adoptive = polyParents(for: kits, of: birthParent, other, adding: extra, in: &clan)
        relationships?.initializeKits(kits.map(\.id), parents: [birthParent.id] + [other?.id].compactMap { $0 } + adoptive, in: &clan, using: &rng)
        for kit in kits { rollCongenital(for: kit.id, in: &clan, using: &rng) }
        return kits.map(\.id)
    }

    /// Clangen's poly parenting: when the birth parents are mates, their other living mates
    /// adopt the litter, as do any cats in `extra`, unless they're already the kits' relatives.
    func polyParents(for kits: [Cat], of mother: Cat, _ father: Cat?, adding extra: [UUID] = [], in clan: inout Clan) -> [UUID] {
        guard let first = kits.first else { return [] }
        let birthParents = [mother.id] + [father?.id].compactMap { $0 }
        var candidates: [UUID] = []
        if let father, mother.mates.contains(father.id) { candidates += mother.mates }
        if let father, father.mates.contains(mother.id) { candidates += father.mates }
        candidates = candidates.filter { !birthParents.contains($0) && clan.isAlive($0) } + extra
        var seen: Set<UUID> = []
        candidates = candidates.filter { seen.insert($0).inserted }

        var adoptive: [UUID] = []
        let relatives = clan.relatives(of: first.id)
        for mate in candidates {
            if let m = clan.index(of: mate) { clan.cats[m].nextThought = .onBirth }
            if !relatives.contains(mate) { adoptive.append(mate) }
        }
        for kit in kits {
            if let k = clan.index(of: kit.id) { clan.cats[k].adoptiveParents = adoptive }
        }
        return adoptive
    }

    /// Clangen's `handle_adoption`: a pair who can't have kits together finds an abandoned
    /// litter. The kits' blood parent is a dead loner or kittypet; the pair and all their
    /// living mates adopt them.
    func adoptLitter(by id: UUID, with partner: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let i = clan.index(of: id), let other = clan[partner], clan.isAlive(partner), other.birthCooldown == 0,
              clan.pregnancies[id] == nil, clan.pregnancies[partner] == nil
        else { return [] }
        let cat = clan.cats[i]
        let count = litterSize(for: cat, using: &rng)

        let social: Cat.Origin = pick([.loner, .kittypet], &rng)
        var birthParent = factory.make(rank: .warrior, moons: Int.random(in: 15...120, using: &rng), origin: social, theyThem: clan.theyThemDefault, using: &rng)
        birthParent.name = factory.names.outsiderName(for: social, using: &rng)
        clan.outsiders.append(birthParent)
        clan.sendToAfterlife(birthParent.id, history: nil, using: &rng)

        var adoptive = [id, partner]
        for mate in cat.mates + other.mates where clan.isAlive(mate) && !adoptive.contains(mate) { adoptive.append(mate) }

        var kits: [Cat] = []
        var usedPrefixes = Set<String>()
        for _ in 0..<count {
            var kit = factory.make(rank: .newborn, moons: 0, origin: .clanborn, theyThem: clan.theyThemDefault, using: &rng)
            for _ in 0..<10 where usedPrefixes.contains(kit.name.prefix) {
                kit.name = factory.names.generate(for: kit.appearance, using: &rng)
            }
            usedPrefixes.insert(kit.name.prefix)
            kit.parents = [birthParent.id]
            kit.adoptiveParents = adoptive
            kit.backstory = "abandoned\(Int.random(in: 1...4, using: &rng))"
            kits.append(kit)
        }
        clan.cats += kits
        relationships?.initializeKits(kits.map(\.id), parents: adoptive, in: &clan, using: &rng)
        for kit in kits { rollCongenital(for: kit.id, in: &clan, using: &rng) }
        clan.cats[i].birthCooldown = Self.birthCooldown
        clan.cats[i].nextThought = .onBirth
        if let p = clan.index(of: partner) { clan.cats[p].nextThought = .onBirth }
        return [.adopted(parents: [id, partner], kits: kits.map(\.id))]
    }

    /// Clangen's `kit_amount`, e.g. "litter of 3 kits".
    func kitAmount(_ count: Int) -> String {
        let amounts = library?.kitAmount ?? [:]
        return count == 1
            ? amounts["one"] ?? "single kitten"
            : (amounts["many"] ?? "litter of %{count} kits").replacing("%{count}", with: "\(count)")
    }
}
