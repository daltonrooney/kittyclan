import SwiftUI

/// How one cat feels about another, as relationship meters.
struct MediationFeelingsView: View {
    @Environment(AppModel.self) private var model
    let from: Cat
    let to: Cat

    private static let values: [RelationshipValue] = [.romance, .like, .respect, .comfort, .trust]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(model.displayName(from)) → \(model.displayName(to))")
                .font(.subheadline.bold())
                .lineLimit(1)
            if let relationship = model.clan?.relationship(from: from.id, to: to.id) {
                HStack(spacing: 10) {
                    ForEach(Self.values, id: \.self) { value in
                        RelationshipMeter(value: value, amount: relationship[value])
                    }
                }
            } else {
                Text("Doesn't know \(model.displayName(to)) yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
