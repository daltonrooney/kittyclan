import Foundation

extension CatFactory {
    /// Clangen's `generate_new_catskills`: kits get an interest, apprentices a stronger interest,
    /// adults a real skill whose tier grows with age, and sometimes a second skill.
    static func skills(rank: Rank, age: CatAge, using rng: inout some RandomNumberGenerator) -> CatSkills {
        if rank == .newborn || age == .newborn { return CatSkills() }
        if rank == .kitten || age == .kitten {
            return CatSkills(primary: Skill(path: .random(using: &rng), points: 0, interestOnly: true))
        }
        if rank.isApprentice || age == .adolescent {
            let primary = Skill.random(tier: 1, interestOnly: true, using: &rng)
            let secondary = Int.random(in: 1...3, using: &rng) == 1
                ? Skill.random(tier: 1, excluding: [primary.path], interestOnly: true, using: &rng) : nil
            return CatSkills(primary: primary, secondary: secondary)
        }
        let (primaryTier, secondaryTier): (Int, Int) = switch age {
        case .youngAdult: (1 + Int.random(in: 0...1, using: &rng), 1 + Int.random(in: 0...1, using: &rng))
        case .adult: (1 + Int.random(in: 0...2, using: &rng), 1 + Int.random(in: 0...1, using: &rng))
        case .seniorAdult: (1 + Int.random(in: 1...2, using: &rng), 1 + Int.random(in: 0...1, using: &rng))
        default: (1 - Int.random(in: 0...1, using: &rng), 1)
        }
        let primary = Skill.random(tier: primaryTier, using: &rng)
        let secondary = Int.random(in: 1...2, using: &rng) == 1
            ? Skill.random(tier: secondaryTier, excluding: [primary.path], using: &rng) : nil
        return CatSkills(primary: primary, secondary: secondary)
    }
}

extension MoonEngine {
    /// Clangen's `progress_skill`, run after ceremonies each moon.
    func progressSkills(_ id: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let i = clan.index(of: id), clan.cats[i].rank != .newborn, clan.cats[i].moons > 0 else { return }
        var cat = clan.cats[i]
        var skills = cat.skills

        if skills.primary == nil {
            let parental = cat.parents.compactMap { clan[$0] }.flatMap { $0.skills.all.map(\.path) }
            let path = !parental.isEmpty && Bool.random(using: &rng) ? pick(parental, &rng) : SkillPath.random(using: &rng)
            skills.primary = Skill(path: path, points: 0, interestOnly: cat.rank.isApprentice || cat.rank == .kitten)
        }

        if cat.rank == .kitten || cat.rank.isApprentice {
            if skills.secondary == nil, oneIn(22, &rng), let primary = skills.primary {
                skills.secondary = Skill(path: .random(excluding: [primary.path], using: &rng), points: 0, interestOnly: true)
            }
            if oneIn(4, &rng) {
                let amount = cat.rank == .kitten ? Int.random(in: 1...4, using: &rng) : Int.random(in: 2...5, using: &rng)
                if skills.secondary != nil, Bool.random(using: &rng) { skills.secondary?.add(amount) } else { skills.primary?.add(amount) }
            }
        } else if cat.moons > 120 {
            skills.primary?.interestOnly = false
            skills.secondary?.interestOnly = false
            if oneIn(max(1, 160 - cat.moons), &rng) {
                skills.primary?.add(-1)
                skills.secondary?.add(-1)
            }
        } else {
            if let primary = skills.primary, primary.interestOnly, let secondary = skills.secondary {
                let swap = weighted([(false, primary.points + 1), (true, secondary.points + 1)], &rng)
                if swap { (skills.primary, skills.secondary) = (secondary, primary) }
            }
            skills.primary?.interestOnly = false
            skills.secondary?.interestOnly = false
            if skills.secondary == nil, oneIn(300, &rng), let primary = skills.primary {
                skills.secondary = Skill.random(tier: 1, excluding: [primary.path], using: &rng)
            }
            if oneIn(max(1, cat.moons / 4), &rng) { skills.primary?.add(1) }
        }
        cat.skills = skills
        clan.cats[i] = cat
    }

    /// Clangen's `mentor_influence` on skills: a mentor improves a skill of a kind they share.
    func mentorSkillInfluence(on id: UUID, from mentorID: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let i = clan.index(of: id), let mentorPath = clan[mentorID]?.skills.primary?.path else { return }
        let kinds = mentorPath.kinds
        let skills = clan.cats[i].skills
        let primary = skills.primary.map { !$0.path.kinds.isDisjoint(with: kinds) } ?? false
        let secondary = skills.secondary.map { !$0.path.kinds.isDisjoint(with: kinds) } ?? false
        guard primary || secondary else { return }
        let amount = Int.random(in: 1...4, using: &rng)
        if primary, !secondary || Bool.random(using: &rng) {
            clan.cats[i].skills.primary?.add(amount)
        } else {
            clan.cats[i].skills.secondary?.add(amount)
        }
    }

    /// Clangen's `mentor_influence` on personality: a facet nudged toward the mentor's.
    func mentorPersonalityInfluence(on id: UUID, from mentorID: UUID, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let i = clan.index(of: id), let mentor = clan[mentorID]?.personality else { return }
        var p = clan.cats[i].personality
        let facets: [WritableKeyPath<Personality, Int>] = [\.lawfulness, \.sociability, \.aggression, \.stability]
        let diffs = facets.map { (path: $0, diff: mentor[keyPath: $0] - p[keyPath: $0]) }.filter { $0.diff != 0 }
        guard !diffs.isEmpty else { return }
        let choice = weighted(diffs.map { ($0, abs($0.diff)) }, &rng)
        p[keyPath: choice.path] += (choice.diff > 0 ? 1 : -1) * Int.random(in: 1...2, using: &rng)
        factory.traits.setKit(p.isKit, &p, using: &rng)
        clan.cats[i].personality = p
    }

    /// Clangen's `rank_change_traits_skill`: up to two rounds of mentor influence at graduation.
    func graduationInfluence(on id: UUID, from mentorID: UUID?, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        guard let mentorID, clan[mentorID] != nil else { return }
        for _ in 0..<Int.random(in: 0...2, using: &rng) {
            mentorPersonalityInfluence(on: id, from: mentorID, in: &clan, using: &rng)
            mentorSkillInfluence(on: id, from: mentorID, in: &clan, using: &rng)
        }
    }
}
