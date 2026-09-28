import Foundation

/// Clangen's clan creation: 12 candidates, then leader, deputy, medicine cat and members.
struct ClanFounding: Sendable {
    static let candidateCount = 12
    static let rerolls = 3
    static let memberRange = 7...10
    static let maxNameLength = 11
    static let leaderRoles: Set<CatAge> = [.youngAdult, .adult, .seniorAdult, .senior]

    enum Role: String, CaseIterable, Sendable {
        case leader, deputy, medicineCat = "medicine cat", member
    }

    let factory: CatFactory

    /// Three candidates are always warriors; the rest are weighted kitten 1, apprentice 1, warrior 2, elder 1.
    func candidates(using rng: inout some RandomNumberGenerator) -> [Cat] {
        let warriors = Set((0..<Self.candidateCount).shuffled(using: &rng).prefix(3))
        return (0..<Self.candidateCount).map { i in
            let rank = warriors.contains(i)
                ? .warrior
                : weighted([(Rank.kitten, 1), (.apprentice, 1), (.warrior, 2), (.elder, 1)], &rng)
            return factory.make(rank: rank, using: &rng)
        }
    }

    static func canLead(_ cat: Cat) -> Bool {
        leaderRoles.contains(cat.age)
    }

    static func validateName(_ name: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        return !name.isEmpty && !name.hasPrefix(" ") && name.count <= maxNameLength
            && name.unicodeScalars.allSatisfy { !forbidden.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }

    /// Builds the Clan. Apprentices get random mentors.
    func found(
        prefix: String,
        leader: Cat,
        deputy: Cat,
        medicineCat: Cat,
        members: [Cat],
        engine: MoonEngine,
        using rng: inout some RandomNumberGenerator
    ) -> Clan {
        var leader = leader
        var deputy = deputy
        var medicineCat = medicineCat
        leader.rank = .leader
        deputy.rank = .deputy
        medicineCat.rank = .medicineCat

        var clan = Clan(
            prefix: prefix.trimmingCharacters(in: .whitespaces),
            cats: [leader, deputy, medicineCat] + members,
            leader: leader.id,
            deputy: deputy.id
        )
        for cat in clan.living where cat.rank.isApprentice {
            MoonEngine.assignMentor(to: cat.id, in: &clan, using: &rng)
        }
        engine.relationships?.initializeFounders(&clan, using: &rng)
        clan.history = [MoonLog(moon: 0, entries: [engine.narrator.entry(.founded, in: clan, using: &rng)])]
        return clan
    }
}
