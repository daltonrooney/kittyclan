import Foundation

enum RelationshipValue: String, Codable, CaseIterable, Sendable {
    case romance, like, respect, comfort, trust

    var range: ClosedRange<Int> { self == .romance ? 0...100 : -100...100 }

    /// Tier words from most negative to most positive (`rel_type_tiers`).
    var tiers: [String] {
        switch self {
        case .romance: ["uninterested", "fancies", "adores", "loves"]
        case .like: ["loathes", "hates", "dislikes", "knows_of", "likes", "enjoys", "cherishes"]
        case .respect: ["resents", "envies", "begrudges", "acknowledges", "praises", "respects", "admires"]
        case .trust: ["discredits", "distrusts", "doubts", "observes", "listens_to", "trusts", "confides_in"]
        case .comfort: ["runs_from", "fears", "avoids", "considers", "relates_to", "understands", "knows_deeply"]
        }
    }

    /// The tier word for a value, using Clangen's value intervals.
    func tier(for value: Int) -> String {
        let bounds = self == .romance ? [5, 24, 69, 100] : [-70, -25, -6, 5, 24, 69, 100]
        let index = bounds.firstIndex { value <= $0 } ?? bounds.count - 1
        return tiers[index]
    }

    /// The index of the neutral tier in `tiers`.
    var neutralIndex: Int { self == .romance ? 0 : 3 }
}

/// How one cat feels about another (directional), following Clangen's five-value model.
struct Relationship: Codable, Hashable, Sendable {
    private(set) var romance = 0
    private(set) var like = 0
    private(set) var respect = 0
    private(set) var comfort = 0
    private(set) var trust = 0
    /// Values that have left the neutral tier and can never return to it.
    private(set) var noLongerNeutral: Set<RelationshipValue> = []
    var log: [String] = []

    static let maxLogEntries = 20

    subscript(value: RelationshipValue) -> Int {
        switch value {
        case .romance: romance
        case .like: like
        case .respect: respect
        case .comfort: comfort
        case .trust: trust
        }
    }

    /// Sets a value with Clangen's clamping and neutral stickiness.
    mutating func set(_ value: RelationshipValue, _ newValue: Int) {
        var v = min(max(newValue, value.range.lowerBound), value.range.upperBound)
        if value != .romance {
            if (-5...5).contains(v) {
                if noLongerNeutral.contains(value) { v = v < 0 ? -7 : 6 }
            } else {
                noLongerNeutral.insert(value)
            }
        }
        switch value {
        case .romance: romance = v
        case .like: like = v
        case .respect: respect = v
        case .comfort: comfort = v
        case .trust: trust = v
        }
    }

    mutating func add(_ value: RelationshipValue, _ amount: Int) {
        set(value, self[value] + amount)
    }

    /// Sets a starting value without marking it as having left neutral, like Clangen's constructor.
    mutating func initialize(_ value: RelationshipValue, _ newValue: Int) {
        let v = min(max(newValue, value.range.lowerBound), value.range.upperBound)
        switch value {
        case .romance: romance = v
        case .like: like = v
        case .respect: respect = v
        case .comfort: comfort = v
        case .trust: trust = v
        }
    }

    mutating func addLog(_ text: String) {
        guard log.last != text else { return }
        log.append(text)
        if log.count > Self.maxLogEntries { log.removeFirst(log.count - Self.maxLogEntries) }
    }

    var total: Int { RelationshipValue.allCases.reduce(0) { $0 + self[$1] } }
    var totalMagnitude: Int { RelationshipValue.allCases.reduce(0) { $0 + abs(self[$1]) } }
    var tiers: [String] { RelationshipValue.allCases.map { $0.tier(for: self[$0]) } }
    var isNeutral: Bool { RelationshipValue.allCases.allSatisfy { $0.tier(for: self[$0]) == $0.tiers[$0.neutralIndex] } }

    /// Clangen's `relationship_qualifies`: every positive threshold met from above, negative from below.
    func meets(_ thresholds: [RelationshipValue: Int]) -> Bool {
        thresholds.allSatisfy { value, threshold in
            threshold == 0 || (threshold > 0 ? self[value] >= threshold : self[value] <= threshold)
        }
    }

    /// Whether this relationship passes a tier filter such as "likes", "loves_only" or "doubts".
    /// Positive tiers accept stronger feelings, negative tiers accept worse ones, neutral tiers are exact.
    func satisfies(tier token: String) -> Bool {
        let exact = token.hasSuffix("_only")
        let word = exact ? String(token.dropLast(5)) : token
        guard let value = RelationshipValue.allCases.first(where: { $0.tiers.contains(word) }),
              let wanted = value.tiers.firstIndex(of: word),
              let actual = value.tiers.firstIndex(of: value.tier(for: self[value]))
        else { return false }
        if exact || wanted == value.neutralIndex { return actual == wanted }
        return wanted > value.neutralIndex ? actual >= wanted : actual <= wanted
    }

    static func isTierToken(_ token: String) -> Bool {
        let word = token.hasSuffix("_only") ? String(token.dropLast(5)) : token
        return RelationshipValue.allCases.contains { $0.tiers.contains(word) }
    }
}
