import Foundation

/// Clangen's family tree relations. Adoptive parents count as parents, as in Clangen.
struct Kin: Hashable, Sendable {
    enum Kind: String, Sendable {
        case parent, adoptiveParent, grandparent, mate, formerMate, kit, adoptiveKit, grandkit
        case sibling, halfSibling, littermate, adoptiveSibling, siblingsKit, auntOrUncle, cousin
    }

    let id: UUID
    let kind: Kind
}

extension Clan {
    /// Every cat the Clan knows of, living or dead, in the Clan or outside it.
    private var everyone: [Cat] { cats + outsiders }

    /// Blood parents first, then adoptive ones.
    func parents(of id: UUID) -> [UUID] { self[id]?.allParents ?? [] }
    func bloodParents(of id: UUID) -> [UUID] { self[id]?.parents ?? [] }
    func adoptiveParents(of id: UUID) -> [UUID] { self[id]?.adoptiveParents ?? [] }

    /// Blood and adopted kits.
    func children(of id: UUID) -> [UUID] {
        everyone.filter { $0.parents.contains(id) || $0.adoptiveParents.contains(id) }.map(\.id)
    }

    func bloodChildren(of id: UUID) -> [UUID] {
        everyone.filter { $0.parents.contains(id) }.map(\.id)
    }

    func adoptedKits(of id: UUID) -> [UUID] {
        everyone.filter { $0.adoptiveParents.contains(id) && !$0.parents.contains(id) }.map(\.id)
    }

    func grandparents(of id: UUID) -> [UUID] {
        let parents = parents(of: id)
        return unique(parents.flatMap { self.parents(of: $0) }.filter { !parents.contains($0) })
    }

    func grandkits(of id: UUID) -> [UUID] {
        unique(children(of: id).flatMap { children(of: $0) })
    }

    /// Clangen's sibling types: any shared parent makes a sibling. Sharing every blood parent
    /// is a full sibling, sharing only some a half sibling, and sharing none an adoptive
    /// sibling; full siblings born the same moon are littermates.
    func siblings(of id: UUID) -> [Kin] {
        guard let cat = self[id], !cat.allParents.isEmpty else { return [] }
        let mineAll = Set(cat.allParents), mineBlood = Set(cat.parents)
        return everyone.compactMap { other in
            guard other.id != id, !mineAll.contains(other.id), !mineAll.isDisjoint(with: other.allParents) else { return nil }
            let theirsBlood = Set(other.parents)
            if mineBlood.isDisjoint(with: theirsBlood) { return Kin(id: other.id, kind: .adoptiveSibling) }
            if mineBlood != theirsBlood { return Kin(id: other.id, kind: .halfSibling) }
            let born = { (c: Cat) in c.moons + c.deadFor }
            return Kin(id: other.id, kind: born(other) == born(cat) ? .littermate : .sibling)
        }
    }

    func auntsAndUncles(of id: UUID) -> [UUID] {
        let parents = Set(parents(of: id))
        let grandparents = Set(grandparents(of: id))
        return everyone.filter { !parents.contains($0.id) && !grandparents.isDisjoint(with: $0.allParents) }.map(\.id)
    }

    func cousins(of id: UUID) -> [UUID] {
        unique(auntsAndUncles(of: id).flatMap { children(of: $0) })
    }

    func siblingsKits(of id: UUID) -> [UUID] {
        unique(siblings(of: id).flatMap { children(of: $0.id) })
    }

    /// The whole family tree, closest relations first.
    func family(of id: UUID) -> [Kin] {
        guard let cat = self[id] else { return [] }
        var result: [Kin] = []
        func add(_ ids: [UUID], _ kind: Kin.Kind) {
            for other in ids where other != id && !result.contains(where: { $0.id == other }) {
                result.append(Kin(id: other, kind: kind))
            }
        }
        add(cat.parents, .parent)
        add(cat.adoptiveParents, .adoptiveParent)
        add(cat.mates, .mate)
        add(bloodChildren(of: id), .kit)
        add(adoptedKits(of: id), .adoptiveKit)
        for sibling in siblings(of: id) { add([sibling.id], sibling.kind) }
        add(grandparents(of: id), .grandparent)
        add(grandkits(of: id), .grandkit)
        add(auntsAndUncles(of: id), .auntOrUncle)
        add(siblingsKits(of: id), .siblingsKit)
        add(cousins(of: id), .cousin)
        add(cat.previousMates, .formerMate)
        return result
    }

    /// Clangen's `get_relatives` without cousins: parents, kits, siblings, grandparents,
    /// grandkits, aunts, uncles, nieces and nephews.
    func relatives(of id: UUID) -> Set<UUID> {
        var result = Set(parents(of: id) + children(of: id) + grandparents(of: id) + grandkits(of: id))
        result.formUnion(siblings(of: id).map(\.id))
        result.formUnion(auntsAndUncles(of: id) + siblingsKits(of: id))
        result.remove(id)
        return result
    }

    /// Clangen's `get_relatives`, with first cousins when `cousins` is set.
    func relatives(of id: UUID, cousins: Bool) -> Set<UUID> {
        cousins ? relatives(of: id).union(self.cousins(of: id)).subtracting([id]) : relatives(of: id)
    }

    /// Clangen's `biggest_family_is_big`: the family holds more than a tenth of the living Clan.
    func isBig(family: Set<UUID>) -> Bool {
        Double(family.count) > Double(living.count) / 10
    }

    /// Clangen's biggest family: the living cat with the most relatives, and those relatives.
    var biggestFamily: Set<UUID> {
        var best: Set<UUID> = []
        for cat in living {
            let family = relatives(of: cat.id).union([cat.id])
            if family.count > best.count { best = family }
        }
        return best
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}
