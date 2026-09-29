import Foundation

/// Clangen's Clan focus (`events_module/focus.py`), run after the cat loop and before the herb moon.
extension MoonEngine {
    /// The warriors' den "Change Focus". Returns false if blocked, on cooldown, unchanged, or missing targets.
    @discardableResult
    func setFocus(_ focus: ClanFocus, targets: [UUID] = [], in clan: inout Clan) -> Bool {
        let targets = focus.targetsOtherClans ? targets.filter { clan.otherClan($0) != nil } : []
        guard clan.canChangeFocus, clan.focusBlock(focus) == nil, !focus.targetsOtherClans || !targets.isEmpty,
              focus != clan.focus || targets != clan.focusTargets
        else { return false }
        clan.focus = focus
        clan.focusTargets = targets
        clan.focusChangedAt = clan.age
        return true
    }

    /// This moon's focus effects. Herb lines go to `herbLog`, to be shown after the herb moon's own.
    func focusMoon(in clan: inout Clan, herbLog: inout [String], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        if clan.focus.needsPreyAndHerbs, !clan.preyAndHerbs { return [] }
        let working = clan.living.filter { !$0.isNotWorking }
        let warriors = working.filter { $0.rank.isWarriorLike }
        let targets = clan.focusTargets.compactMap { clan.otherClan($0) }
        let clanNames = TextTemplate.joined(targets.map(\.name))
        func note(_ text: String, _ kind: LogEntry.Kind = .info, cats: [UUID] = []) -> MoonEvent {
            var pick = StoryPick(template: text, cats: [:])
            pick.groupCats["focus"] = cats
            return .story(pick, kind)
        }
        func plural(_ count: Int, _ one: String, _ many: String) -> String { count == 1 ? one : many }
        func preyText(_ amount: Int) -> String {
            amount == 0 ? "Despite the focus of the Clan, no additional prey could be gathered."
                : "With the heightened focus of the Clan, \(amount) additional \(plural(amount, "piece of prey was", "pieces of prey were")) gathered."
        }
        func addPrey(_ amount: Int, _ text: String) {
            clan.freshKill.add(Double(amount))
            clan.freshKill.log.append(text)
        }
        func gather(_ gatherers: [Cat], bonus: Bool) -> Int {
            var total = 0
            var names: Set<String> = []
            for cat in gatherers {
                for (herb, amount) in findHerbs(by: cat, bonus: bonus, in: clan, using: &rng) {
                    clan.herbs.add(herb, amount)
                    total += amount
                    names.insert(herb)
                }
            }
            if let herbLibrary, !names.isEmpty {
                let list = TextTemplate.joined(names.sorted().map { herbLibrary.name($0, count: 2) })
                herbLog.append("With the additional focus of the Clan, the following herbs were gathered: \(list).")
            }
            return total
        }
        func herbText(_ count: Int) -> String {
            count == 0 ? "Despite the focus of the Clan, no additional herbs could be gathered."
                : "With the focus of the Clan, \(count) \(plural(count, "herb was", "herbs were")) gathered."
        }

        switch clan.focus {
        case .businessAsUsual:
            return []
        case .hunting:
            let amount = Int(Self.huntingFocusCatch(in: clan))
            let text = preyText(amount)
            addPrey(amount, text)
            return [note(text)]
        case .herbGathering:
            let healers = working.filter { [.medicineCat, .medicineApprentice].contains($0.rank) }
            return [note(herbText(gather(healers, bonus: !warriors.isEmpty)))]
        case .threatenOutsiders:
            clan.changeReputation(by: -5)
            return [note("The Clan makes their distaste of non-Clan cats clear, diminishing their relationship with outsiders.")]
        case .seekOutsiders:
            clan.changeReputation(by: 5)
            return [note("The Clan attempts to establish ties to the outsiders on their borders, improving their relationship with outsiders.")]
        case .restAndRecover:
            return [note("The Clan takes it easy this moon, hoping to recover their strength.")]
        case .sabotageOtherClans, .aidOtherClans:
            guard !targets.isEmpty else { return [] }
            let aid = clan.focus == .aidOtherClans
            for other in targets { clan.changeRelations(with: other.id, by: aid ? 2 : -2) }
            return [note(aid ? "The Clan does what they can to aid \(clanNames); improving diplomatic ties."
                : "The Clan does what they can to facilitate the downfall of \(clanNames); damaging diplomatic ties.", .clans)]
        case .raidOtherClans:
            guard !targets.isEmpty else { return [] }
            let prey = warriors.reduce(0) { total, _ in total + weighted([(0, 3), (1, 4), (2, 1)], &rng) }
            var herbsLeft = warriors.reduce(0) { total, _ in total + weighted([(0, 8), (1, 2), (2, 1)], &rng) }
            let herbCount = herbsLeft
            var snatched: [String: Int] = [:]
            if let herbLibrary {
                while herbsLeft > 0 {
                    let amount = Int.random(in: 1...herbsLeft, using: &rng)
                    snatched[pick(herbLibrary.herbs.map(\.name), &rng), default: 0] += amount
                    herbsLeft -= amount
                }
                for (herb, amount) in snatched { clan.herbs.add(herb, amount) }
                if !snatched.isEmpty { herbLog.append("The warriors snatched \(herbLibrary.describe(snatched)).") }
            }
            let chance = max(2, 18 - 3 * targets.count)
            let injuries = [("claw-wound", 15), ("cat bite", 15), ("torn pelt", 15), ("torn ear", 15), ("bite-wound", 10),
                            ("sprain", 10), ("bruises", 7), ("sore", 6), ("small cut", 4), ("cracked pads", 3)]
            var injured: [UUID] = []
            for cat in warriors where oneIn(chance, &rng) {
                if getInjured(cat.id, weighted(injuries, &rng), in: &clan, using: &rng) { injured.append(cat.id) }
            }
            for other in targets { clan.changeRelations(with: other.id, by: -3) }
            var parts: [String] = []
            if prey > 0 {
                let text = "\(prey) \(plural(prey, "piece of prey was", "pieces of prey were")) acquired."
                addPrey(prey, text)
                parts.append(text)
            }
            if herbCount > 0 { parts.append("The warriors snatched \(herbCount) \(plural(herbCount, "herb", "herbs")).") }
            parts.append("Relations with \(clanNames) were deeply impacted by the raids.")
            var events = [note(parts.joined(separator: " "), .clans)]
            if !injured.isEmpty {
                events.append(note(injured.count == 1 ? "A cat got injured while raiding other Clans." : "Multiple cats got injured while raiding other Clans.", .health, cats: injured))
            }
            return events
        case .hoarding:
            let healers = working.filter { $0.rank == .medicineCat }
            let injuries = [("cracked pads", 15), ("sore", 15), ("bruises", 15), ("sprain", 12), ("small cut", 10),
                            ("torn pelt", 10), ("torn ear", 10), ("claw-wound", 5), ("bite-wound", 5), ("cat bite", 3)]
            var injured: [UUID] = []
            var sick: [UUID] = []
            for cat in warriors + healers {
                if oneIn(cat.rank == .medicineCat ? 35 : 25, &rng) {
                    if getInjured(cat.id, weighted(injuries, &rng), in: &clan, using: &rng) { injured.append(cat.id) }
                } else if oneIn(35, &rng) {
                    if getIll(cat.id, weighted([("running nose", 5), ("whitecough", 1)], &rng), in: &clan, using: &rng) { sick.append(cat.id) }
                }
            }
            var parts: [String] = []
            if !healers.isEmpty { parts.append(herbText(gather(healers, bonus: false))) }
            if !warriors.isEmpty {
                let text = preyText(warriors.count)
                addPrey(warriors.count, text)
                parts.append(text)
            }
            var events: [MoonEvent] = parts.isEmpty ? [] : [note(parts.joined(separator: " "))]
            if !injured.isEmpty {
                events.append(note(injured.count == 1 ? "A cat got injured due to hoarding herbs and prey." : "Multiple cats got injured due to hoarding herbs and prey.", .health, cats: injured))
            }
            if !sick.isEmpty {
                events.append(note(sick.count == 1 ? "A cat got sick due to hoarding herbs and prey." : "Multiple cats got sick due to hoarding herbs and prey.", .health, cats: sick))
            }
            return events
        }
    }
}
