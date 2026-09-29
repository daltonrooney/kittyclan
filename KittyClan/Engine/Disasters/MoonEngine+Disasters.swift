import Foundation

/// Clangen's `disasters` setting: mass-death events (`handle_mass_death`).
extension MoonEngine {
    /// Each moon a healthy cat's death roll has this 1-in-N chance of setting off a disaster.
    static let disasterChance = 1024

    /// Clangen's `handle_mass_death`: needs more than 15 eligible cats, then kills between 2 and
    /// half of them (at most 9, fewer being likelier), always including the cat who rolled it.
    /// Events tagged `lost` carry the cats off instead. Disasters touching two cats or fewer
    /// don't happen.
    ///
    /// Clangen filters the pool while iterating it, skipping every other cat, and treats
    /// negated ages like "-kitten" as excluding everyone; here each cat is checked against the
    /// event's `m_c` properly.
    func massDeath(by id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard clan.disasters, let cat = clan[id],
              let (found, pool) = library?.massDeathEvent(for: cat, in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
              pool.count > 15
        else { return [] }
        let most = min(pool.count / 2, 10)
        let count = most > 2 ? weighted((2..<most).map { ($0, Int(10_000 / (0.75 * Double($0)))) }, &rng) : 2
        var caught = Array(pool.shuffled(using: &rng).prefix(count))
        if !caught.contains(id) { caught.append(id) }
        guard caught.count > 2 else { return [] }

        var pick = found
        pick.cats = [:]
        pick.groupCats["multi_cat"] = caught
        if pick.tags.contains("lost") {
            for victim in caught { loseCat(victim, in: &clan, using: &rng) }
            return [.story(pick, .death)]
        }
        pick.deaths = caught
        return applyDeathEvent(pick, cause: .misfortune, in: &clan, using: &rng)
    }
}
