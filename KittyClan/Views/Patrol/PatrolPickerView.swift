import SwiftUI

struct PatrolPickerView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var patrol: PatrolModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 96 : 110, maximum: 150), spacing: sizeClass == .compact ? 10 : 12)]
    }

    var body: some View {
        let eligible = patrol.eligible
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PatrolPreyHint(patrol: patrol)
                PatrolTypePicker(patrol: patrol)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Who's going?")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("^[\(eligible.count) cat](inflect: true) can patrol this moon")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    PatrolRandomButtons(patrol: patrol)
                }
                if eligible.isEmpty {
                    ContentUnavailableView("Everyone has patrolled", systemImage: "moon.zzz", description: Text("Cats can patrol again next moon."))
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(eligible) { cat in
                            PatrolCatCell(cat: cat, isSelected: patrol.isSelected(cat), isDisabled: patrol.isFull && !patrol.isSelected(cat)) {
                                patrol.toggle(cat)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            PatrolSelectionBar(patrol: patrol)
        }
        .alert("No patrol found", isPresented: $patrol.isShowingNoPatrol) {
        } message: {
            Text("These cats couldn't find anything to patrol for. Try different cats or another kind of patrol.")
        }
    }
}
