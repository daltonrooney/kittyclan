/// How the clan screen shows the cats: sitting around camp, or as a list by rank.
enum ClanViewMode: String, CaseIterable, Identifiable {
    case camp
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .camp: "Camp"
        case .list: "List"
        }
    }

    var symbol: String {
        switch self {
        case .camp: "tent.fill"
        case .list: "square.grid.2x2.fill"
        }
    }
}
