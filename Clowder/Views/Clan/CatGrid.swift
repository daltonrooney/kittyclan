import SwiftUI

struct CatGrid: View {
    @Environment(AppModel.self) private var model
    let cats: [Cat]

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(cats) { cat in
                ClanCatCell(cat: cat, name: model.displayName(cat)) {
                    model.selectedCat = cat
                }
            }
        }
    }
}
