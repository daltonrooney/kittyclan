import SwiftUI

/// Clangen's StarClan, Dark Forest and Unknown Residence screens: the Clan's dead and its guide.
struct AfterlifeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sort = Self.initialSort
    @State private var search = ""
    @State private var selectedCat: Cat?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            AfterlifeGrid(afterlife: model.afterlifeTab, sort: sort, search: search, select: select)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top) {
                    Picker("Afterlife", selection: $model.afterlifeTab) {
                        ForEach(Afterlife.allCases, id: \.self) { afterlife in
                            Text(afterlife.label).tag(afterlife)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
                .background { AfterlifeBackground(afterlife: model.afterlifeTab) }
                .navigationTitle(model.afterlifeTab.label)
                .toolbarTitleDisplayMode(.inline)
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        AfterlifeOptionsMenu(sort: $sort)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                }
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(item: $selectedCat) { cat in
            CatDetailSheet(cat: cat)
        }
        .modifier(PageSheetSizing())
    }

    private func select(_ cat: Cat) {
        selectedCat = cat
    }

    private static var initialSort: AfterlifeSort {
        #if DEBUG
        UserDefaults.standard.string(forKey: "afterlifeSort").flatMap(AfterlifeSort.init(rawValue:)) ?? .rank
        #else
        .rank
        #endif
    }
}
