import Foundation

extension MoonEngine {
    /// Gives cats from saves without backstories one that fits: founders are `clan_founder`, cats
    /// born to Clan cats are `clanborn`, and loners, rogues and kittypets get one from their way of life.
    static func fillMissingBackstories(in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        let members = Set(clan.cats.map(\.id))
        func backstory(for cat: Cat) -> String {
            if !cat.parents.isEmpty, cat.parents.contains(where: members.contains) { return "clanborn" }
            let baby = cat.age == .newborn || cat.age == .kitten
            return Backstories.bundled.random(for: cat.origin, baby: baby, using: &rng)
        }
        for i in clan.cats.indices where clan.cats[i].backstory == nil {
            clan.cats[i].backstory = backstory(for: clan.cats[i])
        }
        for i in clan.outsiders.indices where clan.outsiders[i].backstory == nil {
            clan.outsiders[i].backstory = backstory(for: clan.outsiders[i])
        }
    }
}
