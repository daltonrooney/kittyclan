import SwiftUI

/// One afterlife's residents over its art, filtered by name and sorted.
struct AfterlifeGrid: View {
    @Environment(AppModel.self) private var model
    let afterlife: Afterlife
    let sort: AfterlifeSort
    let search: String
    let select: (Cat) -> Void

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 12)]

    var body: some View {
        let residents = model.clan?.residents(of: afterlife) ?? []
        let shown = sorted(residents.filter(matchesSearch))
        Group {
            if residents.isEmpty {
                ContentUnavailableView(afterlife.emptyTitle, systemImage: afterlife.symbol, description: Text(afterlife.emptyMessage))
                    .modifier(AfterlifeCard())
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
                    .modifier(AfterlifeCard())
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shown) { cat in
                            AfterlifeCatCell(cat: cat) { select(cat) }
                        }
                    }
                    .padding()
                    footer
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let faded = model.fadedCount(in: afterlife)
        if faded > 0 {
            Text(faded == 1 ? "1 cat has faded from \(afterlife.label)." : "\(faded) cats have faded from \(afterlife.label).")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom)
        }
    }

    private func matchesSearch(_ cat: Cat) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || model.displayName(cat).localizedStandardContains(query)
    }

    private func sorted(_ cats: [Cat]) -> [Cat] {
        let guides = cats.filter(model.isGuide)
        let rest = cats.filter { !model.isGuide($0) }.sorted { a, b in
            switch sort {
            case .rank:
                let (ra, rb) = (rankOrder(a), rankOrder(b))
                if ra != rb { return ra < rb }
            case .death:
                if a.deadFor != b.deadFor { return a.deadFor > b.deadFor }
            case .name:
                break
            }
            return model.displayName(a).localizedStandardCompare(model.displayName(b)) == .orderedAscending
        }
        return guides + rest
    }

    private func rankOrder(_ cat: Cat) -> Int {
        Rank.displayOrder.firstIndex(of: cat.lastClanRank ?? cat.rank) ?? Rank.displayOrder.count
    }
}

private struct AfterlifeCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .padding()
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: .rect(cornerRadius: 20))
            .padding(40)
            .frame(maxHeight: .infinity)
    }
}
