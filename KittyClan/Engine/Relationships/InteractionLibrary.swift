import Foundation

/// A `relationships` / `relationship_changes` block from Clangen event data.
struct RelationshipChange: Sendable {
    let from: [String]
    let to: [String]
    let mutual: Bool
    let values: [RelationshipValue]
    let amount: Int
    let logFrom: String?
    let logTo: String?

    init?(_ json: [String: Any]) {
        guard let from = json["cats_from"] as? [String], let to = json["cats_to"] as? [String],
              let amount = json["amount"] as? Int
        else { return nil }
        self.from = from
        self.to = to
        self.amount = amount
        mutual = json["mutual"] as? Bool ?? false
        values = (json["values"] as? [String] ?? []).compactMap(RelationshipValue.init)
        let log = json["log"] as? [String: Any]
        logFrom = log?["cats_from"] as? String
        logTo = log?["cats_to"] as? String
    }
}

/// One of Clangen's relationship interactions (normal, group or joining).
struct Interaction: Sendable {
    let strings: [String]
    let main: Constraint?
    let random: Constraint?
    let group: Constraint?
    let rules: [RelationshipRule]
    let changes: [RelationshipChange]
    let weight: Int

    init?(_ json: [String: Any]) {
        let involved = json["involved_cats"] as? [String: [String: Any]] ?? [:]
        guard Set(involved.keys).isSubset(of: ["m_c", "r_c", "multi_cat"]),
              Set(json.keys).isSubset(of: ["event_id", "strings", "involved_cats", "relationship_constraint", "relationship_changes"])
        else { return nil }

        func constraint(_ abbr: String) -> Constraint?? {
            guard let spec = involved[abbr] else { return .some(nil) }
            return Constraint(spec).map { .some($0) }
        }
        guard let main = constraint("m_c"), let random = constraint("r_c"), let group = constraint("multi_cat") else { return nil }

        let ruleJSON = json["relationship_constraint"] as? [[String: Any]] ?? []
        let rules = ruleJSON.compactMap(RelationshipRule.init)
        let changeJSON = json["relationship_changes"] as? [[String: Any]] ?? []
        let changes = changeJSON.compactMap(RelationshipChange.init)
        guard rules.count == ruleJSON.count, changes.count == changeJSON.count else { return nil }

        let allowed: Set<String> = ["m_c", "r_c", "multi_cat"]
        strings = (json["strings"] as? [String] ?? []).filter { text in
            Constraint.textIsSupported(text, allowing: allowed)
                && !text.contains("/multi_cat/")
        }
        guard !strings.isEmpty else { return nil }
        self.main = main
        self.random = random
        self.group = group
        self.rules = rules
        self.changes = changes
        weight = 1 + (rules.isEmpty ? 0 : 20) + involved.values.reduce(0) { $0 + $1.count }
    }
}

enum Intensity: String, CaseIterable, Sendable {
    case low, medium, high

    var amount: Int {
        switch self {
        case .low: 8
        case .medium: 12
        case .high: 16
        }
    }
}

/// Clangen's relationship event text, from `events/relationship_events`.
struct InteractionLibrary: Sendable {
    /// `normal[kind][intensity][positive]`, `joining` likewise, `group[intensity][positive]`.
    private let normal: [String: [Interaction]]
    private let joining: [String: [Interaction]]
    private let group: [String: [Interaction]]
    let becomeMates: [String: [String]]
    let breakups: [String: [String]]

    init(directory: URL) throws {
        func events(_ path: String) -> [Interaction] {
            guard let data = try? Data(contentsOf: directory.appending(path: path)),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return list.compactMap(Interaction.init)
        }
        var normal: [String: [Interaction]] = [:]
        var joining: [String: [Interaction]] = [:]
        var group: [String: [Interaction]] = [:]
        for intensity in Intensity.allCases {
            for direction in ["positive", "negative"] {
                for kind in RelationshipValue.allCases {
                    let key = Self.key(kind, intensity, direction == "positive")
                    normal[key] = events("relationship_events/normal_interactions/\(kind.rawValue)/\(intensity.rawValue)/\(direction).json")
                    joining[key] = events("relationship_events/joining_interactions/\(kind.rawValue)/\(intensity.rawValue)/\(direction).json")
                }
                group[Self.key(nil, intensity, direction == "positive")] =
                    events("relationship_events/group_interactions/\(intensity.rawValue)/\(direction).json")
            }
        }
        self.normal = normal
        self.joining = joining
        self.group = group

        func strings(_ path: String) throws -> [String: [String]] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: path))) as? [String: [String]] ?? [:]
        }
        becomeMates = try strings("relationship_events/become_mates.json")
        breakups = try strings("relationship_events/breakup_mates.json")
    }

    private static func key(_ kind: RelationshipValue?, _ intensity: Intensity, _ positive: Bool) -> String {
        "\(kind?.rawValue ?? "group")/\(intensity.rawValue)/\(positive)"
    }

    func pair(_ kind: RelationshipValue, _ intensity: Intensity, positive: Bool, joining isJoining: Bool) -> [Interaction] {
        (isJoining ? joining : normal)[Self.key(kind, intensity, positive)] ?? []
    }

    func group(_ intensity: Intensity, positive: Bool) -> [Interaction] {
        group[Self.key(nil, intensity, positive)] ?? []
    }

    var counts: (normal: Int, group: Int, joining: Int) {
        (normal.values.reduce(0) { $0 + $1.count }, group.values.reduce(0) { $0 + $1.count }, joining.values.reduce(0) { $0 + $1.count })
    }
}
