import Foundation

/// Clangen's `Afterlife` class: StarClan's or the Dark Forest's personality, the average facets
/// of the cats who shape it, 8 each while there are none.
struct AfterlifeTemper: Hashable, Sendable {
    var lawfulness = 8
    var sociability = 8
    var aggression = 8
    var stability = 8

    init(influencers: [Personality]) {
        guard !influencers.isEmpty else { return }
        func average(_ path: KeyPath<Personality, Int>) -> Int {
            influencers.map { $0[keyPath: path] }.reduce(0, +) / influencers.count
        }
        lawfulness = average(\.lawfulness)
        sociability = average(\.sociability)
        aggression = average(\.aggression)
        stability = average(\.stability)
    }

    /// Clangen's `get_compatibility`: how closely a cat's facets match the afterlife's.
    func compatibility(with cat: Cat) -> RelationshipEngine.Compatibility {
        let p = cat.personality
        let score = [
            (lawfulness, p.lawfulness), (sociability, p.sociability),
            (aggression, p.aggression), (stability, p.stability),
        ].reduce(0) { total, pair in
            let diff = abs(pair.0 - pair.1)
            return total + (diff <= 4 ? 1 : diff >= 6 ? -1 : 0)
        }
        return score >= 2 ? .positive : score <= -2 ? .negative : .neutral
    }

    /// Clangen's `get_temper_alignment`: one word from each temperament table, e.g. ["stoic", "observant"].
    var words: [String] {
        func bucket(_ value: Int) -> Int { value >= 11 ? 2 : value >= 7 ? 1 : 0 }
        return [
            MoonEngine.temperaments[0][bucket(sociability)][bucket(aggression)],
            MoonEngine.temperaments[1][bucket(lawfulness)][bucket(stability)],
        ]
    }

    /// Clangen's `change_affinity` modifier: a compatible afterlife feels a change half again
    /// as strongly, an incompatible one half as much.
    func scaled(_ change: Int, for cat: Cat) -> Int {
        let half = Int((Double(change) * 0.5).rounded(.toNearestOrEven))
        return switch compatibility(with: cat) {
        case .positive: change + half
        case .negative: change - half
        case .neutral: change
        }
    }
}

extension Clan {
    /// The cats who shape an afterlife's temperament: its guide and the leaders, deputies and
    /// medicine cats resting there. The Unknown Residence has none.
    func influencers(of afterlife: Afterlife) -> [Cat] {
        guard afterlife != .unknownResidence else { return [] }
        return afterlifeCats.filter { cat in
            cat.afterlife == afterlife && (cat.id == guide || [.leader, .deputy, .medicineCat].contains(cat.rank))
        }
    }

    func temper(of afterlife: Afterlife) -> AfterlifeTemper {
        AfterlifeTemper(influencers: influencers(of: afterlife).map(\.personality))
    }

    /// Clangen's `change_affinity`: each change is scaled by how well the cat suits that afterlife.
    mutating func changeAffinity(of id: UUID, starClan: Int = 0, darkForest: Int = 0) {
        guard let i = index(of: id) else { return }
        let cat = cats[i]
        if starClan != 0 { cats[i].starClanAffinity += temper(of: .starClan).scaled(starClan, for: cat) }
        if darkForest != 0 { cats[i].darkForestAffinity += temper(of: .darkForest).scaled(darkForest, for: cat) }
    }
}
