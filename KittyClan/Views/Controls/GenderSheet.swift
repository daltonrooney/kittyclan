import SwiftUI

/// Clangen's gender controls: the profile's identity cycle, ChangeGenderScreen's custom
/// identity, and a pronoun set.
struct GenderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var identity = Identity.cisgender
    @State private var custom = ""
    @State private var pronouns = Pronouns.they

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        CatSprite(cat: cat)
                            .frame(width: 72)
                            .grayscale(cat.isDead && cat.afterlife == nil ? 0.7 : 0)
                        VStack(alignment: .leading) {
                            Text(model.displayName(cat))
                                .font(.largeTitle.bold())
                            Text("Sex: \(cat.sex.rawValue.capitalized)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Picker("Identity", selection: identityChoice) {
                        ForEach(Identity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if identity == .custom {
                        TextField("Gender identity", text: $custom, prompt: Text("Describe their gender"))
                            .autocorrectionDisabled()
                    } else {
                        LabeledContent("Shown as", value: label(for: chosen))
                    }
                } header: {
                    Text("Gender identity")
                } footer: {
                    Text("Sex decides who can carry kits and how pelts are inherited; gender and pronouns are how the cat is described.")
                }
                Section {
                    Picker("Pronouns", selection: $pronouns) {
                        ForEach(Pronouns.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(model.pronounPreview(of: cat, pronouns: pronouns))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Pronouns")
                } footer: {
                    Text("Choosing an identity resets pronouns to match it. A custom identity keeps the current pronouns.")
                }
            }
            .navigationTitle("Gender for \(model.displayName(cat))")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(chosen.rawValue.trimmingCharacters(in: .whitespaces).isEmpty || model.isAdvancing)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: custom) {
            let cleaned = String(custom.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
            if cleaned != custom { custom = cleaned }
        }
    }

    /// Picking a built-in identity resets pronouns to match, like Clangen's profile button.
    private var identityChoice: Binding<Identity> {
        Binding { identity } set: { choice in
            identity = choice
            if choice != .custom { pronouns = chosen.defaultPronouns }
        }
    }

    private var chosen: GenderAlign {
        switch identity {
        case .cisgender: .cis(cat.sex)
        case .trans: .trans(cat.sex)
        case .nonbinary: .nonbinary
        case .custom: GenderAlign(rawValue: custom)
        }
    }

    private func label(for gender: GenderAlign) -> String {
        gender == .cis(cat.sex) ? cat.sex.rawValue.capitalized : gender.label
    }

    private func load() {
        pronouns = cat.pronouns
        switch cat.genderAlign {
        case .cis(cat.sex): identity = .cisgender
        case .trans(cat.sex): identity = .trans
        case .nonbinary: identity = .nonbinary
        default:
            identity = .custom
            custom = cat.genderAlign.rawValue
        }
    }

    private func save() {
        Task {
            await model.setGender(cat.id, genderAlign: chosen, pronouns: pronouns)
            dismiss()
        }
    }

    private enum Identity: String, CaseIterable, Identifiable {
        case cisgender = "Cisgender"
        case trans = "Trans"
        case nonbinary = "Nonbinary"
        case custom = "Custom"

        var id: Self { self }
    }
}

extension Pronouns {
    var label: String {
        switch self {
        case .they: "they/them"
        case .he: "he/him"
        case .she: "she/her"
        }
    }
}
