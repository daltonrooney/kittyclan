import Foundation

/// Clangen's pronoun sets from `pronouns.en.json`.
struct PronounTable: Sendable {
    struct Set: Decodable, Sendable {
        let subject: String
        let object: String
        let poss: String
        let inposs: String
        let reflexive: String
        let conju: Int
        let gender: Int

        private enum CodingKeys: String, CodingKey {
            case subject, object, poss, inposs, conju, gender
            case reflexive = "self"
        }

        subscript(field: String) -> String? {
            switch field {
            case "subject": subject
            case "object": object
            case "poss": poss
            case "inposs": inposs
            case "self": reflexive
            default: nil
            }
        }
    }

    let sets: [String: Set]

    init(url: URL) throws {
        sets = try JSONDecoder().decode([String: Set].self, from: Data(contentsOf: url))
    }

    subscript(pronouns: Pronouns) -> Set? { sets[pronouns.rawValue] }
}

/// Fills in Clangen event text (`text_adjust.event_text_adjust`): pronoun, verb and adjective
/// tags, then cat abbreviations such as `m_c` and `r_c0`, then the Clan name.
struct TextTemplate: Sendable {
    let pronouns: PronounTable
    let names: NameGenerator

    /// - Parameters:
    ///   - cats: abbreviation → cat, e.g. `["m_c": leader, "r_c": mentor]`.
    ///   - extras: other literal replacements, e.g. `["r_h": "bravery", "(old_name)": "Firepaw"]`.
    func resolve(_ text: String, cats: [String: Cat], clan: Clan, otherClan: String? = nil, extras: [String: String] = [:]) -> String {
        var cats = cats
        for (abbr, id) in [("lead_name", clan.leader), ("dep_name", clan.deputy)] {
            if let cat = clan[id], cat.isAlive { cats[abbr] = cat }
        }
        if let healer = clan.living.first(where: { $0.rank == .medicineCat }) {
            cats["med_name"] = healer
        }
        var replacements = extras
        for (abbr, cat) in cats { replacements[abbr] = names.display(cat.name, rank: cat.rank) }

        var output = resolveTags(text, cats: cats)
        if let otherClan { output = replaceClanName(output, otherClan, token: "o_c_n") }
        output = replaceAbbreviations(output, replacements)
        return replaceClanName(output, clan.displayName, token: "c_n")
    }

    /// Clangen's `adjust_list_text`: "A", "A and B", or "A, B, and C".
    func list(_ cats: [Cat]) -> String {
        Self.joined(cats.map { names.display($0.name, rank: $0.rank) })
    }

    static func joined(_ labels: [String]) -> String {
        switch labels.count {
        case 0: ""
        case 1: labels[0]
        case 2: "\(labels[0]) and \(labels[1])"
        default: labels.dropLast().joined(separator: ", ") + ", and " + labels.last!
        }
    }

    /// Resolves `{PRONOUN/abbr/field}`, `{VERB/abbr/plural/singular}` and `{ADJ/abbr/they/he/she}`,
    /// with an optional trailing `/CAP`. Tags for cats not in this event are left for later.
    private func resolveTags(_ text: String, cats: [String: Cat]) -> String {
        var output = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            let percent = open > rest.startIndex && rest[rest.index(before: open)] == "%"
            output += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                output += rest[open...]
                return output
            }
            let tag = rest[rest.index(after: open)..<close]
            output += percent ? String(rest[open...close]) : (resolveTag(String(tag), cats: cats) ?? String(rest[open...close]))
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }

    private func resolveTag(_ tag: String, cats: [String: Cat]) -> String? {
        var parts = tag.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let cat = cats[parts[1]], let set = pronouns[cat.pronouns] else { return nil }
        let capitalize = parts.last == "CAP"
        if capitalize { parts.removeLast() }

        let word: String? = switch parts[0].uppercased() {
        case "PRONOUN": set[parts[2]]
        case "VERB": parts.indices.contains(set.conju + 1) ? parts[set.conju + 1] : nil
        case "ADJ": parts.indices.contains(set.gender + 2) ? parts[set.gender + 2] : nil
        default: nil
        }
        guard let word else { return nil }
        return capitalize ? word.prefix(1).uppercased() + word.dropFirst() : word
    }

    /// Plain substring replacement like Clangen, but longest key first so `r_c` never eats `r_c0`.
    /// Anything still inside braces is left alone.
    private func replaceAbbreviations(_ text: String, _ replacements: [String: String]) -> String {
        let keys = replacements.keys.sorted { $0.count > $1.count }
        var output = ""
        var i = text.startIndex
        var depth = 0
        scan: while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" { depth = max(0, depth - 1) }
            if depth == 0 {
                for key in keys where text[i...].hasPrefix(key) {
                    output += replacements[key]!
                    i = text.index(i, offsetBy: key.count)
                    continue scan
                }
            }
            output.append(c)
            i = text.index(after: i)
        }
        return output
    }

    /// Replaces `c_n` (or `o_c_n`) with a Clan name, turning a preceding "a" into "an" before a vowel.
    private func replaceClanName(_ text: String, _ clanName: String, token: String) -> String {
        let startsWithVowel = clanName.first.map { "AEIOU".contains($0.uppercased()) } ?? false
        var parts = text.components(separatedBy: token)
        guard parts.count > 1 else { return text }
        for i in 0..<(parts.count - 1) where startsWithVowel {
            if parts[i].hasSuffix(" a ") { parts[i] = String(parts[i].dropLast(2)) + "an " }
            else if parts[i].hasSuffix(" A ") || parts[i] == "A " { parts[i] = String(parts[i].dropLast(2)) + "An " }
        }
        return parts.joined(separator: clanName)
    }
}
