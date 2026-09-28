import SwiftUI

struct CatFamilySection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    var body: some View {
        let relations = relations
        Section("Family & Mentorship") {
            if relations.isEmpty {
                Text("No family or mentors yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(relations) { relation in
                NavigationLink(value: relation.cat.id) {
                    CatLinkRow(cat: relation.cat, name: model.displayName(relation.cat), relation: relation.label)
                }
            }
        }
    }

    private var relations: [CatRelation] {
        let groups: [(String, [Cat])] = [
            ("Mentor", model.cats([cat.mentor].compactMap(\.self))),
            ("Apprentice", model.cats(cat.apprentices)),
            ("Former apprentice", model.cats(cat.formerApprentices)),
            ("Parent", model.cats(cat.parents)),
            ("Mate", model.cats(cat.mates)),
            ("Kit", model.kits(of: cat)),
        ]
        return groups.flatMap { label, cats in cats.map { CatRelation(label: label, cat: $0) } }
    }
}
