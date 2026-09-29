import Foundation

/// Clangen's relationship simulation: starting values, the per-moon interactions,
/// and how mates form, break up and move on.
struct RelationshipEngine: Sendable {
    let library: InteractionLibrary
    let template: TextTemplate

    enum Compatibility { case positive, neutral, negative }

    private static let maxInteractions = 4
    private static let maxInteractionsSpecial = 6

    // MARK: - Starting values

    /// Clangen's `init_all_relationships` with "random relation" on, for every founding pair.
    func initializeFounders(_ clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        let cats = clan.living
        for a in cats {
            for b in cats where a.id != b.id {
                var r = Relationship()
                if Int.random(in: 1...20, using: &rng) == 1 {
                    r.initialize(.like, Int.random(in: -25...5, using: &rng))
                    r.initialize(.respect, Int.random(in: -10...15, using: &rng))
                    r.initialize(.trust, Int.random(in: -15...5, using: &rng))
                    r.initialize(.comfort, Int.random(in: -15...10, using: &rng))
                } else {
                    r.initialize(.like, Int.random(in: -10...35, using: &rng))
                    r.initialize(.respect, Int.random(in: -10...25, using: &rng))
                    r.initialize(.trust, Int.random(in: -5...15, using: &rng))
                    r.initialize(.comfort, Int.random(in: -5...15, using: &rng))
                    if Int.random(in: 1...max(1, 100 - r[.like]), using: &rng) == 1,
                       a.moons > 11, b.moons > 11, a.age == b.age {
                        r.initialize(.romance, Int.random(in: 15...30, using: &rng))
                        r.initialize(.comfort, Int(Double(r[.comfort]) * 1.3))
                        r.initialize(.trust, Int(Double(r[.trust]) * 1.2))
                    }
                }
                clan.relationships[a.id, default: [:]][b.id] = r
            }
        }
    }

    /// Everyone gets a neutral relationship with new kits; parents and littermates start close.
    func initializeKits(_ kits: [UUID], parents: [UUID], in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        for kit in kits {
            for other in clan.living where other.id != kit {
                clan.relationships[kit, default: [:]][other.id] = Relationship()
                clan.relationships[other.id, default: [:]][kit] = Relationship()
            }
            for parent in parents where clan.isAlive(parent) {
                var y = Int.random(in: 0..<15, using: &rng)
                var toKit = Relationship()
                toKit.initialize(.like, 60 + y)
                toKit.initialize(.comfort, 70 + y)
                toKit.initialize(.respect, 30 + y)
                toKit.initialize(.trust, 60 + y)
                clan.relationships[parent, default: [:]][kit] = toKit

                y = Int.random(in: 0..<15, using: &rng)
                var toParent = Relationship()
                toParent.initialize(.like, 40 + y)
                toParent.initialize(.comfort, 70 + y)
                toParent.initialize(.respect, 30 + y)
                toParent.initialize(.trust, 60 + y)
                clan.relationships[kit, default: [:]][parent] = toParent
            }
            for sibling in kits where sibling != kit {
                let y = Int.random(in: 0..<15, using: &rng)
                var r = Relationship()
                r.initialize(.like, 20 + y)
                r.initialize(.comfort, 10 + y)
                r.initialize(.trust, 10 + y)
                clan.relationships[kit, default: [:]][sibling] = r
            }
        }
    }

    /// A newcomer starts neutral with everyone, then has a few welcoming interactions.
    func welcome(_ newcomer: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        for other in clan.living where other.id != newcomer {
            clan.relationships[newcomer, default: [:]][other.id] = Relationship()
            clan.relationships[other.id, default: [:]][newcomer] = Relationship()
        }
        var used: Set<UUID> = [newcomer]
        var events: [MoonEvent] = []
        for _ in 0..<4 where Bool.random(using: &rng) {
            let pool = clan.living.filter { $0.rank != .newborn && !used.contains($0.id) }
            guard let other = pool.randomElement(using: &rng) else { break }
            used.insert(other.id)
            if let event = interact(newcomer, other.id, kind: nil, joining: true, in: &clan, counts: &counts, using: &rng) {
                events.append(event)
            }
        }
        return events
    }

    // MARK: - Personality

    /// Clangen's personality compatibility: same trait, or facets within 4 of each other.
    func compatibility(_ a: Cat, _ b: Cat) -> Compatibility {
        Self.compatibility(a, b)
    }

    static func compatibility(_ a: Cat, _ b: Cat) -> Compatibility {
        if a.personality.trait == b.personality.trait { return .positive }
        let pa = a.personality, pb = b.personality
        let score = [
            (pa.lawfulness, pb.lawfulness), (pa.sociability, pb.sociability),
            (pa.aggression, pb.aggression), (pa.stability, pb.stability),
        ].reduce(0) { total, pair in
            let diff = abs(pair.0 - pair.1)
            return total + (diff <= 4 ? 1 : diff >= 6 ? -1 : 0)
        }
        return score >= 2 ? .positive : score <= -2 ? .negative : .neutral
    }

    // MARK: - Changing values

    /// Clangen's `change_relationship_values`: romance only moves between possible mates.
    func change(from: UUID, to: UUID, _ values: [RelationshipValue], by amount: Int, log: String?, in clan: inout Clan) {
        guard from != to, let a = clan[from], let b = clan[to] else { return }
        let romanceAllowed = clan.isPotentialMate(a, b, forLoveInterest: true) || a.mates.contains(to)
        clan.updateRelationship(from: from, to: to) { r in
            for value in values where value != .romance || romanceAllowed {
                r.add(value, amount)
            }
            if let log { r.addLog(log) }
        }
    }

    /// Clangen's `unpack_rel_block` for event `relationships` blocks.
    func apply(_ changes: [RelationshipChange], cats: [String: [UUID]], in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        for change in changes where !change.values.isEmpty {
            guard let from = resolve(change.from, cats: cats, in: clan, using: &rng),
                  let to = resolve(change.to, cats: cats, in: clan, using: &rng)
            else { continue }
            let postscript = change.amount > 0 ? " (positive effect)" : " (negative effect)"
            for a in from {
                for b in to where a != b {
                    let log = logText(change.logFrom, from: a, to: b, cats: cats, clan: clan).map { $0 + postscript }
                    self.change(from: a, to: b, change.values, by: change.amount, log: log, in: &clan)
                    if change.mutual {
                        let reverse = logText(change.logTo ?? change.logFrom, from: b, to: a, cats: cats, clan: clan).map { $0 + postscript }
                        self.change(from: b, to: a, change.values, by: change.amount, log: reverse, in: &clan)
                    }
                }
            }
        }
    }

    private func logText(_ text: String?, from: UUID, to: UUID, cats: [String: [UUID]], clan: Clan) -> String? {
        guard let text, let a = clan[from], let b = clan[to] else { return nil }
        var named: [String: Cat] = ["cat_from": a, "cat_to": b]
        for (abbr, ids) in cats where ids.count == 1 { named[abbr] = clan[ids[0]] }
        return template.resolve(text, cats: named, clan: clan)
    }

    private func resolve(_ tokens: [String], cats: [String: [UUID]], in clan: Clan, using rng: inout some RandomNumberGenerator) -> [UUID]? {
        let involved = Set(cats.values.joined())
        var result: [UUID] = []
        func facet(_ name: String) -> ((Cat) -> Bool)? {
            switch name {
            case "high_social": { $0.personality.sociability > 8 }
            case "low_social": { $0.personality.sociability <= 8 }
            case "high_lawful": { $0.personality.lawfulness > 8 }
            case "low_lawful": { $0.personality.lawfulness <= 8 }
            case "high_stable": { $0.personality.stability > 8 }
            case "low_stable": { $0.personality.stability <= 8 }
            case "high_aggress": { $0.personality.aggression > 8 }
            case "low_aggress": { $0.personality.aggression <= 8 }
            default: nil
            }
        }
        for token in tokens {
            let negated = token.hasPrefix("-")
            let name = negated ? String(token.dropFirst()) : token
            if let test = facet(name) {
                result = result.filter { id in clan[id].map { test($0) != negated } ?? false }
                continue
            }
            let found: [UUID]
            switch name {
            case "clan":
                found = clan.living.map(\.id).filter { !involved.contains($0) }
            case "some_clan":
                let pool = clan.living.map(\.id).filter { !involved.contains($0) }
                guard !pool.isEmpty else { return nil }
                let count = Int.random(in: 1...max(1, Int((Double(pool.count) / 8).rounded())), using: &rng)
                found = Array(pool.shuffled(using: &rng).prefix(count))
            default:
                found = cats[name] ?? []
            }
            if found.isEmpty, !negated { return nil }
            if negated {
                result.removeAll { found.contains($0) }
            } else {
                result += found.filter { !result.contains($0) }
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Each moon

    /// Clangen's `handle_relationships`: one pair interaction, maybe a group or romantic one,
    /// then mates moving on, breaking up and getting together.
    func moon(for id: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id], cat.isAlive, cat.rank != .newborn else { return [] }
        var events: [MoonEvent] = []

        let partners = clan.living.filter { $0.id != id && $0.rank != .newborn }
        if let other = partners.randomElement(using: &rng),
           let event = interact(id, other.id, kind: nil, joining: false, in: &clan, counts: &counts, using: &rng) {
            events.append(event)
        }
        if oneIn(5, &rng), underCap(id, clan, counts), let event = groupInteraction(id, in: &clan, counts: &counts, using: &rng) {
            events.append(event)
        }
        if let event = sameAgeInteraction(id, in: &clan, counts: &counts, using: &rng) {
            events.append(event)
        }
        if oneIn(16, &rng), let event = romanticInteraction(id, in: &clan, counts: &counts, using: &rng) {
            events.append(event)
        }
        events += matesAndBreakups(id, in: &clan, using: &rng)
        return events
    }

    private func underCap(_ id: UUID, _ clan: Clan, _ counts: [UUID: Int]) -> Bool {
        let special: Set<Rank> = [.leader, .deputy, .medicineCat, .mediator]
        let cap = clan[id].map { special.contains($0.rank) } == true ? Self.maxInteractionsSpecial : Self.maxInteractions
        return counts[id, default: 0] < cap
    }

    /// Clangen's pair interaction (`generate_pair_event`).
    private func interact(
        _ mainID: UUID, _ otherID: UUID, kind specific: RelationshipValue?, joining: Bool,
        in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator
    ) -> MoonEvent? {
        guard let main = clan[mainID], let other = clan[otherID], main.isAlive, other.isAlive, mainID != otherID else { return nil }
        let rel = clan.relationship(from: mainID, to: otherID) ?? Relationship()
        let compatibility = compatibility(main, other)

        var ballot = [true, false]
        if compatibility == .positive { ballot.append(true) }
        if compatibility == .negative { ballot.append(false) }
        for value in [RelationshipValue.like, .respect, .comfort, .trust] {
            let v = rel[value]
            ballot += Array(repeating: v > 0, count: abs(v) / 20)
        }
        let positive = pick(ballot, &rng)

        let kind: RelationshipValue
        if let specific {
            kind = specific
        } else {
            var weights: [RelationshipValue: Int] = Dictionary(uniqueKeysWithValues: RelationshipValue.allCases.map { ($0, 1) })
            for value in RelationshipValue.allCases where rel[value] > 0 && (positive || value != .romance) {
                weights[value, default: 1] += rel[value] / 10
            }
            if main.mates.contains(otherID) {
                weights[.romance, default: 1] += 1
            } else if !clan.isPotentialMate(main, other, forLoveInterest: true) {
                weights[.romance] = nil
            }
            if !positive, rel[.romance] == 0 { weights[.romance] = nil }
            kind = weighted(RelationshipValue.allCases.compactMap { v in weights[v].map { (v, $0) } }, &rng)
        }
        let intensity = weighted([(Intensity.low, 3), (.medium, 4), (.high, 2)], &rng)

        var pool = library.pair(kind, intensity, positive: positive, joining: joining)
        let cats = ["m_c": [mainID], "r_c": [otherID]]
        var chosen: Interaction?
        while !pool.isEmpty {
            let candidate = pool.remove(at: weighted(Array(zip(pool.indices, pool.map(\.weight))), &rng))
            if candidate.main?.matches(main) ?? true, candidate.random?.matches(other) ?? true,
               candidate.rules.allSatisfy({ $0.holds(cats, clan, partial: false) }) {
                chosen = candidate
                break
            }
        }
        guard let chosen, let text = chosen.strings.randomElement(using: &rng) else { return nil }

        var amount = positive ? intensity.amount : -intensity.amount
        if compatibility == .positive { amount += 5 }
        if compatibility == .negative { amount -= 5 }
        let effect = "\(intensity.rawValue) \(positive ? "positive" : "negative") effect"
        clan.updateRelationship(from: mainID, to: otherID) { $0.add(kind, amount) }

        counts[mainID, default: 0] += 1
        counts[otherID, default: 0] += 1
        apply(chosen.changes, cats: cats, in: &clan, using: &rng)
        return .story(StoryPick(template: "\(text) (\(effect))", cats: ["m_c": mainID, "r_c": otherID]), .interaction)
    }

    private func groupInteraction(_ mainID: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> MoonEvent? {
        guard let main = clan[mainID] else { return nil }
        let positive = Bool.random(using: &rng)
        let intensity = weighted([(Intensity.low, 2), (.medium, 3), (.high, 1)], &rng)
        let candidates = clan.living.filter { $0.id != mainID && $0.rank != .newborn }
        var pool = library.group(intensity, positive: positive)

        while !pool.isEmpty {
            let event = pool.remove(at: weighted(Array(zip(pool.indices, pool.map(\.weight))), &rng))
            guard event.main?.matches(main) ?? true else { continue }
            let target = pick([2, 3, 4], &rng)
            var members: [UUID] = []
            for cat in candidates.shuffled(using: &rng) where event.group?.matches(cat) ?? true {
                let trial = ["m_c": [mainID], "multi_cat": members + [cat.id]]
                if event.rules.allSatisfy({ $0.holds(trial, clan, partial: false) }) { members.append(cat.id) }
                if members.count == target { break }
            }
            guard members.count >= 2, let text = event.strings.randomElement(using: &rng) else { continue }

            for id in [mainID] + members { counts[id, default: 0] += 1 }
            let names = members.compactMap { clan[$0] }
            let effect = "\(intensity.rawValue) \(positive ? "positive" : "negative") effect"
            var pick = StoryPick(template: "\(text) (\(effect))", cats: ["m_c": mainID])
            pick.groupCats = ["multi_cat": names.map(\.id)]
            apply(event.changes, cats: pick.allCats, in: &clan, using: &rng)
            return .story(pick, .interaction)
        }
        return nil
    }

    /// An interaction with a cat of similar age, so friendships and couples form among peers.
    /// Clangen intends this but never runs it (its length check is `< 0`); KittyClan enables it.
    private func sameAgeInteraction(_ id: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> MoonEvent? {
        guard let cat = clan[id], underCap(id, clan, counts) else { return nil }
        let range = min(40, Int(Double(cat.moons) * 0.4))
        let peers = clan.living.filter { other in
            other.id != id && other.rank != .newborn && abs(other.moons - cat.moons) <= range
                && clan.relationship(from: id, to: other.id) != nil
        }
        guard let other = peers.randomElement(using: &rng), underCap(other.id, clan, counts) else { return nil }
        return interact(id, other.id, kind: nil, joining: false, in: &clan, counts: &counts, using: &rng)
    }

    /// Clangen's 1-in-16 romantic interaction, usually with a mate or someone the cat fancies.
    private func romanticInteraction(_ id: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> MoonEvent? {
        guard let cat = clan[id], cat.moons >= 12, underCap(id, clan, counts) else { return nil }
        let free = clan.living.filter { clan.isPotentialMate($0, cat, forLoveInterest: true) }
        let interested = free.filter { (clan.relationship(from: id, to: $0.id)?[.romance] ?? 0) > 0 }
        var pool = switch interested.count {
        case 1...2: free + interested + interested
        case 3...: interested
        default: free
        }
        pool = pool.filter { other in
            let there = clan.relationship(from: id, to: other.id) ?? Relationship()
            let back = clan.relationship(from: other.id, to: id) ?? Relationship()
            return (there[.like] > 10 || there[.comfort] > 10) && (back[.like] > 10 || back[.comfort] > 10)
        }
        if !cat.mates.isEmpty {
            let odds = 15 - cat.mates.reduce(0) { $0 + (clan.relationship(from: id, to: $1)?[.romance] ?? 0) / 20 }
            if Int.random(in: 0..<max(odds, 1), using: &rng) != 0 {
                pool = cat.mates.compactMap { clan[$0] }.filter(\.isAlive)
            }
        }
        guard let other = pool.randomElement(using: &rng) else { return nil }
        return interact(id, other.id, kind: .romance, joining: false, in: &clan, counts: &counts, using: &rng)
    }

    // MARK: - Mates

    func setMates(_ a: UUID, _ b: UUID, in clan: inout Clan) {
        guard let i = clan.index(of: a), let j = clan.index(of: b) else { return }
        if !clan.cats[i].mates.contains(b) { clan.cats[i].mates.append(b) }
        if !clan.cats[j].mates.contains(a) { clan.cats[j].mates.append(a) }
        clan.cats[i].previousMates.removeAll { $0 == b }
        clan.cats[j].previousMates.removeAll { $0 == a }
        for (x, y) in [(a, b), (b, a)] {
            clan.updateRelationship(from: x, to: y) {
                $0.add(.romance, 20)
                $0.add(.comfort, 20)
                $0.add(.trust, 10)
            }
        }
    }

    func unsetMates(_ a: UUID, _ b: UUID, in clan: inout Clan) {
        guard let i = clan.index(of: a), let j = clan.index(of: b) else { return }
        clan.cats[i].mates.removeAll { $0 == b }
        clan.cats[j].mates.removeAll { $0 == a }
        if !clan.cats[i].previousMates.contains(b) { clan.cats[i].previousMates.append(b) }
        if !clan.cats[j].previousMates.contains(a) { clan.cats[j].previousMates.append(a) }
    }

    private func matesAndBreakups(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        var events: [MoonEvent] = []

        for mateID in cat.mates {
            guard let mate = clan[mateID] else { continue }
            if mate.isDead, let died = mate.diedAtClanAge, clan.age - died >= 4 {
                var p = 0.4
                if cat.personality.stability > 8 { p -= 0.1 }
                if cat.personality.sociability < 8 { p -= 0.1 }
                if cat.personality.aggression < 8 { p -= 0.1 }
                if Double.random(in: 0..<1, using: &rng) <= p {
                    unsetMates(id, mateID, in: &clan)
                    events.append(.story(StoryPick(template: "m_c will always love r_c, but has decided to move on.", cats: ["m_c": id, "r_c": mateID]), .relationship))
                }
            } else if mate.isAlive, let event = breakup(id, mateID, in: &clan, using: &rng) {
                events.append(event)
            }
        }

        if let event = confession(id, in: &clan, using: &rng) { return events + [event] }
        return events + mutualInterest(id, in: &clan, using: &rng)
    }

    private func breakup(_ id: UUID, _ mateID: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> MoonEvent? {
        guard let cat = clan[id], let mate = clan[mateID] else { return nil }
        let rel = clan.relationship(from: id, to: mateID) ?? Relationship()
        guard rel.total <= 120 else { return nil }
        var chance = 30 + RelationshipValue.allCases.reduce(0) { $0 + rel[$1] / 10 }
        switch compatibility(cat, mate) {
        case .positive: chance += 5
        case .negative: chance -= 10
        case .neutral: break
        }
        guard oneIn(max(chance, 5), &rng) else { return nil }

        let back = clan.relationship(from: mateID, to: id) ?? Relationship()
        var weights = ["had_fight": 3, "decided_to_be_friends": 3, "lost_feelings": 2, "bad_breakup": 5, "chill_breakup": 5]
        if rel[.romance] < 40 { weights["chill_breakup", default: 0] += 2 }
        if rel[.romance] < 20 { weights["lost_feelings", default: 0] += 5 }
        if rel.total < 80 { weights["had_fight", default: 0] += 3; weights["bad_breakup", default: 0] += 2 }
        if rel[.like] > 40, back[.like] > 40 { weights["decided_to_be_friends", default: 0] += 5 }
        let kind = weighted(weights.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }, &rng)

        let reactions: [String: [RelationshipValue: Int]] = [
            "had_fight": [.romance: -20, .like: -10, .trust: -15],
            "decided_to_be_friends": [.romance: -50, .like: 30, .trust: 20, .comfort: 10, .respect: 10],
            "lost_feelings": [.romance: -30, .like: -10, .comfort: -10],
            "bad_breakup": [.romance: -20, .like: -10, .trust: -30, .comfort: -20, .respect: -10],
            "chill_breakup": [.romance: -20, .comfort: -10, .respect: 10],
        ]
        for (x, y) in [(id, mateID), (mateID, id)] {
            clan.updateRelationship(from: x, to: y) { r in
                for (value, amount) in reactions[kind] ?? [:] {
                    r.add(value, amount + Int.random(in: -10...10, using: &rng))
                }
            }
        }
        unsetMates(id, mateID, in: &clan)
        guard let text = library.breakups[kind]?.randomElement(using: &rng) else { return nil }
        return .story(StoryPick(template: text, cats: ["m_c": id, "r_c": mateID]), .relationship)
    }

    /// Whether existing mates are close enough to welcome a new one (Clangen's poly check).
    private func currentMatesAllow(_ a: Cat, _ b: Cat, in clan: Clan) -> Bool {
        func holds(_ x: UUID, _ y: UUID, _ need: [RelationshipValue: Int]) -> Bool {
            [(x, y), (y, x)].allSatisfy { clan.relationship(from: $0.0, to: $0.1)?.meets(need) ?? true }
        }
        for (cat, newcomer) in [(a, b), (b, a)] {
            for mate in cat.mates where clan.isAlive(mate) && mate != newcomer.id {
                guard holds(cat.id, mate, [.romance: 30, .comfort: 15, .trust: 25]),
                      holds(newcomer.id, mate, [.like: 15, .comfort: 15, .trust: 20])
                else { return false }
            }
        }
        return true
    }

    private func confession(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> MoonEvent? {
        guard let cat = clan[id] else { return nil }
        var best: (Cat, Relationship)?
        for (otherID, rel) in clan.relationships[id] ?? [:] where rel[.romance] > (best?.1[.romance] ?? 0) {
            guard let other = clan[otherID], other.isAlive, !cat.mates.contains(otherID),
                  clan.isPotentialMate(other, cat, forLoveInterest: true)
            else { continue }
            best = (other, rel)
        }
        guard let (other, rel) = best, rel.meets([.romance: 30, .like: 15, .comfort: 10]),
              currentMatesAllow(cat, other, in: clan),
              clan.relationship(from: other.id, to: id)?.meets([.romance: 17, .like: 15, .comfort: 10]) == true
        else { return nil }

        let makeup = other.previousMates.contains(id)
        let fromDelta: [RelationshipValue: Int] = makeup ? [.romance: 10, .trust: 5] : [.romance: 10, .comfort: 5]
        let toDelta: [RelationshipValue: Int] = makeup
            ? [.romance: 10, .comfort: 5, .trust: 5, .respect: 5]
            : [.romance: 10, .comfort: 5, .trust: 5]
        for (x, y, delta) in [(id, other.id, fromDelta), (other.id, id, toDelta)] {
            clan.updateRelationship(from: x, to: y) { r in
                for (value, amount) in delta { r.add(value, amount + Int.random(in: -5...5, using: &rng)) }
            }
        }
        setMates(id, other.id, in: &clan)
        let key = makeup ? "high_romantic_makeup" : "high_romantic"
        let text = library.becomeMates[key]?.randomElement(using: &rng) ?? "m_c and r_c have become mates."
        return .story(StoryPick(template: text, cats: ["m_c": id, "r_c": other.id]), .relationship)
    }

    private func mutualInterest(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id] else { return [] }
        let candidates = (clan.relationships[id] ?? [:]).keys.compactMap { clan[$0] }.filter { other in
            other.isAlive && !cat.mates.contains(other.id) && clan.isPotentialMate(cat, other)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        var events: [MoonEvent] = []
        for other in candidates.shuffled(using: &rng).prefix(max(candidates.count / 3, 1)) {
            let mates = oneIn(5, &rng)
            let friendsToLovers = oneIn(130, &rng)
            guard mates || friendsToLovers, let current = clan[id], currentMatesAllow(current, other, in: clan) else { continue }
            let there = clan.relationship(from: id, to: other.id) ?? Relationship()
            let back = clan.relationship(from: other.id, to: id) ?? Relationship()
            let makeup = other.previousMates.contains(id)
            let key: String
            if mates, there.meets([.romance: 20, .like: 30, .comfort: 20]), back.meets([.romance: 20, .like: 30, .comfort: 20]) {
                key = makeup ? "low_romantic_makeup" : "low_romantic"
            } else if friendsToLovers, there.meets([.like: 50, .comfort: 20]), back.meets([.like: 50, .comfort: 20]) {
                key = makeup ? "low_romantic_makeup" : "like_to_romance"
            } else {
                continue
            }
            clan.updateRelationship(from: id, to: other.id) { $0.add(.romance, 10) }
            clan.updateRelationship(from: other.id, to: id) { $0.add(.romance, 10) }
            setMates(id, other.id, in: &clan)
            let text = library.becomeMates[key]?.randomElement(using: &rng) ?? "m_c and r_c have become mates."
            events.append(.story(StoryPick(template: text, cats: ["m_c": id, "r_c": other.id]), .relationship))
        }
        return events
    }
}
