import SwiftUI

/// Clangen's gender controls: the profile's identity cycle, and ChangeGenderScreen's custom
/// identity and pronoun sets.
struct GenderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var identity = Identity.cisgender
    @State private var custom = ""
    @State private var pronouns: [PronounSet] = [.they]
    @State private var isCreatingPronouns = false

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
                    ForEach(pronouns, id: \.self) { set in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.label)
                                Text(model.pronounSample(of: cat, set: set))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove \(set.label)", systemImage: "minus.circle.fill", role: .destructive) {
                                pronouns.removeAll { $0 == set }
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(pronouns.count > 1 ? .red : .secondary)
                            .disabled(pronouns.count == 1)
                            .buttonStyle(.borderless)
                        }
                    }
                    Menu {
                        ForEach(available, id: \.self) { set in
                            Button(set.label) { pronouns.append(set) }
                        }
                    } label: {
                        Label("Add pronouns", systemImage: "plus.circle")
                    }
                    .disabled(available.isEmpty)
                    Button("Create custom pronouns", systemImage: "square.and.pencil") {
                        isCreatingPronouns = true
                    }
                } header: {
                    Text("Pronouns")
                } footer: {
                    Text("With more than one set, each piece of text about \(model.displayName(cat)) uses one of them at random. Choosing an identity resets pronouns to match it; a custom identity keeps the current pronouns.")
                }
                if let custom = model.clan?.customPronouns, !custom.isEmpty {
                    Section {
                        ForEach(custom, id: \.self) { set in
                            Text(set.label)
                        }
                        .onDelete { offsets in
                            for set in offsets.map({ custom[$0] }) {
                                Task { await model.removeCustomPronouns(set) }
                            }
                        }
                    } header: {
                        Text("Clan pronoun sets")
                    } footer: {
                        Text("Custom sets can be given to any cat. Deleting one here doesn't take it away from cats who use it.")
                    }
                }
            }
            .navigationDestination(isPresented: $isCreatingPronouns) {
                PronounCreator(cat: cat, template: pronouns.first ?? .they) { set in
                    if !pronouns.contains(set) { pronouns.append(set) }
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
            if choice != .custom { pronouns = model.clan?.newPronouns(for: chosen) ?? [chosen.defaultPronouns] }
        }
    }

    /// Built-in and Clan sets the cat doesn't use yet.
    private var available: [PronounSet] {
        (PronounSet.builtIn + (model.clan?.customPronouns ?? [])).filter { !pronouns.contains($0) }
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
        #if DEBUG
        // `-pronounSets YES` adds another set; `-pronounCreator YES` opens the custom set form.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "pronounSets"), let extra = available.first { pronouns.append(extra) }
        if defaults.bool(forKey: "pronounCreator") { isCreatingPronouns = true }
        #endif
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

/// Clangen's PronounCreationWindow: the five pronoun words, verb and adjective forms, and a demo.
struct PronounCreator: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat
    let template: PronounSet
    let onCreate: (PronounSet) -> Void

    @State private var words = Array(repeating: "", count: 5)
    @State private var conju = 1
    @State private var gender = 0

    private static let fields = [
        ("Subject", "they walk"), ("Object", "saw them"), ("Possessive", "their paw"),
        ("Independent possessive", "it's theirs"), ("Reflexive", "by themself"),
    ]

    var body: some View {
        Form {
            Section("Preview") {
                Text(model.pronounPreview(of: cat, set: draft))
            }
            Section {
                ForEach(Self.fields.indices, id: \.self) { i in
                    LabeledContent {
                        TextField(Self.fields[i].0, text: $words[i], prompt: Text(placeholder(i)))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(Self.fields[i].0)
                            Text(Self.fields[i].1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Words")
            } footer: {
                Text("Letters and numbers only. An empty field uses the word shown.")
            }
            Section("Grammar") {
                Picker("Verbs", selection: $conju) {
                    Text("Plural (they are)").tag(1)
                    Text("Singular (she is)").tag(2)
                }
                Picker("Describing words", selection: $gender) {
                    Text("Neutral (cat)").tag(0)
                    Text("Masculine (tom)").tag(1)
                    Text("Feminine (she-cat)").tag(2)
                }
            }
        }
        .navigationTitle("New Pronouns")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: save)
                    .disabled(model.isAdvancing)
            }
        }
        .onAppear {
            conju = template.conju
            gender = template.gender
        }
        .onChange(of: words) {
            let cleaned = words.map { String($0.unicodeScalars.filter(CharacterSet.alphanumerics.contains)) }
            if cleaned != words { words = cleaned }
        }
    }

    private func placeholder(_ i: Int) -> String {
        [template.subject, template.object, template.poss, template.inposs, template.reflexive][i]
    }

    private var draft: PronounSet {
        let w = words.indices.map { words[$0].isEmpty ? placeholder($0) : words[$0] }
        return PronounSet(subject: w[0], object: w[1], poss: w[2], inposs: w[3], reflexive: w[4], conju: conju, gender: gender)
    }

    private func save() {
        let set = draft
        Task {
            await model.addCustomPronouns(set)
            onCreate(set)
            dismiss()
        }
    }
}
