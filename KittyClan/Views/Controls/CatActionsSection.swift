import SwiftUI

/// The player's controls for a cat: role, mentor, mate, adoptive parents, gender and name.
struct CatActionsSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let open: (CatAction) -> Void

    var body: some View {
        let isClanCat = model.isLivingClanCat(cat)
        if model.canRename(cat) {
            Section("Actions") {
                if isClanCat, !model.roleTargets(for: cat).isEmpty {
                    row("Change Role", systemImage: "person.badge.shield.checkmark", value: cat.rank.label, action: .role)
                }
                if isClanCat, cat.rank.isApprentice {
                    row("Choose Mentor", systemImage: "graduationcap", value: model.cat(cat.mentor).map(model.displayName) ?? "None", action: .mentor)
                }
                if model.canChooseMate(cat) {
                    row("Choose Mate", systemImage: "heart", value: matesText, action: .mate)
                }
                if isClanCat {
                    row("Adoptive Parents", systemImage: "figure.and.child.holdinghands", value: adoptiveText, action: .adoptiveParents)
                }
                row("Gender", systemImage: "person.crop.circle.badge.questionmark", value: cat.genderLabel, action: .gender)
                row("Rename", systemImage: "character.cursor.ibeam", value: nil, action: .rename)
            }
            .disabled(model.isAdvancing)
        }
    }

    private var matesText: String {
        switch cat.mates.count {
        case 0: "None"
        case 1: model.cat(cat.mates[0]).map(model.displayName) ?? "1 mate"
        case let n: "\(n) mates"
        }
    }

    private var adoptiveText: String {
        switch cat.adoptiveParents.count {
        case 0: "None"
        case 1: model.cat(cat.adoptiveParents[0]).map(model.displayName) ?? "1 parent"
        case let n: "\(n) parents"
        }
    }

    private func row(_ title: String, systemImage: String, value: String?, action: CatAction) -> some View {
        Button { open(action) } label: {
            LabeledContent {
                if let value { Text(value) }
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
        .tint(.primary)
    }
}
