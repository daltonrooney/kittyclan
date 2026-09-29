import SwiftUI

struct CatPickerGrid<Cell: View>: View {
    let cats: [Cat]
    let emptyText: String
    @ViewBuilder let cell: (Cat) -> Cell

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12, alignment: .top)]

    var body: some View {
        if cats.isEmpty {
            Text(emptyText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cats) { cat in
                    cell(cat)
                }
            }
        }
    }
}
