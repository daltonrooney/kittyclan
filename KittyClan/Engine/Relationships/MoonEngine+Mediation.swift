import Foundation

/// Why a mediator can't mediate a pair right now.
enum MediationBlock: Equatable, Sendable {
    case notMediator
    case cantWork
    case alreadyWorked
    case invalidPair
    case pairAlreadyMediated
}

/// Clangen's MediationScreen and `Cat.mediate_relationship`. Nothing is written to the moon log.
extension MoonEngine {
    static func mediationBlock(_ mediator: UUID, _ a: UUID?, _ b: UUID?, in clan: Clan) -> MediationBlock? {
        guard let cat = clan[mediator], clan.isAlive(mediator), cat.rank.isMediator else { return .notMediator }
        if cat.isNotWorking { return .cantWork }
        if clan.mediatedThisMoon.contains(mediator) { return .alreadyWorked }
        guard let a, let b, a != b, a != mediator, b != mediator, clan.isAlive(a), clan.isAlive(b) else { return .invalidPair }
        if clan.mediatedPairs.contains(CatPair(a, b)) { return .pairAlreadyMediated }
        return nil
    }

    /// Whether romance can be mediated: both 12+ moons or the same age, and not related.
    static func canMediateRomance(_ a: Cat, _ b: Cat, in clan: Clan) -> Bool {
        (a.moons >= 12 && b.moons >= 12 || a.age == b.age) && !clan.areRelated(a.id, b.id)
    }

    /// Mediates between two cats. Returns the result lines, or nil when `mediationBlock` forbids it.
    @discardableResult
    func mediate(
        _ mediatorID: UUID, _ a: UUID, _ b: UUID, sabotage: Bool, allowRomance: Bool = false,
        in clan: inout Clan, using rng: inout some RandomNumberGenerator
    ) -> [String]? {
        guard Self.mediationBlock(mediatorID, a, b, in: clan) == nil,
              let mediator = clan[mediatorID], let catA = clan[a], let catB = clan[b], let m = clan.index(of: mediatorID)
        else { return nil }
        clan.mediatedThisMoon.insert(mediatorID)
        clan.mediatedPairs.insert(CatPair(a, b))

        let level = PatrolSlot.experienceLevel(mediator.experience)
        let levelChance = ["untrained": 15, "learning": 20, "prepared": 35, "proficient": 55, "adept": 70, "masterful": 100]
        var chance = levelChance[level] ?? 40
        func adjust(_ compatibility: RelationshipEngine.Compatibility, _ good: Int, _ bad: Int) {
            switch compatibility {
            case .positive: chance += good
            case .negative: chance -= bad
            case .neutral: break
            }
        }
        adjust(RelationshipEngine.compatibility(catA, catB), 10, 5)
        adjust(RelationshipEngine.compatibility(catA, mediator), 5, 5)
        adjust(RelationshipEngine.compatibility(catB, mediator), 5, 5)

        var sabotage = sabotage
        var lines: [String] = []
        let failed = chance <= 0 || Int.random(in: 0..<chance, using: &rng) == 0
        if failed {
            lines.append(sabotage ? "Sabotage Failed!" : "Mediate Failed!")
            sabotage.toggle()
        }

        var gain = 0.0
        if mediator.rank == .mediatorApprentice {
            gain = Double(Int.random(in: 1...6, using: &rng))
        } else if !failed {
            let levelModifier: Double = ["proficient": 1.25, "adept": 1.75, "masterful": 2.0][level] ?? 1
            gain = Double(Int.random(in: 10...24, using: &rng)) / levelModifier / (clan.preyAndHerbs ? 3 : 1)
        }
        let whole = Int(gain)
        let extra = Double.random(in: 0..<1, using: &rng) < gain - Double(whole) ? 1 : 0
        clan.cats[m].experience = min(321, mediator.experience + whole + extra)

        let mates = catB.mates.contains(a)
        var values: [RelationshipValue] = [.like, .respect, .trust, .comfort]
        if allowRomance, mates || clan.isPotentialMate(catA, catB) { values.append(.romance) }
        let chosen = values.shuffled(using: &rng).prefix(Int.random(in: 2...values.count, using: &rng))
        for value in chosen {
            let bonus = !failed && level == "masterful" ? Int.random(in: 3...4, using: &rng) : 0
            let base = value == .romance && mates ? Int.random(in: 5...10, using: &rng) : Int.random(in: 4...6, using: &rng)
            let amount = (base + bonus) * (sabotage ? -1 : 1)
            clan.updateRelationship(from: a, to: b) { $0.add(value, amount) }
            clan.updateRelationship(from: b, to: a) { $0.add(value, amount) }
            lines.append("\(value.rawValue.capitalized) \(sabotage ? "decreased" : "increased").")
        }
        return lines
    }
}
