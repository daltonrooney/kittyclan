import Foundation

/// Clangen's `snippet_collections.json`: the omens, prophecies, dreams, clairvoyant senses and
/// stories that `omen_list`, `prophecy_list`, `dream_list`, `clair_list` and `story_list` stand for.
struct SnippetCollections: Sendable {
    /// Each group is a set of alternatives; one is picked from each chosen group.
    typealias Groups = [[String]]

    static let listTypes = ["omen_list", "prophecy_list", "dream_list", "clair_list", "story_list"]
    private static let senses = ["sight", "sound", "smell", "emotional", "touch", "taste"]

    /// List → sense (or "" for lists without senses) → "general" or a biome key → groups.
    private let lists: [String: [String: [String: Groups]]]

    init(url: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        func groups(_ value: Any?) -> Groups? { value as? [[String]] }
        var lists: [String: [String: [String: Groups]]] = [:]
        for type in Self.listTypes {
            if let flat = groups(json[type]) {
                lists[type] = ["": ["general": flat]]
            } else if let nested = json[type] as? [String: Any] {
                if Self.senses.contains(where: { nested[$0] != nil }) {
                    lists[type] = nested.compactMapValues { ($0 as? [String: Any])?.compactMapValues(groups) }
                } else {
                    lists[type] = ["": nested.compactMapValues(groups)]
                }
            }
        }
        self.lists = lists
    }

    /// A special list token in the text, e.g. `omen_list_sight_sound/m_c`.
    struct Token: Equatable {
        /// The token as written, without surrounding punctuation.
        let text: String
        let type: String
        let senses: [String]
        /// The cat whose pronouns the snippets use (`cat_tag`), if given.
        let cat: String?
    }

    /// Clangen's `find_special_list_types`: the first word naming a special list.
    static func token(in text: String) -> Token? {
        for word in text.split(separator: " ") where word.contains("_list") {
            let cleaned = word.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
            guard let type = listTypes.first(where: cleaned.contains) else { return nil }
            let parts = cleaned.split(separator: "/", maxSplits: 1).map(String.init)
            return Token(
                text: cleaned,
                type: type,
                senses: senses.filter { cleaned.contains("_" + $0) },
                cat: parts.count > 1 ? parts[1] : nil
            )
        }
        return nil
    }

    /// Clangen's `get_special_snippet_list`: one line from each of 1–3 groups, joined as a list.
    /// Without senses every sense is used (clair lists have taste instead of sight). Snippets that
    /// refer to `cat_tag` are skipped when the token names no cat.
    func snippets(for token: Token, biome: Biome, using rng: inout some RandomNumberGenerator) -> String {
        let list = lists[token.type] ?? [:]
        var senses = token.senses
        if list[""] != nil {
            senses = [""]
        } else if senses.isEmpty {
            senses = token.type == "clair_list"
                ? ["taste", "sound", "smell", "emotional", "touch"]
                : ["sight", "sound", "smell", "emotional", "touch"]
        }
        var groups: Groups = []
        for sense in senses {
            groups += list[sense]?["general"] ?? []
            groups += list[sense]?[biome.key] ?? []
        }
        if token.cat == nil {
            groups = groups.map { $0.filter { !$0.contains("cat_tag") } }
        }
        let picks = groups.filter { !$0.isEmpty }.map { $0.randomElement(using: &rng)! }.shuffled(using: &rng)
        let chosen = Array(picks.prefix(Int.random(in: 1...3, using: &rng)))
        return TextTemplate.joined(chosen)
    }

    /// Replaces the text's special list (Clangen handles one per text) with snippets, and `cat_tag`
    /// with the cat the list names.
    func expand(_ text: String, biome: Biome, using rng: inout some RandomNumberGenerator) -> String {
        guard let token = Self.token(in: text) else { return text }
        var output = text.replacingOccurrences(of: token.text, with: snippets(for: token, biome: biome, using: &rng))
        if let cat = token.cat { output = output.replacingOccurrences(of: "cat_tag", with: cat) }
        return output
    }
}
