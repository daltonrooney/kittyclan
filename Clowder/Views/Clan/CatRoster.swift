import SwiftUI

struct CatRoster: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let living = Dictionary(grouping: model.clan?.living ?? [], by: \.rank)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(Rank.displayOrder, id: \.self) { rank in
                    if let cats = living[rank] {
                        RankSection(title: rank.sectionTitle, cats: cats)
                    }
                }
                RememberedSection(cats: model.clan?.dead ?? [])
            }
            .padding()
        }
    }
}
