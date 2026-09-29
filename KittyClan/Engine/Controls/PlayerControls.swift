import Foundation

/// The choices Clangen leaves to the player: roles, mentors, mates, adoptive parents, names
/// and gender. None of them
/// are written to the moon log, as in Clangen.
extension Rank {
    /// Clangen's RoleScreen buttons for a cat of this rank, without mediators.
    func manualTargets(leaderVacant: Bool, deputyVacant: Bool) -> [Rank] {
        var targets: [Rank]
        switch self {
        case .apprentice: targets = [.medicineApprentice]
        case .medicineApprentice: targets = [.apprentice]
        case .warrior: targets = [.leader, .deputy, .medicineCat, .elder]
        case .deputy: targets = [.leader, .warrior, .elder]
        case .medicineCat: targets = [.warrior, .elder]
        case .elder: targets = [.leader, .deputy, .warrior, .medicineCat]
        case .leader: targets = [.warrior, .elder]
        case .newborn, .kitten: targets = []
        }
        if !leaderVacant { targets.removeAll { $0 == .leader } }
        if !deputyVacant { targets.removeAll { $0 == .deputy } }
        return targets
    }
}

extension Clan {
    /// No leader, or the leader is dead or gone.
    var leaderVacant: Bool { !isAlive(leader) }
    var deputyVacant: Bool { !isAlive(deputy) }

    /// Clangen's ChooseMateScreen rules: like `isPotentialMate` but without the age gap,
    /// among cats of the same group who aren't already mates.
    func canChooseMate(_ a: Cat, _ b: Cat) -> Bool {
        guard a.id != b.id, !a.mates.contains(b.id), a.isDead == b.isDead,
              isOutsider(a.id) == isOutsider(b.id), a.afterlife == b.afterlife,
              !areRelated(a.id, b.id), a.moons >= 12, b.moons >= 12
        else { return false }
        return a.mentor != b.id && b.mentor != a.id
    }

    /// Possible mates in roster order. `singleOnly` hides cats who already have a mate;
    /// `kitsOnly` hides cats who couldn't have kits with this one.
    func mateCandidates(for id: UUID, singleOnly: Bool = false, kitsOnly: Bool = false) -> [Cat] {
        guard let cat = self[id] else { return [] }
        let pool = isOutsider(id) ? outsiders : cats
        return pool.filter { other in
            canChooseMate(cat, other) && (!singleOnly || other.mates.isEmpty) && (!kitsOnly || other.sex != cat.sex)
        }
    }

    func isOutsider(_ id: UUID) -> Bool {
        outsiders.contains { $0.id == id }
    }

    /// Clangen's rename window: letters, digits, spaces and underscores only; an empty prefix
    /// keeps the old one; the suffix only changes when no rank ending hides it.
    /// Returns whether the shown name changed.
    @discardableResult
    mutating func rename(_ id: UUID, prefix: String, suffix: String, hideSpecialSuffix: Bool, names: NameGenerator) -> Bool {
        func clean(_ text: String) -> String {
            String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "_" })
        }
        func apply(_ cat: inout Cat) -> Bool {
            let before = names.display(cat.name, rank: cat.rank)
            cat.name.specialSuffixHidden = hideSpecialSuffix
            let prefix = clean(prefix)
            if !prefix.isEmpty { cat.name.prefix = prefix }
            if hideSpecialSuffix || names.specialSuffix(for: cat.rank) == nil { cat.name.suffix = clean(suffix) }
            return names.display(cat.name, rank: cat.rank) != before
        }
        if let i = index(of: id) { return apply(&cats[i]) }
        if let i = outsiders.firstIndex(where: { $0.id == id }) { return apply(&outsiders[i]) }
        return false
    }
}

extension Clan {
    /// Clangen's `get_valid_adoptive_parents` for a living Clan cat: living Clan cats at least
    /// 14 moons older who aren't already its parent, its mate or a relative of its mates.
    func adoptiveParentCandidates(for id: UUID, matesOfParentsOnly: Bool = false, unrelatedOnly: Bool = false) -> [Cat] {
        guard let cat = self[id], cat.isAlive, !isOutsider(id) else { return [] }
        let mateKin = cat.mates.reduce(into: Set<UUID>()) { $0.formUnion(relatives(of: $1)) }
        let parentMates = Set(cat.allParents.compactMap { self[$0] }.flatMap(\.mates))
        let related = unrelatedOnly ? relatives(of: id) : []
        return living.filter { other in
            other.id != id
                && other.moons - cat.moons >= 14
                && !cat.mates.contains(other.id)
                && !cat.allParents.contains(other.id)
                && !mateKin.contains(other.id)
                && (!matesOfParentsOnly || parentMates.contains(other.id))
                && !related.contains(other.id)
        }
    }

    /// Clangen's `set_adoptive_parent`: both grow closer. Returns false if the cat can't adopt this kit.
    @discardableResult
    mutating func adopt(_ kitID: UUID, by parentID: UUID) -> Bool {
        guard adoptiveParentCandidates(for: kitID).contains(where: { $0.id == parentID }),
              let i = index(of: kitID) else { return false }
        cats[i].adoptiveParents.append(parentID)
        for (a, b) in [(kitID, parentID), (parentID, kitID)] where isAlive(a) {
            updateRelationship(from: a, to: b) {
                $0.add(.like, 20)
                $0.add(.comfort, 20)
                $0.add(.trust, 10)
            }
        }
        return true
    }

    /// Clangen's `unset_adoptive_parent`: both think less of each other. Blood parents can't be removed.
    @discardableResult
    mutating func unadopt(_ kitID: UUID, from parentID: UUID, using rng: inout some RandomNumberGenerator) -> Bool {
        guard let i = index(of: kitID), cats[i].adoptiveParents.contains(parentID) else { return false }
        cats[i].adoptiveParents.removeAll { $0 == parentID }
        if isAlive(kitID) {
            updateRelationship(from: kitID, to: parentID) {
                $0.add(.like, -Int.random(in: 10...30, using: &rng))
                $0.add(.comfort, -Int.random(in: 10...30, using: &rng))
                $0.add(.trust, -Int.random(in: 5...15, using: &rng))
            }
        }
        if isAlive(parentID) {
            updateRelationship(from: parentID, to: kitID) {
                $0.add(.like, -20)
                $0.add(.comfort, -20)
                $0.add(.trust, -10)
            }
        }
        return true
    }

    /// Clangen's ChangeGenderScreen: letters, digits and spaces only. Returns false for an
    /// outsider or an empty identity.
    @discardableResult
    mutating func setGender(_ id: UUID, genderAlign: GenderAlign, pronouns: Pronouns) -> Bool {
        let cleaned = String(genderAlign.rawValue.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
        guard let i = index(of: id), !cleaned.isEmpty else { return false }
        cats[i].genderAlign = GenderAlign(rawValue: cleaned)
        cats[i].pronouns = pronouns
        return true
    }
}

extension MoonEngine {
    /// A player's rank change from Clangen's RoleScreen. Returns false if the change isn't allowed.
    @discardableResult
    func changeRank(_ rank: Rank, for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        guard let cat = clan[id], clan.isAlive(id),
              cat.rank.manualTargets(leaderVacant: clan.leaderVacant, deputyVacant: clan.deputyVacant).contains(rank)
        else { return false }
        switch rank {
        case .leader:
            if clan.deputy == id { clan.deputy = nil }
            setRank(.leader, for: id, in: &clan, using: &rng)
            clan.leader = id
            crownLeader(id, in: &clan, using: &rng)
        case .deputy:
            setRank(.deputy, for: id, in: &clan, using: &rng)
            clan.deputy = id
        default:
            setRank(rank, for: id, in: &clan, using: &rng)
            if clan.leader == id { clan.leader = nil }
            if clan.deputy == id { clan.deputy = nil }
        }
        return true
    }

    /// Clan cats who could mentor this apprentice, in roster order.
    static func mentorCandidates(for id: UUID, in clan: Clan, noCurrentApprentices: Bool = false, noFormerApprentices: Bool = false) -> [Cat] {
        guard let apprentice = clan[id] else { return [] }
        return clan.living.filter { mentor in
            canMentor(mentor, apprentice)
                && (!noCurrentApprentices || mentor.apprentices.isEmpty)
                && (!noFormerApprentices || (mentor.formerApprentices.isEmpty && (apprentice.rank != .apprentice || mentor.apprentices.isEmpty)))
        }
    }

    /// Clangen's ChooseMentorScreen: the old mentor keeps the apprentice as a former apprentice
    /// once it's past 6 moons. `nil` removes the mentor until the next moon assigns one.
    static func setMentor(_ mentorID: UUID?, for apprenticeID: UUID, in clan: inout Clan) {
        guard let a = clan.index(of: apprenticeID) else { return }
        let apprentice = clan.cats[a]
        if let old = apprentice.mentor, let m = clan.index(of: old) {
            clan.cats[m].apprentices.removeAll { $0 == apprenticeID }
            if apprentice.moons > 6, !clan.cats[m].formerApprentices.contains(apprenticeID) {
                clan.cats[m].formerApprentices.append(apprenticeID)
            }
        }
        clan.cats[a].mentor = nil
        guard let mentorID, mentorID != apprentice.mentor, canMentor(clan[mentorID], apprentice), let m = clan.index(of: mentorID) else { return }
        clan.cats[a].mentor = mentorID
        clan.cats[m].apprentices.append(apprenticeID)
        clan.cats[m].formerApprentices.removeAll { $0 == apprenticeID }
    }
}

extension RelationshipEngine {
    /// Clangen's player-initiated breakup: both cats' feelings drop, then they stop being mates.
    func breakUp(_ a: UUID, _ b: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard clan[a]?.mates.contains(b) == true else { return }
        if clan[a]?.isAlive == true {
            clan.updateRelationship(from: a, to: b) {
                $0.add(.romance, -Int.random(in: 20...60, using: &rng))
                $0.add(.comfort, -Int.random(in: 10...30, using: &rng))
                $0.add(.trust, -Int.random(in: 5...15, using: &rng))
            }
        }
        if clan[b]?.isAlive == true {
            clan.updateRelationship(from: b, to: a) {
                $0.add(.romance, -40)
                $0.add(.comfort, -20)
                $0.add(.trust, -10)
            }
        }
        unsetMates(a, b, in: &clan)
    }
}
