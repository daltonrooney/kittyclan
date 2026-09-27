import Foundation

struct Cat: Identifiable, Codable, Hashable, Sendable {
    enum Sex: String, Codable, Sendable { case female, male }

    let id: UUID
    var name: CatName
    var sex: Sex
    var moons: Int
    var appearance: CatAppearance

    var age: CatAge {
        CatAge.allCases.first { $0.moons.contains(moons) } ?? .senior
    }
}

/// Makes random cats: appearance, age and name.
struct CatFactory: Sendable {
    let appearance: AppearanceGenerator
    let names: NameGenerator

    func make(age: CatAge? = nil, using rng: inout some RandomNumberGenerator) -> Cat {
        let age = age ?? pick(CatAge.allCases, &rng)
        let sex: Cat.Sex = Bool.random(using: &rng) ? .female : .male
        let looks = appearance.generate(female: sex == .female, age: age, using: &rng)
        return Cat(
            id: UUID(),
            name: names.generate(for: looks, using: &rng),
            sex: sex,
            moons: Int.random(in: age.moons, using: &rng),
            appearance: looks
        )
    }
}
