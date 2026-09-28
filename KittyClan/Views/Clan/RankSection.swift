import SwiftUI

struct RankSection: View {
    let title: String
    let cats: [Cat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())
                Text(cats.count, format: .number)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CatGrid(cats: cats)
        }
    }
}
