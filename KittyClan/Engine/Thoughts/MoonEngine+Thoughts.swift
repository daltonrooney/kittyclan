import Foundation

extension MoonEngine {
    /// Clangen gives every cat, living or dead, a fresh thought each moon.
    func generateThoughts(in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let thoughts else { return }
        let context = ThoughtContext(clan: clan)
        var used: Set<String> = []
        func next(for cat: Cat) -> Thought? {
            let kind = cat.nextThought ?? (cat.id == clan.guide ? .isGuide : cat.isDead ? .whileDead : .whileAlive)
            if kind == .halfBloodKitting, let thought = halfBloodKittingThought(for: cat, in: clan) { return thought }
            return thoughts.thought(kind, for: cat, about: clan[cat.nextThoughtAbout], in: context, used: &used, using: &rng)
                ?? (kind == .whileAlive || kind == .whileDead ? nil
                    : thoughts.thought(cat.isDead ? .whileDead : .whileAlive, for: cat, in: context, used: &used, using: &rng))
        }
        for i in clan.cats.indices {
            clan.cats[i].thought = next(for: clan.cats[i])
            clan.cats[i].nextThought = nil
            clan.cats[i].nextThoughtAbout = nil
        }
        for i in clan.outsiders.indices {
            clan.outsiders[i].thought = next(for: clan.outsiders[i])
            clan.outsiders[i].nextThought = nil
        }
    }

    /// Clangen's `half_blood_kitting_thought`, for however many of the cat's kits there are.
    func halfBloodKittingThought(for cat: Cat, in clan: Clan) -> Thought? {
        let kits = clan.cats.count { $0.parents.contains(cat.id) }
        guard let text = library?.pregnancy.halfBloodKittingThought[kits == 1 ? "one" : "many"] else { return nil }
        return Thought(text: text)
    }

    /// A new thought for one cat right away, e.g. after the player exiles it.
    func refreshThought(_ kind: ThoughtKind? = nil, for id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let thoughts, let cat = clan[id] else { return }
        let context = ThoughtContext(clan: clan)
        var used: Set<String> = []
        let kind = kind ?? cat.nextThought ?? (cat.id == clan.guide ? .isGuide : cat.isDead ? .whileDead : .whileAlive)
        let thought = thoughts.thought(kind, for: cat, about: clan[cat.nextThoughtAbout], in: context, used: &used, using: &rng)
        if let i = clan.index(of: id) {
            clan.cats[i].thought = thought
            clan.cats[i].nextThought = nil
            clan.cats[i].nextThoughtAbout = nil
        } else if let i = clan.outsiders.firstIndex(where: { $0.id == id }) {
            clan.outsiders[i].thought = thought
            clan.outsiders[i].nextThought = nil
        }
    }
}
