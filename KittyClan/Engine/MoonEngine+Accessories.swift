import Foundation

/// Clangen's accessory events: cats occasionally come home wearing something new.
extension MoonEngine {
    private static let happyTraits: Set<String> = [
        "adventurous", "childish", "confident", "daring", "playful", "attention-seeker",
        "sweet", "troublesome", "impulsive", "inquisitive", "strange", "shameless",
    ]
    private static let grumpyTraits: Set<String> = ["cold", "strict", "bossy", "bullying", "insecure", "nervous"]

    /// Clangen's `gain_accessories`: a 1-in-`chance` roll for an accessory event, where `chance`
    /// starts at 150 and depends on rank, age, trait, accessories worn and a ceremony this moon.
    static func accessoryChance(for cat: Cat, hadCeremony: Bool) -> Int {
        var chance = 150
        if cat.rank == .medicineCat || cat.rank == .medicineApprentice { chance -= 80 }
        switch cat.age {
        case .kitten, .adolescent: chance -= 20
        case .seniorAdult, .senior: chance += 20
        default: break
        }
        if happyTraits.contains(cat.personality.trait) {
            chance -= 30
        } else if grumpyTraits.contains(cat.personality.trait) {
            chance += 30
        }
        if !cat.appearance.accessories.isEmpty { chance += 50 }
        if hadCeremony { chance -= 20 }
        return max(chance, 1)
    }

    func gainAccessory(_ id: UUID, hadCeremony: Bool, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id], cat.isAlive, cat.appearance.accessories.count < 3 else { return [] }
        let chance = Self.accessoryChance(for: cat, hadCeremony: hadCeremony)
        guard Int(Double.random(in: 0..<1, using: &rng) * Double(chance)) == 0,
              var pick = library?.accessoryEvent(for: cat, ceremony: hadCeremony, in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
              giveAccessory(for: &pick, in: &clan, using: &rng),
              addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) != nil
        else { return [] }
        relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
        applyEventEffects(pick, in: &clan, using: &rng)
        applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
        return [.story(pick, .info)]
    }

    /// Gives `m_c` the event's accessory and names it in the text (`acc_singular`, `acc_plural`).
    /// Returns false when the cat can wear none of them, which cancels the event.
    func giveAccessory(for pick: inout StoryPick, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> Bool {
        guard !pick.newAccessory.isEmpty else { return true }
        guard let id = pick.cats["m_c"], let i = clan.index(of: id),
              let accessory = factory.appearance.eventAccessory(from: pick.newAccessory, for: clan.cats[i].appearance, using: &rng)
        else { return false }
        clan.cats[i].appearance.accessories.append(accessory)
        let index = factory.appearance.index
        pick.template = pick.template
            .replacing("acc_plural", with: index.accessoryName(accessory, form: \.many))
            .replacing("acc_singular", with: index.accessoryName(accessory, form: \.one))
        return true
    }
}
