import SwiftUI

/// Every relative Clangen's family tree knows of, grouped by relation.
struct FamilyTreeView: View {
    @Environment(AppModel.self) private var model
    let catID: Cat.ID

    var body: some View {
        if let cat = model.cat(catID) {
            let family = model.family(of: cat)
            List {
                if family.isEmpty {
                    ContentUnavailableView("No known family", systemImage: "tree", description: Text("\(model.displayName(cat)) has no known relatives."))
                        .listRowBackground(Color.clear)
                }
                ForEach(FamilyGroup.allCases) { group in
                    let relatives = group.members(of: family)
                    if !relatives.isEmpty {
                        Section("\(group.rawValue) (\(relatives.count))") {
                            ForEach(relatives, id: \.id) { kin in
                                if let relative = model.cat(kin.id) {
                                    NavigationLink(value: relative.id) {
                                        CatLinkRow(cat: relative, name: model.displayName(relative), relation: kin.kind.label(for: relative))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(model.displayName(cat))'s Family")
            .toolbarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This cat has wandered off", systemImage: "questionmark.circle")
        }
    }
}
