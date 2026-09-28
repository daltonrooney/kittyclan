import Foundation

/// Clangen's neighbouring Clans: relations, war and the leader's den.
extension MoonEngine {
    /// Clangen's two temperament tables: rows by one facet, columns by another.
    static let temperaments: [[[String]]] = [
        [["cunning", "proud", "bloodthirsty"], ["amiable", "stoic", "wary"], ["gracious", "mellow", "logical"]],
        [["chaotic", "mercurial", "calculating"], ["eager", "observant", "adaptable"], ["decisive", "methodical", "steadfast"]],
    ]

    /// 3–5 neighbouring Clans with unique names and temperaments, starting neutral.
    func generateOtherClans(for clan: Clan, using rng: inout some RandomNumberGenerator) -> [OtherClan] {
        var clans: [OtherClan] = []
        var used: Set<String> = []
        for _ in 0..<Int.random(in: 3...5, using: &rng) {
            var prefix = factory.names.randomClanPrefix(using: &rng)
            while prefix == clan.prefix || clans.contains(where: { $0.prefix == prefix }) {
                prefix = factory.names.randomClanPrefix(using: &rng)
            }
            let temperament = Self.temperaments.map { table in
                pick(table.flatMap { $0 }.filter { !used.contains($0) }, &rng)
            }
            used.formUnion(temperament)
            clans.append(OtherClan(prefix: prefix, relations: Int.random(in: 8...12, using: &rng), temperament: temperament))
        }
        return clans
    }

    /// Clangen's player Clan temperament: the leader counts triple, the deputy double.
    static func temperament(of clan: Clan) -> [String] {
        let living = clan.living
        guard !living.isEmpty else { return ["stoic", "observant"] }
        func median(_ values: [Int]) -> Int? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        func facet(_ path: KeyPath<Personality, Int>) -> Int {
            var values: [Int] = []
            if let leader = clan[clan.leader], leader.isAlive { values += Array(repeating: leader.personality[keyPath: path], count: 3) }
            if let deputy = clan[clan.deputy], deputy.isAlive { values += Array(repeating: deputy.personality[keyPath: path], count: 2) }
            if let m = median(living.filter { $0.rank == .medicineCat }.map { $0.personality[keyPath: path] }) { values.append(m) }
            let others = living.filter { ![clan.leader, clan.deputy].contains($0.id) && $0.rank != .medicineCat }
            if let m = median(others.map { $0.personality[keyPath: path] }) { values.append(m) }
            return values.isEmpty ? 8 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }
        func bucket(_ value: Int) -> Int { value < 7 ? 0 : value <= 10 ? 1 : 2 }
        return [
            temperaments[0][bucket(facet(\.sociability))][bucket(facet(\.aggression))],
            temperaments[1][bucket(facet(\.lawfulness))][bucket(facet(\.stability))],
        ]
    }

    // MARK: - War

    /// Clangen's `check_war`: hostile neighbours may start a war; wars end once relations recover.
    func checkWar(in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard !clan.otherClans.isEmpty, clan.age > 4, let war = library?.war else { return [] }
        func threshold(_ other: OtherClan, base: Int) -> Int {
            if other.temperament.contains("bloodthirsty") { return base == 10 ? 12 : 10 }
            if !Set(other.temperament).isDisjoint(with: ["mellow", "amiable", "gracious"]) { return base == 10 ? 7 : 3 }
            return base
        }

        if let enemyID = clan.war.enemy, let i = clan.otherClans.firstIndex(where: { $0.id == enemyID }) {
            let limit = threshold(clan.otherClans[i], base: 10) - clan.war.duration
            clan.otherClans[i].setRelations(max(clan.otherClans[i].relations, 0))
            if clan.otherClans[i].relations >= limit, clan.war.duration > 1 {
                clan.otherClans[i].changeRelations(by: 2)
                clan.war = War()
                return notice(war.conclusion, about: enemyID, in: clan, using: &rng)
            }
            clan.war.duration += 1
            clan.war.trend = pick([War.Trend.relUp, .neutral, .relDown], &rng)
            switch clan.war.trend {
            case .relUp: clan.otherClans[i].changeRelations(by: 2)
            case .relDown where clan.otherClans[i].relations > 1: clan.otherClans[i].changeRelations(by: -1)
            default: break
            }
            return notice(war.progress[clan.war.trend.rawValue] ?? [], about: enemyID, in: clan, using: &rng)
        }
        if clan.war.enemy != nil { clan.war = War() }

        for other in clan.otherClans where other.relations <= threshold(other, base: 5) {
            if other.relations <= 0 || oneIn(other.relations, &rng) {
                clan.war = War(enemy: other.id, duration: 0, trend: .relDown)
                return notice(war.trigger, about: other.id, in: clan, using: &rng)
            }
        }
        return []
    }

    private func notice(_ lines: [String], about otherClan: UUID, in clan: Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let line = lines.filter({ Constraint.namedRolesExist(in: $0, clan: clan) }).randomElement(using: &rng) else { return [] }
        var pick = StoryPick(template: line, cats: [:])
        pick.otherClan = otherClan
        return [.story(pick, .clans)]
    }

    /// The Clan an event is about: during war usually the enemy (4 in 5 draws on bad moons,
    /// 1 in 2 otherwise), else a random neighbour.
    func otherClanForEvent(in clan: Clan, using rng: inout some RandomNumberGenerator) -> (clan: OtherClan?, war: Bool) {
        if let enemy = clan.otherClan(clan.war.enemy) {
            let chance = clan.war.trend == .relDown ? 5 : 2
            if Int.random(in: 1...chance, using: &rng) != 1 { return (enemy, true) }
        }
        return (clan.otherClans.randomElement(using: &rng), false)
    }

    // MARK: - Leader's den

    /// Who acts in the leader's den: the leader, else a working deputy, medicine cat, or experienced cat.
    static func leaderDenActor(in clan: Clan) -> Cat? {
        if let leader = clan[clan.leader], clan.isAlive(leader.id), !leader.isNotWorking { return leader }
        let working = clan.living.filter { !$0.isNotWorking }
        if let deputy = working.first(where: { $0.id == clan.deputy }) { return deputy }
        if let healer = working.first(where: { [.medicineCat, .medicineApprentice].contains($0.rank) }) { return healer }
        return working.filter { !$0.rank.isBaby }.max { $0.experience < $1.experience }
    }

    /// The two leader's den actions for a Clan's standing: (unfriendly, friendly).
    static func leaderDenActions(for standing: OtherClan.Standing) -> (String, String) {
        switch standing {
        case .ally: ("offend", "praise")
        case .neutral: ("provoke", "befriend")
        case .hostile: ("antagonize", "appease")
        }
    }

    /// Clangen's leader's den roll: Clans with similar temperaments get along; helpers do worse than the leader.
    static func leaderDenSucceeds(player: [String], other: [String], byLeader: Bool, using rng: inout some RandomNumberGenerator) -> Bool {
        var fail = 0.0
        for k in 0..<2 {
            guard let (pr, pc) = position(of: player[k], in: temperaments[k]),
                  let (or, oc) = position(of: other[k], in: temperaments[k])
            else { continue }
            let value = { (row: Int, col: Int) in [1, 3, 5][row] + col + 1 }
            var f = Double(abs(value(pr, pc) - value(or, oc))) / 10
            if pr != or { f += 0.1 }
            if Set([pr, or]) == [0, 2] { f += 0.15 }
            if pc != oc { f += 0.1 }
            if Set([pc, oc]) == [0, 2] { f += 0.15 }
            fail += f / 2
        }
        if !byLeader { fail *= 1.4 }
        return Double.random(in: 0..<1, using: &rng) >= fail
    }

    private static func position(of word: String, in table: [[String]]) -> (Int, Int)? {
        for (r, row) in table.enumerated() {
            if let c = row.firstIndex(of: word) { return (r, c) }
        }
        return nil
    }

    /// Resolves last moon's leader's den choices.
    func resolveLeaderDen(in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        let plans = [clan.leaderDenPlan, clan.outsiderDenPlan].compactMap { $0 }
        clan.leaderDenPlan = nil
        clan.outsiderDenPlan = nil
        return plans.flatMap { resolve($0, in: &clan, using: &rng) }
    }

    private func resolve(_ plan: LeaderDenPlan, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard clan.isAlive(plan.actor), let actor = clan[plan.actor], let den = library?.leaderDen else { return [] }
        switch plan.target {
        case .clan(let id):
            guard let other = clan.otherClan(id) else { return [] }
            let options = (plan.succeeded ? den.clanSuccess : den.clanFail).filter { outcome in
                outcome.interaction == plan.interaction
                    && (outcome.otherTemperament.contains("any") || !Set(outcome.otherTemperament).isDisjoint(with: other.temperament))
                    && (outcome.playerTemperament.contains("any") || !Set(outcome.playerTemperament).isDisjoint(with: plan.playerTemperament))
                    && (outcome.main?.matches(actor) ?? true)
            }
            guard let outcome = options.randomElement(using: &rng) else { return [] }
            clan.changeRelations(with: id, by: outcome.change)
            let suffix = outcome.change > 0 ? "improved" : outcome.change < 0 ? "worsened" : "are unchanged"
            var pick = StoryPick(template: outcome.text + " (o_c_n relations \(suffix == "are unchanged" ? "unchanged" : suffix).)", cats: ["m_c": plan.actor])
            pick.otherClan = id
            return [.story(pick, .clans)]
        case .outsider(let id):
            return resolveOutsiderDen(plan, outsider: id, actor: actor, in: &clan, using: &rng)
        }
    }
}
