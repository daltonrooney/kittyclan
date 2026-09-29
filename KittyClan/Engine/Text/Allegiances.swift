import Foundation

/// Clangen's Allegiances screen: the living Clan listed by rank, as in the front of a Warriors book.
struct Allegiances: Sendable {
    struct Entry: Identifiable, Hashable, Sendable {
        let id: Cat.ID
        /// The name in capitals, e.g. "FIRESTAR".
        let name: String
        /// E.g. "a ginger tabby tom".
        let description: String
        /// Which kits a queen is caring for.
        var caringFor: String?
        /// Apprentices' names in capitals.
        var apprentices: [String] = []

        /// The apprentice line, e.g. "APPRENTICES: ASHPAW AND FERNPAW".
        var apprenticeLine: String? {
            guard !apprentices.isEmpty else { return nil }
            let label = apprentices.count == 1 ? "APPRENTICE" : "APPRENTICES"
            return "\(label): \(AppearanceText.list(apprentices).uppercased())"
        }
    }

    struct Section: Identifiable, Hashable, Sendable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    let clanName: String
    let sections: [Section]

    /// Builds the roster with Clangen's `get_allegiances_text` rules.
    init(clan: Clan, name: (Cat) -> String, describe: (Cat, _ short: Bool) -> String) {
        clanName = clan.displayName
        let living = clan.living

        func entry(_ cat: Cat, caringFor: String? = nil) -> Entry {
            Entry(
                id: cat.id,
                name: name(cat).uppercased(),
                description: describe(cat, false),
                caringFor: caringFor,
                apprentices: cat.apprentices.compactMap { clan[$0] }.map { name($0).uppercased() }
            )
        }

        var meds: [Cat] = [], mediators: [Cat] = [], warriors: [Cat] = [], apprentices: [Cat] = []
        var elders: [Cat] = []
        for cat in living {
            switch cat.rank {
            case .medicineCat: meds.append(cat)
            case .warrior: warriors.append(cat)
            case .mediator: mediators.append(cat)
            case .elder: elders.append(cat)
            case let rank where rank.isApprentice: apprentices.append(cat)
            default: break
            }
        }
        let (queens, unattended) = Self.queens(in: clan)
        for (queen, _) in queens {
            if let i = warriors.firstIndex(where: { $0.id == queen }) {
                warriors.remove(at: i)
            } else if let i = elders.firstIndex(where: { $0.id == queen }) {
                elders.remove(at: i)
            }
        }

        var sections: [Section] = []
        func add(_ one: String, _ many: String, _ cats: [Cat], plural: Bool? = nil) {
            guard !cats.isEmpty else { return }
            sections.append(Section(title: (plural ?? (cats.count > 1)) ? many : one, entries: cats.map { entry($0) }))
        }
        if let leader = clan[clan.leader], clan.isAlive(leader.id) { add("LEADER", "LEADER", [leader]) }
        if let deputy = clan[clan.deputy], clan.isAlive(deputy.id) { add("DEPUTY", "DEPUTY", [deputy]) }
        add("MEDICINE CAT", "MEDICINE CATS", meds)
        add("MEDIATOR", "MEDIATORS", mediators)
        add("WARRIOR", "WARRIORS", warriors)
        add("APPRENTICES", "APPRENTICES", apprentices, plural: true)

        if !queens.isEmpty || !unattended.isEmpty {
            var entries: [Entry] = []
            for (queenID, kits) in queens {
                guard let queen = clan[queenID] else { continue }
                let names = kits.map { "\(name($0)) - \(describe($0, true))" }
                let caring = names.count == 1
                    ? "(caring for \(names[0]))"
                    : "(caring for \(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1]))"
                entries.append(entry(queen, caringFor: caring))
            }
            entries += unattended.map { entry($0) }
            sections.append(Section(title: "QUEENS AND KITS", entries: entries))
        }
        add("ELDERS", "ELDERS", elders, plural: true)
        self.sections = sections
    }

    /// Clangen's `get_alive_clan_queens`: each kit is listed under one living parent in the Clan,
    /// preferring a she-cat. Returns queens in the order they're found, and kits with no parent in the Clan.
    static func queens(in clan: Clan) -> (queens: [(Cat.ID, [Cat])], unattended: [Cat]) {
        var queens: [(Cat.ID, [Cat])] = []
        var unattended: [Cat] = []
        for kit in clan.living where kit.rank.isBaby {
            let parents = kit.allParents.compactMap { clan[$0] }.filter { clan.isAlive($0.id) }
            guard !parents.isEmpty else {
                unattended.append(kit)
                continue
            }
            let carer = parents.count != 2 || parents.allSatisfy { $0.sex == .male } || parents[0].sex == .female
                ? parents[0] : parents[1]
            if let i = queens.firstIndex(where: { $0.0 == carer.id }) {
                queens[i].1.append(kit)
            } else {
                queens.append((carer.id, [kit]))
            }
        }
        return (queens, unattended)
    }

    /// The roster as Clangen's plain text, for sharing.
    var text: String {
        var lines = ["\(clanName) Allegiances", ""]
        for section in sections {
            lines.append(section.title)
            for entry in section.entries {
                var line = "\(entry.name) - \(entry.description)"
                if let caring = entry.caringFor { line += " \(caring)" }
                lines.append(line)
                if let apprentices = entry.apprenticeLine { lines.append("      \(apprentices)") }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
