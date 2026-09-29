import Foundation

/// The choices Clangen leaves to the player: roles, mentors, mates and names. None of them
/// are written to the moon log, as in Clangen.
extension Rank {
    /// Clangen's RoleScreen buttons for a cat of this rank.
    func manualTargets(leaderVacant: Bool, deputyVacant: Bool) -> [Rank] {
        var targets: [Rank]
        switch self {
        case .apprentice: targets = [.medicineApprentice, .mediatorApprentice]
        case .medicineApprentice: targets = [.apprentice, .mediatorApprentice]
        case .mediatorApprentice: targets = [.apprentice, .medicineApprentice]
        case .warrior: targets = [.leader, .deputy, .medicineCat, .mediator, .elder]
        case .deputy: targets = [.leader, .warrior, .elder]
        case .medicineCat: targets = [.warrior, .mediator, .elder]
        case .mediator: targets = [.leader, .deputy, .warrior, .medicineCat, .elder]
        case .elder: targets = [.leader, .deputy, .warrior, .medicineCat, .mediator]
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
