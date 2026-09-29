import Foundation

extension MoonEngine {
    /// Clangen's `[transition_related]` config: 1 in 256 each moon, twice as likely for kittens and
    /// adolescents and half as likely from adulthood on.
    static func comingOutChance(for age: CatAge) -> Int {
        switch age {
        case .kitten, .adolescent: 256 - 128
        case .adult, .seniorAdult, .senior: 256 + 256
        default: 256
        }
    }

    /// Clangen's `attempt_coming_out`: a cat of 3 moons or more whose gender still matches its sex
    /// may come out, taking a new identity and that identity's pronouns.
    func attemptComingOut(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let cat = clan[id], cat.moons >= 3, cat.isCis,
              Int.random(in: 0..<Self.comingOutChance(for: cat.age), using: &rng) == 0,
              let (event, cats) = library?.transitionEvent(for: cat, in: clan, using: &rng),
              let i = clan.index(of: id), let text = event.strings.randomElement(using: &rng)
        else { return [] }
        let gender = pick(event.newGenders, &rng)
        clan.cats[i].genderAlign = gender
        clan.cats[i].pronouns = clan.newPronouns(for: gender)

        var story = StoryPick(template: text, cats: cats, relationshipChanges: event.changes, newAccessory: event.accessories)
        if !giveAccessory(for: &story, in: &clan, using: &rng) { story.newAccessory = [] }
        relationships?.apply(story.relationshipChanges, cats: story.allCats, in: &clan, using: &rng)
        return [.story(story, .info)]
    }
}
