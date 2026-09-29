import Foundation

/// Clangen's afterlife: the Clan's guide, the dead growing older, and fading.
extension MoonEngine {
    /// Clangen's guide ranks.
    private static let guideRanks: [Rank] = [
        .apprentice, .mediatorApprentice, .medicineApprentice, .warrior, .medicineCat, .leader, .mediator, .deputy, .elder,
    ]

    /// Clangen's `create_clan` guide: a StarClan cat dead for 20–200 moons.
    func makeGuide(for clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        var guide = factory.make(rank: pick(Self.guideRanks, &rng), using: &rng)
        guide.isDead = true
        guide.afterlife = .starClan
        guide.deadFor = Int.random(in: 20...200, using: &rng)
        guide.diedAtClanAge = clan.age - guide.deadFor
        guide.backstory = "clan_guide\(Int.random(in: 1...7, using: &rng))"
        clan.cats.append(guide)
        clan.guide = guide.id
    }

    /// Ages every cat in the afterlife by a moon and fades those who have been dead too long.
    func afterlifeMoon(in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        if clan.guide == nil { makeGuide(for: &clan, using: &rng) }
        for i in clan.cats.indices where clan.cats[i].isDead {
            settleLegacyDead(&clan.cats[i], isOutsider: false, in: clan)
            clan.cats[i].deadFor += 1
        }
        for i in clan.outsiders.indices where clan.outsiders[i].isDead {
            settleLegacyDead(&clan.outsiders[i], isOutsider: true, in: clan)
            clan.outsiders[i].deadFor += 1
        }
        guard clan.fading else { return }
        let fading = (clan.cats + clan.outsiders).filter {
            $0.isDead && $0.deadFor > Afterlife.ageToFade && !$0.preventFading && $0.id != clan.guide
        }
        for cat in fading { fade(cat.id, in: &clan) }
    }

    /// Cats who died before the afterlife existed join the guide's afterlife.
    private func settleLegacyDead(_ cat: inout Cat, isOutsider: Bool, in clan: Clan) {
        guard cat.afterlife == nil else { return }
        cat.afterlife = clan.afterlife(for: cat, isOutsider: isOutsider)
        cat.deadFor = max(0, clan.age - 1 - (cat.diedAtClanAge ?? clan.age - 1))
    }

    /// Clangen's fading: mates are freed, roles cleared, and only a record of the cat remains.
    func fade(_ id: UUID, in clan: inout Clan) {
        guard let cat = clan[id], let afterlife = cat.afterlife else { return }
        for i in clan.cats.indices where clan.cats[i].mates.contains(id) {
            clan.cats[i].mates.removeAll { $0 == id }
        }
        if clan.leader == id { clan.leader = nil }
        if clan.deputy == id { clan.deputy = nil }
        clan.relationships[id] = nil
        for key in clan.relationships.keys { clan.relationships[key]?[id] = nil }
        clan.nutrition[id] = nil
        clan.cats.removeAll { $0.id == id }
        clan.outsiders.removeAll { $0.id == id }
        clan.faded.append(FadedCat(
            id: id, name: cat.name, pronouns: cat.pronouns, rank: cat.rank, moons: cat.moons,
            deadFor: cat.deadFor, afterlife: afterlife, parents: cat.parents,
            adoptiveParents: cat.adoptiveParents
        ))
    }

    /// Resets the leader's lives and holds their nine-lives ceremony.
    func crownLeader(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        clan.leaderLives = Clan.maxLeaderLives
        guard let ceremonies, let i = clan.index(of: id) else { return }
        clan.cats[i].leaderCeremony = Self.leaderCeremony(for: id, in: clan, library: ceremonies, using: &rng)
    }
}
