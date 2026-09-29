import Foundation

/// Clangen's injuries, illnesses and permanent conditions (classic mode, no herb stores).
extension MoonEngine {
    // MARK: - Medicine cats

    private func workingHealers(in clan: Clan) -> [Cat] {
        clan.living.filter { [.medicineCat, .medicineApprentice].contains($0.rank) && !$0.isNotWorking }
    }

    /// In classic mode any working medicine cat or apprentice covers the whole Clan.
    private func isCovered(_ clan: Clan) -> Bool { !workingHealers(in: clan).isEmpty }

    /// Clangen picks text with `r_c` (a medicine cat helping) only when a healer other than the cat exists.
    private func pickText(_ options: [String], healer: Cat?, for id: UUID, indexZeroIsHealer: Bool, using rng: inout some RandomNumberGenerator) -> String? {
        let helped = healer.map { $0.id != id } ?? false
        if helped { return options.randomElement(using: &rng) }
        let pool = (indexZeroIsHealer && options.count > 1 ? Array(options.dropFirst()) : options).filter { !$0.contains("r_c") }
        return pool.randomElement(using: &rng)
    }

    private func story(_ texts: [String], for id: UUID, healer: Cat?) -> MoonEvent? {
        guard !texts.isEmpty else { return nil }
        var cats = ["m_c": id]
        if let healer, healer.id != id { cats["r_c"] = healer.id }
        return .story(StoryPick(template: texts.joined(separator: " "), cats: cats), .health)
    }

    // MARK: - Gaining conditions

    @discardableResult
    func getIll(_ id: UUID, _ name: String, eventTriggered: Bool = false, lethal: Bool = true, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        guard let library = conditions, let info = library.conditions[name], info.kind == .illness,
              let i = clan.index(of: id), clan.cats[i].isAlive, !clan.cats[i].has(name)
        else { return false }
        if name == "kittencough", clan.cats[i].rank != .kitten { return false }
        let covered = isCovered(clan)
        let age = clan.cats[i].age.rawValue
        var duration = covered ? info.medicineDuration : info.duration
        duration = max(1, duration + Int.random(in: -1...0, using: &rng))
        let mortality = !lethal ? 0 : (covered ? info.medicineMortality[age] : info.mortality[age]) ?? 0
        clan.cats[i].conditions.append(CatCondition(
            kind: .illness, name: name, severity: info.severity, mortality: mortality, duration: duration,
            moonStart: clan.age, risks: info.risks, eventTriggered: eventTriggered, infectiousness: info.infectiousness
        ))
        return true
    }

    @discardableResult
    func getInjured(
        _ id: UUID, _ name: String, eventTriggered: Bool = false, lethal: Bool = true, scars: [String]? = nil,
        in clan: inout Clan, using rng: inout some RandomNumberGenerator
    ) -> Bool {
        guard let library = conditions, let info = library.conditions[name], info.kind == .injury,
              let i = clan.index(of: id), clan.cats[i].isAlive, !clan.cats[i].has(name)
        else { return false }
        let scarsNow = Set(clan.cats[i].appearance.scars)
        if name == "mangled tail", scarsNow.contains("NOTAIL") { return false }
        if name == "torn ear", scarsNow.contains("NOEAR") { return false }
        let mortality = lethal ? info.mortality[clan.cats[i].age.rawValue] ?? 0 : 0
        clan.cats[i].conditions.append(CatCondition(
            kind: .injury, name: name, severity: info.severity, mortality: mortality, duration: info.duration,
            moonStart: clan.age, risks: info.risks, eventTriggered: eventTriggered,
            potentialScars: scars.flatMap { $0.isEmpty ? nil : $0 }
        ))
        if !info.alsoGot.isEmpty, oneIn(5, &rng),
           !(info.alsoGot.contains("blood loss") && stopBleeding(for: id, in: &clan, using: &rng)),
           let extra = info.alsoGot.randomElement(using: &rng) {
            if library.conditions[extra]?.kind == .illness {
                getIll(id, extra, eventTriggered: true, in: &clan, using: &rng)
            } else {
                getInjured(id, extra, eventTriggered: true, in: &clan, using: &rng)
            }
        }
        return true
    }

    @discardableResult
    func getPermanent(
        _ id: UUID, _ name: String, bornWith: Bool = false, eventTriggered: Bool = false,
        in clan: inout Clan, using rng: inout some RandomNumberGenerator
    ) -> Bool {
        guard let library = conditions, let info = library.conditions[name], info.kind == .permanent,
              let i = clan.index(of: id), clan.cats[i].isAlive, !clan.cats[i].has(name)
        else { return false }
        if name == "failing eyesight", clan.cats[i].has("blind") { return false }
        if name == "partial hearing loss", clan.cats[i].has("deaf") { return false }
        removeLostAccessories(i, in: &clan)

        let bornWith = bornWith || info.congenital == "always"
        var moonsUntil = 0
        if bornWith {
            moonsUntil = info.moonsUntil == 0 ? 0 : max(0, Int.random(in: (info.moonsUntil - 1)...(info.moonsUntil + 1), using: &rng))
            if !clan.cats[i].rank.isBaby { moonsUntil = -2 }
        }
        clan.cats[i].conditions.append(CatCondition(
            kind: .permanent, name: name, severity: info.severity,
            mortality: info.mortality[clan.cats[i].age.rawValue] ?? 0, duration: 0,
            moonStart: clan.age, risks: info.risks, eventTriggered: eventTriggered, bornWith: bornWith, moonsUntil: moonsUntil
        ))
        return true
    }

    /// Accessories can't stay on a missing tail or leg.
    private func removeLostAccessories(_ i: Int, in clan: inout Clan) {
        let scars = Set(clan.cats[i].appearance.scars)
        let parts = factory.appearance.index.accessoryBodyParts
        clan.cats[i].appearance.accessories.removeAll { accessory in
            (parts[accessory] == "tail" && !scars.isDisjoint(with: ["NOTAIL", "HALFTAIL"]))
                || (parts[accessory] == "paw" && scars.contains("NOPAW"))
        }
    }

    /// Applies an event's `injury` blocks: each listed cat gets one injury they don't already have.
    func applyInjuries(_ blocks: [InjuryBlock], cats: [String: UUID], in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        for block in blocks {
            let possible = block.injuries.flatMap { ConditionLibrary.injuryGroups[$0] ?? [$0] }
            for abbr in block.cats {
                guard let id = cats[abbr], let cat = clan[id] else { continue }
                let options = possible.filter { !cat.has($0) }
                guard let name = options.randomElement(using: &rng) else { continue }
                if conditions?.conditions[name]?.kind == .illness {
                    getIll(id, name, in: &clan, using: &rng)
                } else {
                    getInjured(id, name, scars: block.scars, in: &clan, using: &rng)
                }
            }
        }
    }

    /// 1 in 90 kits is born with a condition that may only show as they grow.
    func rollCongenital(for id: UUID, odds: Int = 90, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let library = conditions, oneIn(odds, &rng) else { return }
        let options = library.conditions.filter { $0.value.kind == .permanent && $0.value.congenital != "never" }.map(\.key).sorted()
        guard let name = options.randomElement(using: &rng),
              getPermanent(id, name, bornWith: true, in: &clan, using: &rng),
              let i = clan.index(of: id)
        else { return }
        if name == "born without a leg" { clan.cats[i].appearance.scars.append("NOPAW") }
        if name == "born without a tail" { clan.cats[i].appearance.scars.append("NOTAIL") }
    }

    // MARK: - Each moon for sick and hurt cats

    /// Clangen's `handle_already_ill` / `handle_already_injured`, in a random order when a cat is both.
    func progressConditions(for id: UUID, skip: inout Set<String>, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        var order: [ConditionKind] = []
        if cat.isIll { order.append(.illness) }
        if cat.isInjured { order.append(.injury) }
        order.shuffle(using: &rng)
        var events: [MoonEvent] = []
        for kind in order where clan.isAlive(id) {
            if kind == .injury, clan.pregnancies[id] != nil { continue }
            events += progress(kind, for: id, skip: &skip, in: &clan, using: &rng)
        }
        return events
    }

    private func progress(_ kind: ConditionKind, for id: UUID, skip: inout Set<String>, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let library = conditions, let start = clan[id] else { return [] }
        let healer = workingHealers(in: clan).randomElement(using: &rng)
        var texts: [String] = []
        var lifeEvents: [MoonEvent] = []

        for condition in start.conditions where condition.kind == kind && !skip.contains(condition.name) {
            guard let i = clan.index(of: id), let c = clan.cats[i].conditions.firstIndex(where: { $0.name == condition.name && $0.kind == kind }) else { continue }
            if clan.cats[i].conditions[c].eventTriggered {
                clan.cats[i].conditions[c].eventTriggered = false
                continue
            }
            let current = clan.cats[i].conditions[c]
            var mortality = current.mortality
            if clan.leader == id, mortality != 0 { mortality = max(1, Int(Double(mortality) * 0.7)) }

            if mortality != 0, oneIn(mortality, &rng) {
                let file = kind == .illness ? "illness_death_strings" : "injury_death_strings"
                let fallback = kind == .illness ? "m_c was killed by {PRONOUN/m_c/poss} illness." : "m_c was killed by {PRONOUN/m_c/poss} injuries."
                texts = [library.strings(file, current.name).randomElement(using: &rng) ?? fallback]
                let history = kind == .illness ? "m_c died to an illness." : "m_c died to an injury."
                lifeEvents = loseLifeOrDie(id, cause: .misfortune, history: history, in: &clan, using: &rng).filter { if case .died = $0 { false } else { true } }
                break
            }

            let healed = current.duration - current.moonsWith(clanAge: clan.age) <= 0 && (kind == .illness || current.complication == nil)
            if healed {
                skip.insert(current.name)
                clan.cats[i].conditions.remove(at: c)
                if kind == .illness {
                    if ["an infected wound", "a festering wound"].contains(current.name) {
                        for j in clan.cats[i].conditions.indices { clan.cats[i].conditions[j].complication = nil }
                    }
                    let options = library.strings("illness_healed_strings", current.name)
                    texts.append(pickText(options, healer: healer, for: id, indexZeroIsHealer: false, using: &rng)
                        ?? "m_c's \(library.displayName(current.name)) has healed.")
                } else {
                    texts.append(healInjury(current, for: id, healer: healer, in: &clan, using: &rng))
                }
                continue
            }

            if let text = giveRisks(current, for: id, healer: healer, skip: &skip, in: &clan, using: &rng) {
                texts.append(text)
            }
        }
        return [story(texts, for: id, healer: healer)].compactMap { $0 } + lifeEvents
    }

    /// A healed injury may leave a scar, and some scars leave a lasting condition.
    private func healInjury(_ injury: CatCondition, for id: UUID, healer: Cat?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> String {
        guard let library = conditions else { return "" }
        let display = library.displayName(injury.name)
        var text: String
        let scar = giveScar(for: injury, to: id, in: &clan, using: &rng)
        if scar != nil {
            text = pick([
                "m_c's \(display) has healed, but {PRONOUN/m_c/subject}'ll always carry evidence of it on {PRONOUN/m_c/poss} pelt.",
                "m_c healed from {PRONOUN/m_c/poss} \(display) but will forever be marked by a scar.",
                "m_c's \(display) has healed, but the injury left {PRONOUN/m_c/object} scarred.",
            ], &rng)
        } else {
            text = pickText(library.strings("injury_healed_strings", injury.name), healer: healer, for: id, indexZeroIsHealer: false, using: &rng)
                ?? "m_c's \(display) has healed."
        }

        var lasting: String?
        if let scar {
            lasting = ConditionLibrary.scarToCondition[scar]?.randomElement(using: &rng)
        } else {
            let possible = library.conditions[injury.name]?.causePermanent.filter(ConditionLibrary.scarlessConditions.contains) ?? []
            if !possible.isEmpty, oneIn(15, &rng) { lasting = possible.randomElement(using: &rng) }
        }
        if let lasting, getPermanent(id, lasting, in: &clan, using: &rng) {
            text = pickText(library.strings("gain_permanent_condition_strings", injury.name, lasting), healer: healer, for: id, indexZeroIsHealer: false, using: &rng)
                ?? "After m_c's \(display) healed, {PRONOUN/m_c/subject} now {VERB/m_c/have/has} \(library.displayName(lasting))."
        }
        return text
    }

    /// Clangen's `handle_scars`: a scar is likelier the faster the injury healed.
    private func giveScar(for injury: CatCondition, to id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> String? {
        guard let i = clan.index(of: id) else { return nil }
        let potential = injury.potentialScars ?? []
        guard !potential.isEmpty || ConditionLibrary.scarAllowed[injury.name] != nil else { return nil }
        let chance = max(5 - injury.moonsWith(clanAge: clan.age), 1) + (isCovered(clan) ? 2 : 0)
        let existing = clan.cats[i].appearance.scars
        guard existing.count < 4, oneIn(chance, &rng) else { return nil }

        let index = factory.appearance.index
        let drawable = Set(index.scars + index.missingPartScars)
        var pool = (potential.isEmpty ? ConditionLibrary.scarAllowed[injury.name] ?? [] : potential)
            .filter { !existing.contains($0) && drawable.contains($0) }
        let has = Set(existing)
        if has.contains("NOPAW") { pool.removeAll { ["TOETRAP", "RATBITE", "FROSTSOCK"].contains($0) } }
        if has.contains("NOTAIL") { pool.removeAll { ["HALFTAIL", "TAILBASE", "TAILSCAR", "MANTAIL", "BURNTAIL", "FROSTTAIL"].contains($0) } }
        if has.contains("HALFTAIL") { pool.removeAll { ["TAILSCAR", "MANTAIL", "FROSTTAIL"].contains($0) } }
        if has.contains("BRIGHTHEART") { pool.removeAll { ["RIGHTBLIND", "BOTHBLIND"].contains($0) } }
        if has.contains("BOTHBLIND") { pool.removeAll { ["THREE", "RIGHTBLIND", "LEFTBLIND", "BOTHBLIND", "BRIGHTHEART"].contains($0) } }
        if has.contains("NOEAR") { pool.removeAll { ["LEFTEAR", "RIGHTEAR", "NOLEFTEAR", "NORIGHTEAR", "FROSTFACE"].contains($0) } }
        if !has.isDisjoint(with: ["MANTAIL", "BURNTAIL", "FROSTTAIL"]) { pool.removeAll { ["MANTAIL", "BURNTAIL", "FROSTTAIL"].contains($0) } }
        if Int.random(in: 0..<3, using: &rng) != 0 { pool.removeAll(where: ConditionLibrary.conditionScars.contains) }
        guard var scar = pool.randomElement(using: &rng) else { return nil }

        var scars = existing
        if (scar == "NOLEFTEAR" && has.contains("NORIGHTEAR")) || (scar == "NORIGHTEAR" && has.contains("NOLEFTEAR")) {
            scars.removeAll { ["NOLEFTEAR", "NORIGHTEAR"].contains($0) }
            scar = "NOEAR"
        }
        if (scar == "LEFTBLIND" && has.contains("RIGHTBLIND")) || (scar == "RIGHTBLIND" && has.contains("LEFTBLIND")) {
            scars.removeAll { ["LEFTBLIND", "RIGHTBLIND"].contains($0) }
            scar = "BOTHBLIND"
        }
        clan.cats[i].appearance.scars = scars + [scar]
        removeLostAccessories(i, in: &clan)
        return scar
    }

    /// Clangen's `give_risks`: each condition may bring on a complication, at most one per moon.
    private func giveRisks(_ condition: CatCondition, for id: UUID, healer: Cat?, skip: inout Set<String>, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> String? {
        guard let library = conditions, let cat = clan[id] else { return nil }
        let progression: [String: String] = switch condition.kind {
        case .illness: ConditionLibrary.illnessProgression
        case .injury: ConditionLibrary.injuryProgression
        case .permanent: ConditionLibrary.permanentProgression
        }
        let hasMedicineCat = clan.living.contains { $0.rank == .medicineCat }
        for (r, risk) in condition.risks.enumerated() {
            if cat.has(risk.name) { continue }
            if risk.name == "an infected wound", cat.has("a festering wound") { continue }
            var chance = risk.chance
            if isCovered(clan) { chance += 10 }
            if !hasMedicineCat, chance != 0 { chance = max(1, Int(Double(chance) * 0.75)) }
            guard chance != 0, oneIn(chance, &rng), let info = library.conditions[risk.name] else { continue }
            if let later = progression[risk.name], cat.has(later) { break }

            guard let i = clan.index(of: id),
                  let c = clan.cats[i].conditions.firstIndex(where: { $0.name == condition.name && $0.kind == condition.kind })
            else { break }
            let infection = ["an infected wound", "a festering wound"].contains(risk.name)
            clan.cats[i].conditions[c].risks[r].chance = infection ? 0 : risk.chance + 20

            let file = switch condition.kind {
            case .illness: "illness_risk_strings"
            case .injury: "injuries_risk_strings"
            case .permanent: "permanent_condition_risk_strings"
            }
            let text = pickText(library.strings(file, condition.name, risk.name), healer: healer, for: id, indexZeroIsHealer: true, using: &rng)
                ?? "m_c's condition has gotten worse."

            let evolves = progression[condition.name] == risk.name
            if evolves { clan.cats[i].conditions.remove(at: c) }
            skip.insert(risk.name)
            let triggered = condition.kind == .permanent
            switch info.kind {
            case .injury:
                getInjured(id, risk.name, eventTriggered: triggered, in: &clan, using: &rng)
            case .illness:
                getIll(id, risk.name, eventTriggered: triggered, in: &clan, using: &rng)
                if !evolves, condition.kind != .illness, infection,
                   let i = clan.index(of: id),
                   let c = clan.cats[i].conditions.firstIndex(where: { $0.name == condition.name && $0.kind == condition.kind }) {
                    clan.cats[i].conditions[c].complication = risk.name == "an infected wound" ? "infected" : "festering"
                }
            case .permanent:
                getPermanent(id, risk.name, eventTriggered: triggered, in: &clan, using: &rng)
            }
            return text
        }
        return nil
    }

    /// Clangen's `handle_already_disabled`, including congenital conditions showing and retirement.
    func progressDisabilities(for id: UUID, skip: inout Set<String>, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let library = conditions, let start = clan[id] else { return [] }
        let healer = workingHealers(in: clan).randomElement(using: &rng)
        var texts: [String] = []
        var events: [MoonEvent] = []

        for condition in start.permanentConditions where !skip.contains(condition.name) {
            guard let i = clan.index(of: id), let c = clan.cats[i].conditions.firstIndex(where: { $0.name == condition.name && $0.kind == .permanent }) else { continue }
            if clan.cats[i].conditions[c].eventTriggered {
                clan.cats[i].conditions[c].eventTriggered = false
                continue
            }
            let current = clan.cats[i].conditions[c]
            if current.bornWith, current.moonsUntil >= 0 {
                clan.cats[i].conditions[c].moonsUntil -= 1
                if clan.cats[i].conditions[c].moonsUntil != -1 { continue }
                clan.cats[i].conditions[c].moonsUntil = -2
                let hasParents = !(clan[id]?.parents.isEmpty ?? true)
                let options = library.strings("gain_congenital_condition_strings", current.name)
                let text = pickText(options, healer: hasParents ? healer : nil, for: id, indexZeroIsHealer: true, using: &rng)
                texts.append(text ?? "m_c has \(library.displayName(current.name)).")
                continue
            }
            var mortality = current.mortality
            if clan.leader == id, mortality != 0 { mortality = max(1, Int(Double(mortality) * 0.7)) }
            if mortality != 0, oneIn(mortality, &rng) {
                let display = library.displayName(current.name)
                let isLeader = clan.leader == id && clan.leaderLives > 1
                texts = [isLeader ? "m_c lost a life to \(display)." : "m_c died from complications caused by \(display)."]
                let history = "m_c died from complications caused by \(display)."
                events += loseLifeOrDie(id, cause: .misfortune, history: history, in: &clan, using: &rng).filter { if case .died = $0 { false } else { true } }
                break
            }
            if let text = giveRisks(current, for: id, healer: healer, skip: &skip, in: &clan, using: &rng) {
                texts.append(text)
            }
        }
        let health = [story(texts, for: id, healer: healer)].compactMap { $0 }
        return health + events + retireForDisability(id, in: &clan, using: &rng)
    }

    private func retireForDisability(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id], cat.isAlive, [.apprentice, .warrior].contains(cat.rank) else { return [] }
        for condition in cat.permanentConditions {
            guard let odds = ConditionLibrary.retirementOdds[condition.severity]?[cat.age], oneIn(odds, &rng) else { continue }
            let text: String
            if cat.age == .adolescent {
                text = "m_c decides {PRONOUN/m_c/subject}'d rather spend {PRONOUN/m_c/poss} time helping around camp and entertaining the kits; {PRONOUN/m_c/subject}{VERB/m_c/'re/'s} warmly welcomed into the elders' den."
            } else if clan.isAlive(clan.leader), cat.moons < 120 {
                text = "Seeing m_c struggling the last few moons, lead_name approaches {PRONOUN/m_c/object} and promises that no one would think less of {PRONOUN/m_c/object} for retiring early, and that {PRONOUN/m_c/subject} would still be a valuable member of the Clan as an elder. m_c agrees; later that day, {PRONOUN/m_c/poss} elder ceremony is held."
            } else {
                text = "m_c has decided to retire from normal Clan duty."
            }
            setRank(.elder, for: id, in: &clan, using: &rng)
            return [.story(StoryPick(template: text, cats: ["m_c": id]), .ceremony)]
        }
        return []
    }

    // MARK: - New conditions for healthy cats

    /// Clangen's `handle_injuries`: 6 in 450 each moon, 16 in 450 for risk-taking personalities.
    func rollInjury(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id], let library else { return [] }
        let roll = Int.random(in: 0..<(clan.war.isGoingBadly ? 225 : 450), using: &rng)
        let risky = ConditionLibrary.riskyTraits.contains(cat.personality.trait)
        var counts: [UUID: Int] = [:]
        guard roll <= (risky ? 15 : 5),
              var pick = library.injuryEvent(for: cat, in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
              addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) != nil
        else { return [] }
        applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
        applyEventEffects(pick, in: &clan, using: &rng)
        relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
        var events: [MoonEvent] = [.story(pick, .health)]
        for victim in pick.deaths {
            let (history, involved) = pick.deathHistory(for: victim)
            events += loseLifeOrDie(victim, cause: .misfortune, history: history, involved: involved, in: &clan, using: &rng).filter { if case .died = $0 { false } else { true } }
        }
        return events
    }

    /// Clangen's `handle_illnesses`: 11 in 500 each moon, picked by season.
    func rollIllness(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let library = conditions, let cat = clan[id], Int.random(in: 0..<500, using: &rng) <= 10,
              let weights = library.seasons[clan.season.rawValue], !weights.isEmpty
        else { return [] }
        var name = weighted(weights.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }, &rng)
        if name == "kittencough", !cat.rank.isBaby { name = "whitecough" }
        guard getIll(id, name, in: &clan, using: &rng) else { return [] }
        let text = library.strings("gain_illness_strings", name).randomElement(using: &rng) ?? "m_c has gotten \(library.displayName(name))."
        return [.story(StoryPick(template: text, cats: ["m_c": id]), .health)] + outbreak(from: id, in: &clan, using: &rng)
    }

    /// Clangen's `handle_outbreaks`: contagious illnesses spread in the colder seasons (fleas any time).
    func outbreak(from id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let library = conditions, let cat = clan[id] else { return [] }
        let living = clan.living
        let healthy = living.filter { !$0.isIll }
        guard Double(living.count - healthy.count) < Double(healthy.count) * 0.25 else { return [] }
        let healers = workingHealers(in: clan).count

        for illness in cat.illnesses where illness.infectiousness != 0 {
            guard oneIn(illness.infectiousness + 10 * healers, &rng) else { continue }
            guard [.leafFall, .leafBare].contains(clan.season) || illness.name == "fleas" else { continue }
            let pool = illness.name == "kittencough" ? healthy.filter { $0.rank.isBaby } : healthy
            var most = pool.count / 2
            if most < 2 { most = pool.count }
            guard most >= 2 else { return [] }
            let count = weighted((2...most).map { ($0, 1000 / $0) }, &rng)
            let caught = pool.shuffled(using: &rng).prefix(count).map(\.id).filter {
                getIll($0, illness.name, eventTriggered: true, in: &clan, using: &rng)
            }
            guard !caught.isEmpty else { return [] }
            let text: String = switch illness.name {
            case "kittencough": "Kittencough has spread around the nursery. multi_cat \(caught.count == 1 ? "is" : "are") affected."
            case "fleas": "Fleas have been hopping from pelt to pelt and now multi_cat \(caught.count == 1 ? "is" : caught.count == 2 ? "are both" : "are all") infested."
            default: "\(library.displayName(illness.name).prefix(1).uppercased() + library.displayName(illness.name).dropFirst()) has spread around the camp. multi_cat have been infected."
            }
            var pick = StoryPick(template: text, cats: [:])
            pick.groupCats = ["multi_cat": caught]
            return [.story(pick, .health)]
        }
        return []
    }

    /// Clangen's classic "basic treatment": each moon a medicine cat eases one condition per cat.
    func basicTreatment(in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let library = conditions else { return }
        let covered = isCovered(clan)
        let rank: [String: Int] = ["severe": 0, "major": 1, "minor": 2]
        let patients = clan.living.filter { !$0.conditions.isEmpty }.sorted {
            ($0.conditions.map { rank[$0.severity] ?? 2 }.min() ?? 2) < ($1.conditions.map { rank[$0.severity] ?? 2 }.min() ?? 2)
        }
        for patient in patients {
            if !covered, ![.medicineCat, .medicineApprentice].contains(patient.rank) { break }
            let ordered = patient.injuries + patient.illnesses + patient.permanentConditions
            guard let first = ordered.first, library.conditions[first.name]?.hasHerbs == true,
                  !(first.kind == .permanent && first.bornWith && first.moonsUntil >= 0),
                  let i = clan.index(of: patient.id),
                  let c = clan.cats[i].conditions.firstIndex(where: { $0.name == first.name && $0.kind == first.kind })
            else { continue }
            var effects: [String] = []
            if first.mortality != 0 { effects += ["mortality", "mortality", "mortality"] }
            if !first.risks.isEmpty { effects += ["risks", "risks"] }
            if first.duration > 1 { effects.append("duration") }
            switch effects.randomElement(using: &rng) {
            case "mortality": clan.cats[i].conditions[c].mortality += 4
            case "duration": clan.cats[i].conditions[c].duration = max(0, first.duration - 1)
            case "risks":
                for r in clan.cats[i].conditions[c].risks.indices { clan.cats[i].conditions[c].risks[r].chance += 4 }
            default: break
            }
        }
    }
}
