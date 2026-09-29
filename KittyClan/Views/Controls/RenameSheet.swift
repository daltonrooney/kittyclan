import SwiftUI

struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var prefix = ""
    @State private var suffix = ""
    @State private var hidesSpecialSuffix = false

    var body: some View {
        let ending = model.specialSuffix(for: cat)
        let suffixLocked = ending != nil && !hidesSpecialSuffix
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        CatSprite(cat: cat)
                            .frame(width: 72)
                            .grayscale(cat.isDead && cat.afterlife == nil ? 0.7 : 0)
                        VStack(alignment: .leading) {
                            Text(model.previewName(of: cat, prefix: prefix, suffix: suffix, hideSpecialSuffix: hidesSpecialSuffix))
                                .font(.largeTitle.bold())
                            Text("Currently \(model.displayName(cat))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    field("Prefix", text: $prefix, placeholder: cat.name.prefix) {
                        prefix = model.randomName(for: cat)?.prefix ?? prefix
                    }
                    field("Suffix", text: $suffix, placeholder: suffixLocked ? (ending ?? "") : "No suffix") {
                        suffix = model.randomName(for: cat)?.suffix ?? suffix
                    }
                    .disabled(suffixLocked)
                    if let ending {
                        Toggle("Drop the special ending (-\(ending))", isOn: $hidesSpecialSuffix)
                    }
                } header: {
                    Text("Name")
                } footer: {
                    Text("Names use letters, numbers and spaces. An empty prefix keeps the old one.")
                }
            }
            .navigationTitle("Rename \(model.displayName(cat))")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.isAdvancing)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: hidesSpecialSuffix) {
            suffix = hidesSpecialSuffix ? cat.name.suffix : ""
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, roll: @escaping () -> Void) -> some View {
        HStack {
            TextField(title, text: text, prompt: Text(placeholder))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Random \(title.lowercased())", systemImage: "dice", action: roll)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private func load() {
        hidesSpecialSuffix = cat.name.specialSuffixHidden
        prefix = cat.name.prefix
        suffix = model.specialSuffix(for: cat) == nil || hidesSpecialSuffix ? cat.name.suffix : ""
    }

    private func save() {
        Task {
            await model.rename(cat.id, prefix: prefix, suffix: suffix, hideSpecialSuffix: hidesSpecialSuffix)
            dismiss()
        }
    }
}
