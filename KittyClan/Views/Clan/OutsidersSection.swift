import SwiftUI

/// Clangen's "Cats Outside the Clans": loners, rogues, kittypets, and lost or exiled cats nearby.
struct OutsidersSection: View {
    @Environment(AppModel.self) private var model
    @State private var isExpanded: Bool

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12)]

    init(isExpanded: Bool = false) {
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        let cats = model.nearbyOutsiders
        if !cats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: toggle) {
                    HStack {
                        Label("Cats Outside the Clan", systemImage: "tree.fill")
                            .font(.title2.bold())
                        Text(cats.count, format: .number)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isHeader)

                if isExpanded {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(cats) { cat in
                            OutsiderCell(cat: cat, name: model.displayName(cat)) {
                                model.selectedCat = cat
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func toggle() {
        withAnimation(.snappy) { isExpanded.toggle() }
    }
}
