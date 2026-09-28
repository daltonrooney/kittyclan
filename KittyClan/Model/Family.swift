import Foundation

/// Clangen's family tree relations, computed from blood parents.
struct Kin: Hashable, Sendable {
    enum Kind: String, Sendable {
        case parent, grandparent, mate, formerMate, kit, grandkit
        case sibling, halfSibling, littermate, siblingsKit, auntOrUncle, cousin
    }

    let id: UUID
    let kind: Kind
}

extension Clan {
    /// Every cat the Clan knows of, living or dead, in the Clan or outside it.
    private var everyone: [Cat] { cats + outsiders }

    func parents(of id: UUID) -> [UUID] { self[id]?.parents ?? [] }

    func children(of id: UUID) -> [UUID] {
        everyone.filter { $0.parents.contains(id) }.map(\.id)
    }

    func grandparents(of id: UUID) -> [UUID] {
        let parents = parents(of: id)
        return unique(parents.flatMap { self.parents(of: $0) }.filter { !parents.contains($0) })
    }

    func grandkits(of id: UUID) -> [UUID] {
        unique(children(of: id).flatMap { children(of: $0) })
    }

    /// Clangen's sibling types: sharing every parent is a full sibling, sharing only some a
    /// half sibling; full siblings born the same moon are littermates.
    func siblings(of id: UUID) -> [Kin] {
        guard let cat = self[id], !cat.parents.isEmpty else { return [] }
        let mine = Set(cat.parents)
        return everyone.compactMap { other in
            let theirs = Set(other.parents)
            guard other.id != id, !mine.isDisjoint(with: theirs), !mine.contains(other.id) else { return nil }
            if mine != theirs { return Kin(id: other.id, kind: .halfSibling) }
            let born = { (c: Cat) in c.moons + c.deadFor }
            return Kin(id: other.id, kind: born(other) == born(cat) ? .littermate : .sibling)
        }
    }

    func auntsAndUncles(of id: UUID) -> [UUID] {
        let parents = Set(parents(of: id))
        let grandparents = Set(grandparents(of: id))
        return everyone.filter { !parents.contains($0.id) && !grandparents.isDisjoint(with: $0.parents) }.map(\.id)
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
        add(cat.mates, .mate)
        add(children(of: id), .kit)
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
