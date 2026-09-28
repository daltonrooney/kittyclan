import Foundation

enum DeathCause: String, Codable, Sendable {
    case oldAge, misfortune, childbirth
}

/// Something that happened during a moon, before it is turned into text.
enum MoonEvent: Sendable {
    case founded
    case apprenticed(UUID, mentor: UUID?, oldName: String)
    case newMentor(apprentice: UUID, mentor: UUID)
    case graduated(UUID, oldName: String)
    case retired(UUID)
    case deputyAppointed(UUID)
    case becameLeader(UUID, oldName: String)
    case leaderLostLife(UUID, livesLeft: Int)
    case died(UUID, DeathCause)
    case becameMates(UUID, UUID)
    case expecting(mother: UUID)
    case born(mother: UUID, father: UUID, kits: [UUID])
    case joined(UUID, foundBy: UUID)
    case litterFound([UUID], foundBy: UUID)
    case noDeputy
    /// A Clangen event whose text is filled in by the narrator.
    case story(StoryPick, LogEntry.Kind)

    var kind: LogEntry.Kind {
        switch self {
        case .founded, .noDeputy: .info
        case .story(_, let kind): kind
        case .apprenticed, .newMentor, .graduated, .retired, .deputyAppointed, .becameLeader: .ceremony
        case .leaderLostLife, .died: .death
        case .becameMates, .expecting: .relationship
        case .born: .birth
        case .joined, .litterFound: .join
        }
    }

    var cats: [UUID] {
        switch self {
        case .founded, .noDeputy: []
        case .apprenticed(let cat, let mentor, _): [cat] + [mentor].compactMap { $0 }
        case .story(let pick, _): pick.cats.sorted { $0.key < $1.key }.map(\.value)
        case .newMentor(let a, let m): [a, m]
        case .graduated(let c, _), .retired(let c), .deputyAppointed(let c), .becameLeader(let c, _): [c]
        case .joined(let c, let by): [c, by]
        case .leaderLostLife(let c, _), .died(let c, _): [c]
        case .becameMates(let a, let b): [a, b]
        case .expecting(let m): [m]
        case .born(let m, let f, let kits): [m, f] + kits
        case .litterFound(let kits, let by): kits + [by]
        }
    }
}

extension MoonEvent {
    /// Cats who just arrived in the Clan.
    var newcomers: [UUID] {
        switch self {
        case .joined(let cat, _): [cat]
        case .litterFound(let kits, _): kits
        default: []
        }
    }
}

/// Turns moon events into log text.
protocol Narrator: Sendable {
    func text(for event: MoonEvent, in clan: Clan, using rng: inout some RandomNumberGenerator) -> String
}

extension Narrator {
    func entry(_ event: MoonEvent, in clan: Clan, using rng: inout some RandomNumberGenerator) -> LogEntry {
        LogEntry(kind: event.kind, text: text(for: event, in: clan, using: &rng), cats: event.cats)
    }
}
