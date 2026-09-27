import Foundation

/// Clangen's personality: four facets from 0 to 16 and a trait whose ranges contain them.
/// Kits have kit traits and switch to adult traits when they become apprentices.
struct Personality: Codable, Hashable, Sendable {
    var lawfulness: Int
    var sociability: Int
    var aggression: Int
    var stability: Int
    var trait: String
    var isKit: Bool

    static let facetRange = 0...16
}

/// The trait table from Clangen's `trait_ranges.json`.
struct TraitTable: Sendable {
    struct Ranges: Decodable, Sendable {
        let lawfulness: [Int]
        let sociability: [Int]
        let aggression: [Int]
        let stability: [Int]

        func contains(_ p: Personality) -> Bool {
            func inRange(_ r: [Int], _ v: Int) -> Bool { r.count == 2 && r[0] <= v && v <= r[1] }
            return inRange(lawfulness, p.lawfulness) && inRange(sociability, p.sociability)
                && inRange(aggression, p.aggression) && inRange(stability, p.stability)
        }
    }

    private struct File: Decodable {
        let normal_traits: [String: Ranges]
        let kit_traits: [String: Ranges]
    }

    let normal: [String: Ranges]
    let kit: [String: Ranges]

    init(url: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        normal = file.normal_traits
        kit = file.kit_traits
    }

    /// A random trait, with facets rolled inside its ranges.
    func random(kit isKit: Bool, using rng: inout some RandomNumberGenerator) -> Personality {
        let table = isKit ? kit : normal
        let trait = pick(table.keys.sorted(), &rng)
        let r = table[trait]!
        func roll(_ range: [Int]) -> Int { Int.random(in: range[0]...range[1], using: &rng) }
        return Personality(
            lawfulness: roll(r.lawfulness), sociability: roll(r.sociability),
            aggression: roll(r.aggression), stability: roll(r.stability),
            trait: trait, isKit: isKit
        )
    }

    /// Clangen's `set_kit`: re-chooses the trait from the other table if it no longer fits.
    func setKit(_ isKit: Bool, _ personality: inout Personality, using rng: inout some RandomNumberGenerator) {
        personality.isKit = isKit
        chooseTraitIfInvalid(&personality, using: &rng)
    }

    /// Clangen's `facet_wobble`, applied when a cat moves to a new age group.
    func wobble(_ personality: inout Personality, by amount: Int, using rng: inout some RandomNumberGenerator) {
        func nudge(_ v: Int) -> Int {
            min(max(v + Int.random(in: -amount...amount, using: &rng), Personality.facetRange.lowerBound), Personality.facetRange.upperBound)
        }
        personality.lawfulness = nudge(personality.lawfulness)
        personality.stability = nudge(personality.stability)
        personality.aggression = nudge(personality.aggression)
        personality.sociability = nudge(personality.sociability)
        chooseTraitIfInvalid(&personality, using: &rng)
    }

    private func chooseTraitIfInvalid(_ p: inout Personality, using rng: inout some RandomNumberGenerator) {
        let table = p.isKit ? kit : normal
        if let ranges = table[p.trait], ranges.contains(p) { return }
        let fitting = table.filter { $0.value.contains(p) }.map(\.key).sorted()
        p.trait = fitting.randomElement(using: &rng) ?? "strange"
    }
}
