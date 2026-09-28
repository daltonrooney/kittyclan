import SwiftUI

struct RelationshipRow: View {
    enum Bond {
        case mate, exMate

        var label: String { self == .mate ? "Mate" : "Former mate" }
        var symbol: String { self == .mate ? "heart.fill" : "heart.slash" }
    }

    @Environment(AppModel.self) private var model
    let entry: CatRelationshipEntry
    let bond: Bond?

    private static let shownValues: [RelationshipValue] = [.like, .respect, .trust, .comfort]

    var body: some View {
        let name = model.displayName(entry.cat)
        let relationship = entry.relationship
        DisclosureGroup {
            NavigationLink(value: entry.cat.id) {
                Label("Visit \(name)", systemImage: "pawprint.fill")
            }
            if relationship.log.isEmpty {
                Text("Nothing memorable has happened between them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(relationship.log.indices.reversed(), id: \.self) { index in
                Text(relationship.log[index])
                    .font(.subheadline)
            }
        } label: {
            HStack(spacing: 12) {
                CatSprite(cat: entry.cat)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.headline)
                        if let bond {
                            Label(bond.label, systemImage: bond.symbol)
                                .font(.caption.bold())
                                .foregroundStyle(.pink)
                        }
                        Text(entry.cat.rank.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        ForEach(values(for: relationship), id: \.self) { value in
                            RelationshipMeter(value: value, amount: relationship[value])
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(name: name, relationship: relationship))
        }
    }

    private func values(for relationship: Relationship) -> [RelationshipValue] {
        relationship[.romance] > 0 ? Self.shownValues + [.romance] : Self.shownValues
    }

    private func accessibilityText(name: String, relationship: Relationship) -> String {
        let feelings = values(for: relationship).map { $0.tierText(for: relationship[$0]) }.joined(separator: ", ")
        return [name, bond?.label, feelings].compactMap(\.self).joined(separator: ", ")
    }
}
