import SwiftUI

struct CatFamilySection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let showFamilyTree: () -> Void

    var body: some View {
        let family = model.family(of: cat)
        let close = closeFamily(family)
        let relations = mentorship + close
        let others = family.count - close.count
        Section("Family & Mentorship") {
            if relations.isEmpty && family.isEmpty {
                Text("No family or mentors yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(relations) { relation in
                NavigationLink(value: relation.cat.id) {
                    CatLinkRow(cat: relation.cat, name: model.displayName(relation.cat), relation: relation.label)
                }
            }
            if others > 0 {
                Button(action: showFamilyTree) {
                    LabeledContent {
                        Text(others == 1 ? "1 more relative" : "\(others) more relatives")
                    } label: {
                        Label("Full Family Tree", systemImage: "tree")
                    }
                }
            }
        }
    }

    private var mentorship: [CatRelation] {
        let groups: [(String, [Cat])] = [
            ("Mentor", model.cats([cat.mentor].compactMap(\.self))),
            ("Apprentice", model.cats(cat.apprentices)),
            ("Former apprentice", model.cats(cat.formerApprentices)),
        ]
        return groups.flatMap { label, cats in cats.map { CatRelation(label: label, cat: $0) } }
    }

    private func closeFamily(_ family: [Kin]) -> [CatRelation] {
        FamilyGroup.close.flatMap { group in
            group.members(of: family).compactMap { kin in
                model.cat(kin.id).map { CatRelation(label: kin.kind.label(for: $0), cat: $0) }
            }
        }
    }
}
