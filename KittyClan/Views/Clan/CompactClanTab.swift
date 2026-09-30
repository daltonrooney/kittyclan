/// The sections of the clan screen on narrow screens, where the moon log can't sit beside the cats.
enum CompactClanTab: String, CaseIterable, Identifiable {
    case camp
    case cats
    case moons

    var id: Self { self }

    var title: String {
        switch self {
        case .camp: "Camp"
        case .cats: "Cats"
        case .moons: "Moons"
        }
    }
}
