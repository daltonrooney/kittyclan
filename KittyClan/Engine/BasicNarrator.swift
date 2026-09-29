import Foundation

/// Plain log text for moon events, used where no Clangen template applies.
struct BasicNarrator: Narrator {
    let names: NameGenerator

    func name(_ id: UUID?, in clan: Clan) -> String {
        guard let cat = clan[id] else { return "a cat" }
        return names.display(cat.name, rank: cat.rank)
    }

    func text(for event: MoonEvent, in clan: Clan, using rng: inout some RandomNumberGenerator) -> String {
        switch event {
        case .founded:
            "\(clan.displayName) has been founded, led by \(name(clan.leader, in: clan))."
        case .apprenticed(let cat, let mentor, _):
            mentor.map { "\(name(cat, in: clan)) has reached the age of six moons and has been made an apprentice, with \(name($0, in: clan)) as their mentor." }
                ?? "\(name(cat, in: clan)) has reached the age of six moons and has been made an apprentice."
        case .newMentor(let apprentice, let mentor):
            "\(name(mentor, in: clan)) is now mentoring \(name(apprentice, in: clan))."
        case .graduated(let cat, _):
            clan[cat]?.rank == .medicineCat
                ? "\(name(cat, in: clan)) has been welcomed as a full medicine cat."
                : "\(clan.displayName) welcomes \(name(cat, in: clan)) as a new warrior."
        case .retired(let cat):
            "\(name(cat, in: clan)) has retired to the elders' den."
        case .deputyAppointed(let cat):
            "\(name(cat, in: clan)) has been chosen as the new deputy."
        case .becameLeader(let cat, _):
            "\(name(cat, in: clan)) has become the new leader of the Clan."
        case .leaderLostLife(let cat, let lives):
            lives == 1 ? "\(name(cat, in: clan)) has 1 life left." : "\(name(cat, in: clan)) has \(lives) lives left."
        case .died(let cat, let cause):
            switch cause {
            case .oldAge: "\(name(cat, in: clan)) died peacefully of old age."
            case .childbirth: "\(name(cat, in: clan)) died while kitting."
            case .misfortune: "\(name(cat, in: clan)) died."
            }
        case .becameMates(let a, let b):
            "\(name(a, in: clan)) and \(name(b, in: clan)) have become mates."
        case .expecting(let mother):
            "\(name(mother, in: clan)) is expecting kits."
        case .born(let mother, let father, let kits):
            "\(name(mother, in: clan)) had a litter of \(kits.count) with \(name(father, in: clan))."
        case .adopted(let parents, let kits):
            "\(parents.map { name($0, in: clan) }.joined(separator: " and ")) found a litter of \(kits.count) kits and \(parents.count == 1 ? "decides" : "decide") to adopt them."
        case .joined(let cat, _):
            "\(name(cat, in: clan)) has joined the Clan."
        case .litterFound(let kits, _):
            "A litter of \(kits.count) kits has been taken in by the Clan."
        case .noDeputy:
            "There are no cats fit to become deputy."
        case .lowPrey:
            "\(clan.displayName) doesn't have enough prey for next moon!"
        case .story(let pick, _):
            pick.template
        }
    }
}
