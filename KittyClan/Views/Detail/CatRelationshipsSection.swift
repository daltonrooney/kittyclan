import SwiftUI

struct CatRelationshipsSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    @State private var showsAll = false

    private static let shownByDefault = 8

    var body: some View {
        let entries = model.relationships(of: cat)
        let shown = showsAll ? entries : Array(entries.prefix(Self.shownByDefault))
        Section("Relationships") {
            if entries.isEmpty {
                Text("\(model.displayName(cat)) hasn't formed strong feelings about anyone yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { entry in
                RelationshipRow(entry: entry, bond: bond(with: entry.cat))
            }
            if entries.count > Self.shownByDefault {
                Button(showsAll ? "Show fewer" : "Show all \(entries.count)", action: toggleShowsAll)
            }
        }
    }

    private func bond(with other: Cat) -> RelationshipRow.Bond? {
        if cat.mates.contains(other.id) { return .mate }
        if cat.previousMates.contains(other.id) { return .exMate }
        return nil
    }

    private func toggleShowsAll() {
        withAnimation { showsAll.toggle() }
    }
}
