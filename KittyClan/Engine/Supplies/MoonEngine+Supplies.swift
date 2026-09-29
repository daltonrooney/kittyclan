import Foundation

/// Clangen's fresh-kill pile and herb supply (`clan_resources`). The pile and herb treatment only
/// run with prey and herbs on (Clangen's expanded mode); herb stores exist in every Clan.
extension MoonEngine {
    // MARK: - Prey needs

    static func preyRequirement(_ rank: Rank) -> Double {
        switch rank {
        case .leader, .deputy, .warrior: 3
        case .medicineCat, .mediator: 2
        case .medicineApprentice, .apprentice, .mediatorApprentice, .elder: 1.5
        case .kitten: 0.5
        case .newborn: 0.25
        }
    }

    /// Nursing queens (the mother of a living kit under 3 moons, else another parent) and the kits they feed.
    static func queens(in clan: Clan) -> (queens: Set<UUID>, fedKits: Set<UUID>) {
        var queens: Set<UUID> = []
        var fedKits: Set<UUID> = []
        for kit in clan.living where kit.rank.isBaby && kit.moons < 3 {
            let parents = kit.allParents.compactMap { clan[$0] }.filter { clan.isAlive($0.id) }
            guard let queen = parents.first(where: { $0.sex == .female }) ?? parents.first else { continue }
            queens.insert(queen.id)
            fedKits.insert(kit.id)
        }
        for id in clan.pregnancies.keys where clan.isAlive(id) { queens.insert(id) }
        return (queens, fedKits)
    }

    /// Clangen's `_update_needed_food`: what the Clan eats in a moon.
    static func preyNeeded(in clan: Clan) -> Double {
        let (queens, _) = queens(in: clan)
        var needed = 0.0
        for cat in clan.living {
            if cat.rank.isBaby {
                let hasQueen = cat.allParents.contains { clan.isAlive($0) }
                if !hasQueen { needed += preyRequirement(cat.rank) }
            } else {
                needed += preyRequirement(cat.rank)
            }
        }
        return needed + Double(queens.count) * (4 - 3)
    }

    private func maxNutrition(for cat: Cat, isQueen: Bool) -> Double {
        let requirement = isQueen ? 4 : Self.preyRequirement(cat.rank)
        return requirement * (cat.rank.isBaby || cat.rank == .elder ? 2 : 3)
    }

    /// Keeps every living cat's nutrition entry, rescaling it when their needs change.
    func updateNutrition(in clan: inout Clan) {
        let (queens, _) = Self.queens(in: clan)
        var updated: [UUID: Nutrition] = [:]
        for cat in clan.living {
            let maxScore = maxNutrition(for: cat, isQueen: queens.contains(cat.id))
            if var entry = clan.nutrition[cat.id] {
                if entry.maxScore != maxScore {
                    entry.currentScore = entry.currentScore / max(entry.maxScore, 0.01) * maxScore
                    entry.maxScore = maxScore
                }
                updated[cat.id] = entry
            } else {
                updated[cat.id] = Nutrition(maxScore: maxScore, currentScore: maxScore)
            }
        }
        clan.nutrition = updated
    }

    // MARK: - Each moon

    /// Start of the moon: prey spoils, the Clan eats, then the moon's catch comes in.
    /// - Parameter patrolled: whether any patrol went out last moon. With starvation off, a Clan
    ///   left to itself also gets Clangen's "hunting" focus catch.
    func freshKillMoon(in clan: inout Clan, patrolled: Bool = true, using rng: inout some RandomNumberGenerator) {
        guard clan.preyAndHerbs else { return }
        clan.freshKill.log = []
        let spoiled = clan.freshKill.age()
        if spoiled > 0 { clan.freshKill.log.append("\(Int(spoiled)) pieces of prey went bad.") }

        let before = clan.freshKill.total
        feed(clan.living.map(\.id), in: &clan, manual: false)
        let eaten = before - clan.freshKill.total
        if eaten > 0 { clan.freshKill.log.append("The Clan ate \(Int(eaten.rounded())) pieces of prey.") }

        var caught = autoCatch(in: clan, using: &rng)
        if !clan.canStarve, !patrolled, clan.focus != .hunting { caught += Self.huntingFocusCatch(in: clan) }
        clan.freshKill.add(caught)
        if caught > 0 { clan.freshKill.log.append("The Clan's hunters caught \(Int(caught)) pieces of prey this moon.") }
    }

    /// Clangen's moon catch: each hunting-rank cat brings in a little prey.
    private func autoCatch(in clan: Clan, using rng: inout some RandomNumberGenerator) -> Double {
        func catchList(_ cat: Cat) -> [Int] {
            if cat.isNotWorking { return [0, 0, 1] }
            return switch cat.rank {
            case .leader, .deputy, .warrior: [2, 3, 3, 4]
            case .apprentice: [1, 2, 2, 3]
            case .medicineCat: [0, 1, 1, 2]
            case .medicineApprentice: [0, 1]
            case .mediator: [0, 1, 2, 2]
            case .mediatorApprentice: [0, 1, 1]
            case .elder: [0, 1, 1]
            case .kitten: [0, 0, 1]
            case .newborn: [0]
            }
        }
        var hunters = clan.living.filter { [.leader, .deputy, .warrior, .apprentice].contains($0.rank) && !$0.isNotWorking }
        if hunters.isEmpty { hunters = clan.living.filter { !$0.isNotWorking } }
        if hunters.isEmpty { hunters = clan.living }
        return Double(hunters.reduce(0) { $0 + pick(catchList($1), &rng) })
    }

    /// Clangen's "hunting" Clan focus: 2 more prey per working warrior, deputy or leader, 1 per apprentice.
    static func huntingFocusCatch(in clan: Clan) -> Double {
        Double(clan.living.filter { !$0.isNotWorking }.reduce(0) { total, cat in
            total + ([.leader, .deputy, .warrior].contains(cat.rank) ? 2 : cat.rank == .apprentice ? 1 : 0)
        })
    }

    /// Clangen's `feed_cats` with the default "lowest rank first" order.
    /// Manual feeding only adds nutrition; the moon's feeding also takes it away when prey runs short.
    func feed(_ ids: [UUID], in clan: inout Clan, manual: Bool) {
        updateNutrition(in: &clan)
        let (queens, fedKits) = Self.queens(in: clan)
        let order: [Rank] = [
            .newborn, .kitten, .elder, .medicineCat, .medicineApprentice, .apprentice, .mediatorApprentice,
            .warrior, .mediator, .deputy, .leader,
        ]
        let chosen = Set(ids)
        let cats = clan.living.filter { chosen.contains($0.id) && !fedKits.contains($0.id) }
        let queenGroup = cats.filter { queens.contains($0.id) }.sorted { $0.moons < $1.moons }
        var ordered: [Cat] = []
        for rank in order {
            if rank == .elder { ordered += queenGroup }
            ordered += cats.filter { $0.rank == rank && !queens.contains($0.id) }.sorted { $0.moons < $1.moons }
        }

        let needed = Self.preyNeeded(in: clan)
        for cat in ordered {
            guard var entry = clan.nutrition[cat.id] else { continue }
            let requirement = queens.contains(cat.id) ? 4 : Self.preyRequirement(cat.rank)
            var allowed = requirement
            let total = clan.freshKill.total
            if entry.percentage < 100 {
                if total > needed * 2 { allowed += 2 }
                else if total > needed * 1.8 { allowed += 1.5 }
                else if total > needed * 1.2 { allowed += 1 }
                else if total > needed { allowed += 0.5 }
            }
            let taken = clan.freshKill.take(allowed)
            let short = allowed - taken
            if manual {
                entry.currentScore += taken
            } else if short > 0 {
                entry.currentScore -= short
            } else if entry.percentage < 100 {
                entry.currentScore += allowed - requirement
            }
            entry.currentScore = min(max(entry.currentScore, 0), entry.maxScore)
            clan.nutrition[cat.id] = entry
        }
    }

    /// Clangen's `handle_nutrient`: hungry cats become malnourished or starving and recover when fed.
    func hunger(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard clan.preyAndHerbs, let library = conditions, let cat = clan[id], var entry = clan.nutrition[id] else { return [] }
        if !clan.canStarve, entry.percentage <= 20 {
            entry.currentScore = entry.maxScore * 0.21
            clan.nutrition[id] = entry
        }
        let percentage = entry.percentage
        func say(_ file: String, _ name: String) -> MoonEvent? {
            library.strings(file, name).randomElement(using: &rng).map { .story(StoryPick(template: $0, cats: ["m_c": id]), .health) }
        }
        func remove(_ name: String) {
            if let i = clan.index(of: id) { clan.cats[i].conditions.removeAll { $0.name == name } }
        }

        if percentage <= 0 {
            let text = library.strings("illness_death_strings", "starving").randomElement(using: &rng) ?? "m_c starved to death."
            var events: [MoonEvent] = [.story(StoryPick(template: text, cats: ["m_c": id]), .death)]
            events += loseLifeOrDie(id, cause: .misfortune, history: "m_c starved to death when the Clan ran out of prey.", in: &clan, using: &rng).filter { if case .died = $0 { false } else { true } }
            if clan.isAlive(id) {
                clan.nutrition[id]?.currentScore = entry.maxScore * 0.46
                getIll(id, "malnourished", in: &clan, using: &rng)
            }
            return events
        }
        if percentage > 45, cat.has("malnourished") {
            remove("malnourished")
            return [say("illness_healed_strings", "malnourished")].compactMap { $0 }
        }
        if percentage > 20, cat.has("starving") {
            remove("starving")
            if percentage < 45 { getIll(id, "malnourished", in: &clan, using: &rng) }
            return [say("illness_healed_strings", "starving")].compactMap { $0 }
        }
        if percentage <= 20, !cat.has("starving") {
            remove("malnourished")
            getIll(id, "starving", in: &clan, using: &rng)
            return [say("gain_illness_strings", "starving")].compactMap { $0 }
        }
        if percentage <= 45, !cat.has("malnourished"), !cat.has("starving") {
            let name = cat.rank == .kitten || cat.rank == .elder ? "starving" : "malnourished"
            getIll(id, name, in: &clan, using: &rng)
            return [say("gain_illness_strings", name)].compactMap { $0 }
        }
        return []
    }

    // MARK: - Herbs

    /// Clangen's starting herb stores: each herb has a 1 in 4 chance to be stocked.
    func startingHerbs(clanSize: Int, using rng: inout some RandomNumberGenerator) -> HerbSupply {
        var supply = HerbSupply()
        guard let herbLibrary else { return supply }
        let low = Int((Double(clanSize) / 3).rounded())
        for herb in herbLibrary.herbs where oneIn(4, &rng) {
            supply.add(herb.name, Int.random(in: low...max(low, clanSize), using: &rng))
        }
        return supply
    }

    /// Herbs whose stores are lowest come first when gathering.
    private func herbsByNeed(in clan: Clan) -> [String] {
        (herbLibrary?.herbs.map(\.name) ?? []).sorted { clan.herbs.total(of: $0) < clan.herbs.total(of: $1) }
    }

    private static let seasonWeights: [Season: [Int]] = [
        .newleaf: [2, 3, 2], .greenleaf: [1, 2, 3], .leafFall: [2, 3, 2], .leafBare: [5, 2, 1],
    ]

    /// Clangen's `get_found_herbs`: SENSE finds more kinds of herb, CLEVER finds more of each.
    /// - Parameter bonus: the herb-gathering focus doubles the kinds found and the amount of each.
    func findHerbs(by cat: Cat, limit: Int? = nil, bonus: Bool = false, in clan: Clan, using rng: inout some RandomNumberGenerator) -> [String: Int] {
        guard let herbLibrary else { return [:] }
        let weights = Self.seasonWeights[clan.season] ?? [1, 1, 1]
        var kinds = (weighted(Array(zip([1, 2, 3], weights)), &rng) + 1 + (cat.skills.tier(of: .SENSE) ?? 0)) * (bonus ? 2 : 1)
        let cleverness = (1 + Double(cat.skills.tier(of: .CLEVER) ?? 0)) * (bonus ? 2 : 1)
        var remaining = limit
        var found: [String: Int] = [:]
        for name in herbsByNeed(in: clan) where kinds > 0 {
            guard let herb = herbLibrary.herb(name), case let rarity = herb.rarity(in: clan.biome, clan.season), rarity > 0,
                  oneIn(rarity, &rng)
            else { continue }
            var modifier = cleverness
            if rarity >= 5 { modifier /= 2 } else if rarity <= 2 { modifier += 1 }
            var amount = max(1, Int(Double(weighted(Array(zip([2, 3, 4], weights)), &rng)) * modifier))
            if let left = remaining { amount = min(amount, left) }
            found[name] = amount
            kinds -= 1
            if let left = remaining {
                remaining = left - amount
                if remaining! <= 0 { break }
            }
        }
        return found
    }

    /// Clangen's herb moon: gathered herbs join the stores, medicine cats gather,
    /// herbs treat conditions (with prey and herbs on), and old herbs expire.
    func herbMoon(in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let herbLibrary else { return }
        clan.herbs.log = []
        let healers = clan.living.filter { [.medicineCat, .medicineApprentice].contains($0.rank) && !$0.isNotWorking }

        for herb in clan.herbs.storage.keys where clan.herbs.collected[herb] == nil {
            clan.herbs.storage[herb]?.insert(0, at: 0)
        }
        for (herb, amount) in clan.herbs.collected where amount > 0 {
            clan.herbs.storage[herb, default: []].insert(amount, at: 0)
        }
        clan.herbs.collected = [:]

        for healer in healers {
            let found = findHerbs(by: healer, in: clan, using: &rng)
            for (herb, amount) in found { clan.herbs.add(herb, amount) }
            let name = factory.names.display(healer.name, rank: healer.rank)
            clan.herbs.log.append(found.isEmpty
                ? "\(name) didn't collect any herbs this moon."
                : "\(name) collected \(herbLibrary.describe(found)) during this moon.")
        }

        if clan.preyAndHerbs { treatWithHerbs(in: &clan, using: &rng) } else { basicTreatment(in: &clan, using: &rng) }

        var expired: [String] = []
        for herb in herbLibrary.herbs {
            guard var batches = clan.herbs.storage[herb.name], !batches.isEmpty else { continue }
            if batches.last == 0 { batches.removeLast() }
            if batches.count > herb.expiration {
                batches.removeLast()
                expired.append(herbLibrary.name(herb.name, count: 2))
            }
            clan.herbs.storage[herb.name] = batches.isEmpty ? nil : batches
        }
        if !expired.isEmpty {
            clan.herbs.log.append("Some stores of \(expired.joined(separator: ", ")) were too old to be of use anymore.")
        }
    }

    /// Clangen's `_use_herbs`: each condition is treated with the most plentiful herb that helps it.
    /// Stronger herbs help more. Without the right herbs, lasting conditions and redcough get worse.
    private func treatWithHerbs(in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let library = conditions, let herbLibrary else { return }
        let covered = clan.living.contains { [.medicineCat, .medicineApprentice].contains($0.rank) && !$0.isNotWorking }
        let severity: [String: Int] = ["severe": 0, "major": 1, "minor": 2]
        let patients = clan.living.filter { !$0.conditions.isEmpty }.sorted {
            ($0.conditions.map { severity[$0.severity] ?? 2 }.min() ?? 2) < ($1.conditions.map { severity[$0.severity] ?? 2 }.min() ?? 2)
        }
        for patient in patients {
            if !covered, ![.medicineCat, .medicineApprentice].contains(patient.rank) { continue }
            for condition in patient.injuries + patient.illnesses + patient.permanentConditions where condition.isRevealed {
                guard let info = library.conditions[condition.name], info.hasHerbs,
                      let i = clan.index(of: patient.id),
                      let c = clan.cats[i].conditions.firstIndex(where: { $0.name == condition.name && $0.kind == condition.kind })
                else { continue }
                var effects: [String] = []
                if condition.mortality != 0 { effects += ["mortality", "mortality", "mortality"] }
                if !condition.risks.isEmpty { effects += ["risks", "risks"] }
                if condition.duration > 1 { effects.append("duration") }
                guard let effect = effects.randomElement(using: &rng) else { continue }

                let helpful = info.herbs.values.flatMap { $0 }.filter { clan.herbs.total(of: $0) > 0 }
                guard let herb = helpful.max(by: { clan.herbs.total(of: $0) < clan.herbs.total(of: $1) }) else {
                    if condition.kind == .permanent || condition.name == "redcough", Double.random(in: 0..<1, using: &rng) > 0.3 {
                        for r in clan.cats[i].conditions[c].risks.indices {
                            clan.cats[i].conditions[c].risks[r].chance = max(2, clan.cats[i].conditions[c].risks[r].chance - Int.random(in: 1...3, using: &rng))
                        }
                        if condition.mortality != 0 {
                            clan.cats[i].conditions[c].mortality = max(2, condition.mortality - Int.random(in: 1...3, using: &rng))
                        }
                    }
                    continue
                }
                let amount = Int.random(in: 1...min(clan.herbs.total(of: herb), 3), using: &rng)
                let strength = info.herbs.filter { $0.value.contains(herb) }.map(\.key).max() ?? 1
                clan.herbs.remove(herb, amount)
                switch effect {
                case "mortality": clan.cats[i].conditions[c].mortality += 3 * strength + amount
                case "duration": clan.cats[i].conditions[c].duration = max(0, condition.duration - strength)
                default:
                    for r in clan.cats[i].conditions[c].risks.indices {
                        clan.cats[i].conditions[c].risks[r].chance += 3 * strength + amount
                    }
                }
                let name = factory.names.display(patient.name, rank: patient.rank)
                clan.herbs.log.append("\(name) was given \(amount) \(herbLibrary.name(herb, count: amount)) for \(library.displayName(condition.name)).")
            }
        }
    }

    /// Clangen's blood-loss check: a medicine cat with the right herbs stops the bleeding.
    func stopBleeding(for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        guard clan.living.contains(where: { $0.rank == .medicineCat && !$0.isNotWorking }) else { return false }
        let options = ["horsetail", "raspberry", "marigold", "cobwebs"].filter { clan.herbs.total(of: $0) > 0 }
        guard let herb = options.randomElement(using: &rng) else { return false }
        clan.herbs.remove(herb, 1)
        if let cat = clan[id] {
            clan.herbs.log.append("Herbs were used to stop blood loss for \(factory.names.display(cat.name, rank: cat.rank)).")
        }
        return true
    }
}

// MARK: - Event supplies

extension MoonEngine {
    /// A check for Clangen's event supply triggers (low, adequate, full, excess, empty).
    /// Campkeepers make events that halve or empty the stores less likely.
    /// Without prey and herbs, only unconditional herb events run, and their effects are ignored.
    func supplyCheck(for clan: Clan, using rng: inout some RandomNumberGenerator) -> EventLibrary.SupplyCheck {
        let expanded = clan.preyAndHerbs
        let avoid = 1 + clan.living.reduce(0) { $0 + ($1.skills.tier(of: .CAMP) ?? 0) }
        let allowBigLosses = oneIn(avoid, &rng)
        let old = clan.age >= 5
        let needed = Self.preyNeeded(in: clan)
        let prey = clan.freshKill.total
        let size = clan.living.count
        let herbNames = herbLibrary?.herbs.map(\.name) ?? []
        let herbs = clan.herbs

        return { blocks in
            guard !blocks.isEmpty else { return true }
            guard old else { return false }
            guard expanded else { return blocks.allSatisfy { $0.type != "freshkill" && $0.triggers == ["always"] } }
            for block in blocks {
                if ["reduce_half", "reduce_full"].contains(block.adjust), !allowBigLosses { return false }
                if block.triggers.contains("always") { continue }
                if block.type == "freshkill" {
                    let factor = max(2, 4 - Int((pow(Double(size) / 35, 2)).rounded()))
                    let threshold = Double(factor) * needed
                    let fits = block.triggers.contains { trigger in
                        switch trigger {
                        case "low": needed / 2 > prey
                        case "adequate": needed / 2 < prey && prey < needed
                        case "full": needed < prey && prey < threshold
                        case "excess": prey > threshold
                        default: false
                        }
                    }
                    if !fits { return false }
                } else {
                    if herbs.total <= 0, block.triggers.contains("empty") { continue }
                    let fits: Bool = switch block.type {
                    case "all_herb": block.triggers.contains(herbs.overallRating(herbs: herbNames, clanSize: size))
                    case "any_herb": herbNames.contains { block.triggers.contains(HerbSupply.rating(herbs.total(of: $0), clanSize: size)) }
                    default: block.triggers.contains(HerbSupply.rating(herbs.total(of: block.type), clanSize: size))
                    }
                    if !fits { return false }
                }
            }
            return true
        }
    }

    /// Applies an event's supply changes (only with prey and herbs on).
    func applySupplies(_ blocks: [SupplyBlock], in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard clan.preyAndHerbs, let herbLibrary else { return }
        let size = clan.living.count
        for block in blocks where !block.adjust.isEmpty {
            let divisor: Double? = switch block.adjust {
            case "reduce_full": 1
            case "reduce_half": 2
            case "reduce_quarter": 4
            case "reduce_eighth": 8
            default: nil
            }
            let increase = block.adjust.hasPrefix("increase_") ? Int(block.adjust.dropFirst("increase_".count)) : nil

            if block.type == "freshkill" {
                if let divisor { clan.freshKill.take((clan.freshKill.total / divisor).rounded(.down)) }
                if let increase { clan.freshKill.add(Double(increase)) }
                continue
            }
            let names = herbLibrary.herbs.map(\.name)
            let targets: [String] = switch block.type {
            case "all_herb": names
            case "any_herb": [names.filter {
                block.triggers.contains("always") || block.triggers.contains(HerbSupply.rating(clan.herbs.total(of: $0), clanSize: size))
            }.randomElement(using: &rng)].compactMap { $0 }
            default: [block.type]
            }
            var changed: [String: Int] = [:]
            for herb in targets {
                if let divisor {
                    let amount = Int(Double(clan.herbs.total(of: herb)) / divisor)
                    clan.herbs.remove(herb, amount)
                    if amount > 0 { changed[herb] = amount }
                } else if let increase {
                    clan.herbs.add(herb, increase)
                    changed[herb] = increase
                }
            }
            if !changed.isEmpty {
                clan.herbs.log.append("The Clan \(divisor == nil ? "gained" : "lost") \(herbLibrary.describe(changed)).")
            }
        }
    }
}
