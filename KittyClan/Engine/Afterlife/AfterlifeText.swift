import Foundation

/// Profile text for the dead: how they died, how the afterlife took them, the guide's
/// backstory and a leader's nine-lives ceremony.
struct AfterlifeText: Sendable {
    let template: TextTemplate
    private let acceptance: [String: String]
    private let backstories: [String: String]

    private static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]

    init(directory: URL, template: TextTemplate) throws {
        self.template = template
        func strings(_ name: String) throws -> [String: String] {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "afterlife/\(name)")))
            return json as? [String: String] ?? [:]
        }
        acceptance = try strings("afterlife.en.json")
        backstories = try strings("backstories.en.json")
    }

    /// Clangen's `past_group`: "past StarClan warrior", or "past warrior" for the guide and outsiders.
    func pastRank(of cat: Cat, in clan: Clan) -> String? {
        guard cat.isDead, let afterlife = cat.afterlife else { return nil }
        let rank = (cat.lastClanRank ?? cat.rank).rawValue
        let isOutsider = clan.outsiders.contains { $0.id == cat.id }
        return cat.id == clan.guide || isOutsider ? "past \(rank)" : "past \(afterlife.label) \(rank)"
    }

    /// Clangen's `moons_age_in_death`.
    func deadFor(_ cat: Cat) -> String? {
        guard cat.isDead else { return nil }
        return cat.deadFor == 1 ? "dead for 1 moon" : "dead for \(cat.deadFor) moons"
    }

    func backstory(of cat: Cat, in clan: Clan) -> String? {
        guard let key = cat.backstory, let text = backstories[key] else { return nil }
        return template.resolve(text, cats: ["m_c": cat], clan: clan)
    }

    /// Clangen's short backstory label, e.g. "formerly a loner".
    func backstoryLabel(of cat: Cat) -> String? {
        guard let key = cat.backstory, let category = Backstories.bundled.category(of: key) else { return nil }
        return backstories[category]
    }

    /// Clangen's `get_backstory_text`: another Clan's cats and outsiders who never lived in the Clan
    /// are described by who they are now; everyone else by their backstory, then whether they're lost or exiled.
    func profileBackstory(of cat: Cat, in clan: Clan) -> String {
        let isOutsider = clan.outsiders.contains { $0.id == cat.id }
        var text: String
        if isOutsider, cat.belongsToOtherClan, let name = clan.otherClan(cat.otherClan)?.name {
            text = (backstories["other_clan_cat"] ?? "This cat is part of %{clan}.").replacingOccurrences(of: "%{clan}", with: name)
            if cat.isDead { text = text.replacingOccurrences(of: "is part", with: "was part") }
        } else if isOutsider, !cat.isLost, !cat.isExiled {
            let key = cat.isDead ? "cats_outside_the_clan_dead" : "cats_outside_the_clan"
            text = (backstories[key] ?? "This cat is a %{status}.").replacingOccurrences(of: "%{status}", with: cat.social.rawValue)
        } else if let key = cat.backstory, let story = backstories[key] {
            text = story
        } else {
            text = (backstories["unknown"] ?? "%{name}'s past history is unknown.").replacingOccurrences(of: "%{name}", with: "m_c")
        }
        text = text.replacingOccurrences(of: "This cat", with: "m_c")
        if isOutsider, cat.isLost { text += " " + (backstories["currently_lost"] ?? "").replacingOccurrences(of: "%{name}", with: "m_c") }
        if isOutsider, cat.isExiled { text += " " + (backstories["currently_exiled"] ?? "").replacingOccurrences(of: "%{name}", with: "m_c") }
        return template.resolve(text.trimmingCharacters(in: .whitespaces), cats: ["m_c": cat], clan: clan)
    }

    /// Clangen's afterlife acceptance text, shown at the end of a dead cat's history.
    func acceptance(of cat: Cat, in clan: Clan) -> String? {
        guard let key = cat.afterlifeAcceptance, let text = acceptance[key] else { return nil }
        return template.resolve(text, cats: ["m_c": cat], clan: clan)
    }

    /// Clangen's `get_death_text`: one line per death, with leaders' lives numbered.
    func deaths(of cat: Cat, in clan: Clan) -> [String] {
        let wasLeader = cat.rank == .leader || cat.lastClanRank == .leader
        var lines: [String] = []
        var extraLives = 0
        for (index, record) in cat.deaths.enumerated() {
            if wasLeader, record.text == DeathRecord.multiLives {
                extraLives += 1
                continue
            }
            var cats = ["m_c": cat]
            if let other = Self.cat(record.involved, in: clan, standIn: cat) { cats["r_c"] = other }
            var text = template.resolve(record.text, cats: cats, clan: clan)
            if wasLeader {
                let lives = ((index - extraLives)...index).map { Self.ordinals[min($0, Self.ordinals.count - 1)] }
                let label = switch lives.count {
                case 1: "\(lives[0].capitalized) life:"
                case 2: "\(lives[0].capitalized) and \(lives[1]) lives:"
                default: "\(lives[0].capitalized) through \(lives[lives.count - 1]) lives:"
                }
                text = "\(label) \(text)"
                extraLives = 0
            }
            if !text.hasSuffix(".") { text += "." }
            var line = "\(text) (moon \(record.moon))"
            if let murder = cat.murders.first(where: { $0.victim == cat.id && $0.moon == record.moon }) {
                line += " " + status(of: murder, in: clan)
            }
            lines.append(line)
        }
        return lines
    }

    /// Clangen's `get_murder_text`: the murders this cat has committed.
    func murders(by cat: Cat, in clan: Clan) -> [String] {
        cat.murders.filter { $0.murderer == cat.id }.map { murder in
            let victim = clan[murder.victim].map { template.names.display($0.name, rank: $0.rank) }
                ?? clan.faded.first { $0.id == murder.victim }.map { template.names.display($0.name, rank: $0.rank) } ?? "a Clanmate"
            let name = template.names.display(cat.name, rank: cat.rank)
            return "\(name) murdered \(victim). (moon \(murder.moon)) " + status(of: murder, in: clan)
        }
    }

    /// Clangen's `get_murder_status_text`.
    private func status(of murder: MurderRecord, in clan: Clan) -> String {
        if murder.revealedToClan { return "The Clan knows." }
        let aware = murder.aware.compactMap { clan[$0] }.map { template.names.display($0.name, rank: $0.rank) }
        return (aware.isEmpty ? "" : "\(TextTemplate.joined(aware)) \(aware.count == 1 ? "knows" : "know"). ") + "The Clan is unaware."
    }

    /// The leader's nine-lives ceremony as paragraphs.
    func ceremony(of leader: Cat, in clan: Clan) -> [String] {
        var asWarrior = leader
        asWarrior.rank = .warrior
        let starName = leader.name.prefix + "star"
        return leader.leaderCeremony.map { line in
            var cats = ["m_c": asWarrior]
            if let giver = Self.cat(line.giver, in: clan, standIn: leader) { cats["r_c"] = giver }
            var extras = ["m_c_star": starName]
            if let virtue = line.virtue {
                extras["[virtue]"] = template.resolve(virtue, cats: cats, clan: clan)
            }
            if let lives = line.extraLives {
                extras["[life_num]"] = lives == 1 ? "1 life" : "\(lives) lives"
            }
            return template.resolve(line.text, cats: cats, clan: clan, extras: extras)
        }
    }

    /// A cat by ID; a faded cat is stood in for by `standIn` wearing its name and pronouns.
    private static func cat(_ id: UUID?, in clan: Clan, standIn: Cat) -> Cat? {
        if let cat = clan[id] { return cat }
        guard let faded = clan.faded.first(where: { $0.id == id }) else { return nil }
        var cat = standIn
        cat.name = faded.name
        cat.rank = faded.rank
        cat.pronouns = faded.pronouns
        return cat
    }
}
