import Foundation

/// Makes new cats: founding candidates, newborn kits and cats who join the Clan.
struct CatFactory: Sendable {
    let appearance: AppearanceGenerator
    let names: NameGenerator
    let traits: TraitTable

    /// Clangen's gender alignment roll: babies match their sex; older cats are rarely
    /// nonbinary (1 in 76) or trans (1 in 51).
    static func genderAlign(for sex: Cat.Sex, baby: Bool, using rng: inout some RandomNumberGenerator) -> GenderAlign {
        guard !baby else { return .cis(sex) }
        if Int.random(in: 0...75, using: &rng) == 1 { return .nonbinary }
        if Int.random(in: 0...50, using: &rng) == 1 { return .trans(sex) }
        return .cis(sex)
    }

    /// Clangen's `_get_random_age_from_rank` and moon ranges for new cats.
    static func randomMoons(for rank: Rank, using rng: inout some RandomNumberGenerator) -> Int {
        switch rank {
        case .newborn: 0
        case .kitten: Int.random(in: 1...5, using: &rng)
        case .apprentice, .medicineApprentice, .mediatorApprentice: Int.random(in: 6...11, using: &rng)
        case .elder: Int.random(in: 120...300, using: &rng)
        default:
            switch pick([CatAge.youngAdult, .adult, .adult, .seniorAdult], &rng) {
            case .youngAdult: Int.random(in: 12...47, using: &rng)
            case .adult: Int.random(in: 48...95, using: &rng)
            default: Int.random(in: 96...119, using: &rng)
            }
        }
    }

    /// Clangen's starting experience for cats generated at a given age.
    static func startingExperience(moons: Int, using rng: inout some RandomNumberGenerator) -> Int {
        switch CatAge(moons: moons) {
        case .newborn, .kitten, .adolescent: 0
        case .youngAdult, .adult: Int.random(in: 51...240, using: &rng)
        case .seniorAdult: Int.random(in: 171...320, using: &rng)
        case .senior: Int.random(in: 241...321, using: &rng)
        }
    }

    /// - Parameters:
    ///   - sex: Clangen's gender override; random when nil.
    ///   - theyThem: Clangen's `they them default` setting.
    func make(
        rank: Rank,
        moons: Int? = nil,
        origin: Cat.Origin = .founder,
        sex: Cat.Sex? = nil,
        theyThem: Bool = false,
        using rng: inout some RandomNumberGenerator
    ) -> Cat {
        let moons = moons ?? Self.randomMoons(for: rank, using: &rng)
        let random: Cat.Sex = Bool.random(using: &rng) ? .female : .male
        let sex = sex ?? random
        let age = CatAge(moons: moons)
        let baby = age == .newborn || age == .kitten
        let looks = appearance.generate(female: sex == .female, age: age, using: &rng)
        let name = names.generate(for: looks, using: &rng)
        let gender = Self.genderAlign(for: sex, baby: baby, using: &rng)
        var cat = Cat(
            id: UUID(),
            name: name,
            sex: sex,
            genderAlign: gender,
            pronouns: [theyThem ? .they : gender.defaultPronouns],
            moons: moons,
            appearance: looks,
            personality: traits.random(kit: baby, using: &rng),
            skills: Self.skills(rank: rank, age: age, using: &rng),
            rank: rank,
            origin: origin,
            experience: Self.startingExperience(moons: moons, using: &rng)
        )
        cat.backstory = Backstories.bundled.random(for: origin, baby: baby, using: &rng)
        return cat
    }

    /// A newborn whose looks are inherited from its parents.
    func makeKit(mother: Cat, father: Cat, theyThem: Bool = false, using rng: inout some RandomNumberGenerator) -> Cat {
        let sex: Cat.Sex = Bool.random(using: &rng) ? .female : .male
        let looks = appearance.generate(
            female: sex == .female, age: .newborn,
            parents: [mother.appearance, father.appearance], using: &rng
        )
        var kit = Cat(
            id: UUID(),
            name: names.generate(for: looks, using: &rng),
            sex: sex,
            genderAlign: .cis(sex),
            pronouns: [theyThem ? .they : GenderAlign.cis(sex).defaultPronouns],
            moons: 0,
            appearance: looks,
            personality: traits.random(kit: true, using: &rng),
            rank: .newborn,
            origin: .clanborn,
            parents: [mother.id, father.id]
        )
        kit.backstory = "clanborn"
        return kit
    }

    /// A loner, rogue or kittypet who asks to join. Half keep their outsider name.
    func makeJoiner(origin: Cat.Origin, sex: Cat.Sex? = nil, theyThem: Bool = false, using rng: inout some RandomNumberGenerator) -> Cat {
        var cat = make(rank: .warrior, moons: Int.random(in: 23...120, using: &rng), origin: origin, sex: sex, theyThem: theyThem, using: &rng)
        if Bool.random(using: &rng) {
            cat.name = names.outsiderName(for: origin, using: &rng)
        }
        maybeCollar(&cat, using: &rng)
        return cat
    }

    /// Clangen gives half of the kittypets it creates a collar.
    func maybeCollar(_ cat: inout Cat, using rng: inout some RandomNumberGenerator) {
        guard cat.origin == .kittypet, Bool.random(using: &rng) else { return }
        cat.appearance.accessories.append(appearance.randomCollar(using: &rng))
    }
}
