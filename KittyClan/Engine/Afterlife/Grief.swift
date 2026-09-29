import Foundation

/// Clangen's death reactions (`events/death/death_reactions`): what a cat feels when someone dies.
struct GriefLibrary: Sendable {
    /// family → relationship file ("like", "neg_trust", …) → trait or "general" → "body"/"no_body" → lines.
    private let reactions: [String: [String: [String: [String: [String]]]]]

    init(directory: URL) throws {
        var reactions: [String: [String: [String: [String: [String]]]]] = [:]
        for family in ["general", "mate", "parent", "child", "sibling"] {
            let folder = directory.appending(path: "death_reactions/\(family)")
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension == "json" {
                let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "\(family)_", with: "")
                reactions[family, default: [:]][name] = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: [String]]] ?? [:]
            }
        }
        self.reactions = reactions
    }

    /// Clangen's `possible_death_reactions`: the general file's lines, plus the family file's
    /// (family files have no romance reactions).
    func lines(family: String, value: String, trait: String, body: Bool) -> [String] {
        let key = body ? "body" : "no_body"
        func from(_ family: String) -> [String] {
            let file = reactions[family]?[value] ?? [:]
            return (file["general"]?[key] ?? []) + (file[trait]?[key] ?? [])
        }
        var lines = from("general")
        if family != "general", value != "romance" { lines += from(family) }
        return lines
    }
}

extension MoonEngine {
    /// Clangen's `grief`: each Clan cat who cared strongly for the dead cat may be grief-stricken,
    /// think of them, or (if they disliked them) react coldly.
    func grieve(for deadID: UUID, body: Bool, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let grief, let dead = clan[deadID] else { return [] }
        var events: [MoonEvent] = []
        var bodyTreated = false
        let values: [RelationshipValue] = [.romance, .like, .trust, .comfort, .respect]

        for cat in clan.living where cat.moons >= 1 {
            guard let relationship = clan.relationship(from: cat.id, to: deadID) else { continue }
            let family = if cat.allParents.contains(deadID) {
                "child"
            } else if dead.allParents.contains(cat.id) {
                "parent"
            } else if !Set(cat.allParents).isDisjoint(with: dead.allParents) {
                "sibling"
            } else if cat.mates.contains(deadID) {
                "mate"
            } else {
                "general"
            }

            var veryHigh: [RelationshipValue] = []
            var high: [RelationshipValue] = []
            var veryLow: [RelationshipValue] = []
            for value in values {
                let v = relationship[value]
                if v >= 70 { veryHigh.append(value) }
                else if v >= 25 { high.append(value) }
                else if v <= -70 { veryLow.append(value) }
                else if v <= -25, oneIn(6, &rng) { veryLow.append(value) }
            }

            if !veryHigh.isEmpty {
                var chance = 3
                if cat.personality.stability < 5 { chance -= 1 }
                if family != "general" { chance -= 1 }
                if body, !bodyTreated, clan.herbs.total(of: "rosemary") > 0 {
                    clan.herbs.remove("rosemary", 1)
                    clan.herbs.log.append("Rosemary was used for \(factory.names.display(dead.name, rank: dead.rank))'s body.")
                    bodyTreated = true
                }
                if bodyTreated { chance += 1 }
                if oneIn(max(1, chance), &rng) {
                    let options = veryHigh.flatMap {
                        grief.lines(family: family, value: $0.rawValue, trait: cat.personality.trait, body: body)
                    }
                    if let line = options.randomElement(using: &rng) {
                        getIll(cat.id, "grief stricken", eventTriggered: true, in: &clan, using: &rng)
                        events.append(.story(StoryPick(template: line, cats: ["m_c": deadID, "r_c": cat.id]), .relationship))
                    }
                    continue
                }
            }
            if !veryHigh.isEmpty || !high.isEmpty, family != "general" || oneIn(5, &rng) {
                if let i = clan.index(of: cat.id) {
                    clan.cats[i].nextThought = body ? .onGriefTowardBody : .onGriefNoBody
                    clan.cats[i].nextThoughtAbout = deadID
                }
                continue
            }
            let cold = veryLow.flatMap {
                grief.lines(family: family, value: "neg_" + $0.rawValue, trait: cat.personality.trait, body: body)
            }
            if let line = cold.randomElement(using: &rng) {
                events.append(.story(StoryPick(template: line, cats: ["m_c": deadID, "r_c": cat.id]), .relationship))
            }
        }
        return events
    }

    /// Clangen's end-of-moon mourning notice; more than two deaths leave some cats shaken.
    func mourn(in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        let dead = clan.diedThisMoon.filter { clan[$0] != nil }
        clan.diedThisMoon = []
        guard !dead.isEmpty, !clan.living.isEmpty else { return [] }
        let afterlife = clan.guideAfterlife.label
        var events: [MoonEvent]
        if dead.count == 1 {
            events = [.story(StoryPick(template: "This past moon, m_c has taken {PRONOUN/m_c/poss} place in \(afterlife). c_n mourns the loss of their Clanmate, and {PRONOUN/m_c/poss} Clanmates will miss where {PRONOUN/m_c/subject} had been in their lives. Moments of {PRONOUN/m_c/poss} life are shared in stories around the circle of mourners as those that were closest to {PRONOUN/m_c/object} take {PRONOUN/m_c/object} to {PRONOUN/m_c/poss} final resting place.", cats: ["m_c": dead[0]]), .death)]
        } else {
            var pick = StoryPick(template: "The past moon, multi_cat have taken their place in \(afterlife). c_n mourns their loss, and their Clanmates will miss where they had been in their lives. Moments of their lives are shared in stories around the circle of mourners as those that were closest to them take them to their final resting place.", cats: [:])
            pick.groupCats["multi_cat"] = dead
            events = [.story(pick, .death)]
        }
        if dead.count > 2 {
            let count = max(Int(Double(clan.living.count) * Double(Int.random(in: 4...6, using: &rng)) / 100), 1)
            let shaken = clan.living.shuffled(using: &rng).prefix(count).map(\.id).filter {
                getInjured($0, "shock", lethal: false, in: &clan, using: &rng)
            }
            if !shaken.isEmpty {
                var pick = StoryPick(template: "So much grief and death has taken its toll on the cats of c_n. multi_cat \(shaken.count == 1 ? "is" : "are") particularly shaken by it.", cats: [:])
                pick.groupCats["multi_cat"] = shaken
                events.append(.story(pick, .health))
            }
        }
        return events
    }
}
