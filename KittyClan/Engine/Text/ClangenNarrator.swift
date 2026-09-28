import Foundation

/// Narrates moon events with Clangen's own ceremony, pregnancy and event text.
struct ClangenNarrator: Narrator {
    let library: EventLibrary
    let template: TextTemplate
    let fallback: BasicNarrator

    func text(for event: MoonEvent, in clan: Clan, using rng: inout some RandomNumberGenerator) -> String {
        switch event {
        case .story(let pick, _):
            return resolve(pick, in: clan)
        case .apprenticed(let id, _, let oldName), .graduated(let id, let oldName), .becameLeader(let id, let oldName):
            return ceremony(for: id, oldName: oldName, in: clan, using: &rng) ?? fallback.text(for: event, in: clan, using: &rng)
        case .retired(let id), .deputyAppointed(let id):
            let oldName = clan[id].map { template.names.display($0.name, rank: $0.rank) } ?? ""
            return ceremony(for: id, oldName: oldName, in: clan, using: &rng) ?? fallback.text(for: event, in: clan, using: &rng)
        case .expecting(let mother):
            guard let cat = clan[mother], let line = library.announcements.randomElement(using: &rng) else { break }
            var cats = ["m_c": cat]
            if let mate = cat.mates.compactMap({ clan[$0] }).first { cats["r_c"] = mate }
            else if line.contains("r_c") { break }
            return template.resolve(line, cats: cats, clan: clan)
        case .born(let mother, let father, let kits):
            guard let cat = clan[mother], let mate = clan[father],
                  let line = library.twoParentBirths.randomElement(using: &rng)
            else { break }
            let amount = kits.count == 1
                ? library.kitAmount["one"] ?? "single kitten"
                : (library.kitAmount["many"] ?? "litter of %{count} kits").replacing("%{count}", with: "\(kits.count)")
            return template.resolve(line.replacing("{insert}", with: amount), cats: ["m_c": cat, "r_c": mate], clan: clan)
        default:
            break
        }
        return fallback.text(for: event, in: clan, using: &rng)
    }

    private func ceremony(for id: UUID, oldName: String, in clan: Clan, using rng: inout some RandomNumberGenerator) -> String? {
        guard let cat = clan[id], let pick = library.ceremony(for: cat, in: clan, using: &rng) else { return nil }
        let extras = ["r_h": library.honor(for: cat, using: &rng), "(old_name)": oldName]
        return resolve(pick, in: clan, extras: extras)
    }

    private func resolve(_ pick: StoryPick, in clan: Clan, extras: [String: String] = [:]) -> String {
        let cats = pick.cats.compactMapValues { clan[$0] }
        var extras = extras
        for (abbr, ids) in pick.groupCats {
            let cats = ids.compactMap { clan[$0] }
            extras[abbr] = template.list(cats)
            if abbr.hasPrefix("n_c:"), let first = cats.first {
                extras["n_c_pre:" + abbr.dropFirst(4)] = first.name.prefix
            }
        }
        return template.resolve(pick.template, cats: cats, clan: clan, otherClan: clan.otherClan(pick.otherClan)?.name, extras: extras)
    }
}
