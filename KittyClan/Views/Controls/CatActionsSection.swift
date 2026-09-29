import SwiftUI

/// The player's controls for a cat: role, mentor, mediation, mate, adoptive parents, gender and
/// name, then Clangen's dangerous ones: moving a ghost between afterlives, killing, and
/// removing accessories.
struct CatActionsSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let open: (CatAction) -> Void

    @State private var isConfirmingGuideMove = false
    @State private var isConfirmingAccessories = false

    var body: some View {
        let isClanCat = model.isLivingClanCat(cat)
        let canEdit = model.canRename(cat)
        let hasAccessories = !cat.appearance.accessories.isEmpty
        if canEdit || cat.isDead || hasAccessories {
            Section("Actions") {
                if canEdit {
                    editRows(isClanCat: isClanCat)
                }
                if cat.isDead, let destination = cat.afterlife?.next(isGuide: model.isGuide(cat)) {
                    Button(action: moveAfterlife) {
                        Label(destination.moveLabel, systemImage: destination.symbol)
                            .foregroundStyle(destination.tint)
                    }
                }
                if isClanCat {
                    Button(role: .destructive) { open(.kill) } label: {
                        Label("Kill Cat", systemImage: "heart.slash")
                    }
                }
                if hasAccessories {
                    Button(role: .destructive) { isConfirmingAccessories = true } label: {
                        Label("Remove Accessories", systemImage: "xmark.circle")
                    }
                }
            }
            .disabled(model.isAdvancing)
            .alert(guideMoveTitle, isPresented: $isConfirmingGuideMove) {
                Button("Cancel", role: .cancel) {}
                Button(guideMoveButton) { Task { await model.moveToNextAfterlife(cat.id) } }
            } message: {
                Text(guideMoveMessage)
            }
            .confirmationDialog("Remove \(model.displayName(cat))'s accessories?", isPresented: $isConfirmingAccessories, titleVisibility: .visible) {
                Button("Remove Accessories", role: .destructive) { Task { await model.removeAccessories(from: cat.id) } }
            } message: {
                Text("Everything \(model.displayName(cat)) wears will be thrown away.")
            }
            #if DEBUG
            .task {
                if model.isGuide(cat), UserDefaults.standard.bool(forKey: "confirmGuideMove") { isConfirmingGuideMove = true }
                if hasAccessories, UserDefaults.standard.bool(forKey: "confirmAccessories") { isConfirmingAccessories = true }
            }
            #endif
        }
    }

    @ViewBuilder
    private func editRows(isClanCat: Bool) -> some View {
        if isClanCat, !model.roleTargets(for: cat).isEmpty {
            row("Change Role", systemImage: "person.badge.shield.checkmark", value: cat.rank.label, action: .role)
        }
        if isClanCat, cat.rank.isApprentice {
            row("Choose Mentor", systemImage: "graduationcap", value: model.cat(cat.mentor).map(model.displayName) ?? "None", action: .mentor)
        }
        if isClanCat, cat.rank.isMediator {
            row("Mediate", systemImage: "person.2.wave.2", value: nil, action: .mediate)
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

    /// The guide asks first, since the whole Clan's dead follow it.
    private func moveAfterlife() {
        if model.isGuide(cat) {
            isConfirmingGuideMove = true
        } else {
            Task { await model.moveToNextAfterlife(cat.id) }
        }
    }

    private var guideDestination: Afterlife {
        (cat.afterlife ?? .starClan).next(isGuide: true)
    }

    private var guideMoveTitle: String {
        "\(guideDestination.moveLabel)?"
    }

    private var guideMoveButton: String {
        guideDestination == .darkForest ? "Exile" : "Guide"
    }

    private var guideMoveMessage: String {
        let name = model.displayName(cat)
        let place = guideDestination == .darkForest ? "the Dark Forest" : "StarClan"
        return "Changing where \(name) resides will change where your Clan goes after death. "
            + "From now on, the Clan's dead will join \(place), and new leaders will receive their nine lives from \(place)."
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

extension Afterlife {
    /// Clangen's profile button for sending a dead cat here.
    var moveLabel: String {
        switch self {
        case .starClan: "Guide into StarClan"
        case .darkForest: "Exile to the Dark Forest"
        case .unknownResidence: "Send to a Foreign Land"
        }
    }
}
