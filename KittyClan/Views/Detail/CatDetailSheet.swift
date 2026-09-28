import SwiftUI

struct CatDetailSheet: View {
    let cat: Cat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CatDetailView(catID: cat.id)
                .navigationDestination(for: Cat.ID.self) { id in
                    CatDetailView(catID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                }
        }
        .modifier(PageSheetSizing())
    }
}
