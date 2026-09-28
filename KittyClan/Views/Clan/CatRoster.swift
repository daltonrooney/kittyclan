import SwiftUI

struct CatRoster: View {
    @Environment(AppModel.self) private var model

    private static let outsiders = "outsiders"

    var body: some View {
        let living = Dictionary(grouping: model.clan?.living ?? [], by: \.rank)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(Rank.displayOrder, id: \.self) { rank in
                        if let cats = living[rank] {
                            RankSection(title: rank.sectionTitle, cats: cats)
                        }
                    }
                    RememberedSection(cats: model.clan?.dead ?? [])
                    OutsidersSection(isExpanded: Self.expandsOutsiders)
                        .id(Self.outsiders)
                }
                .padding()
            }
            #if DEBUG
            .task {
                if Self.expandsOutsiders { proxy.scrollTo(Self.outsiders, anchor: .top) }
            }
            #endif
        }
    }

    private static var expandsOutsiders: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "outsiders")
        #else
        false
        #endif
    }
}
