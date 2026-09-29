import SwiftUI

struct MateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var tab = MateTab.potential
    @State private var selection: Cat.ID?
    @State private var singleOnly = false
    @State private var kitsOnly = false
    @State private var confirming: Cat?

    var body: some View {
        let cat = current
        let name = model.displayName(cat)
        let shown = tab == .potential
            ? model.mateCandidates(for: cat, singleOnly: singleOnly, kitsOnly: kitsOnly)
            : model.cats(cat.mates)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MatePairCard(cat: cat, partner: model.cat(selection), decide: confirm)
                        .confirmationDialog(confirmTitle, isPresented: isConfirming, titleVisibility: .visible, presenting: confirming) { other in
                            if cat.mates.contains(other.id) {
                                Button("Break It Up", role: .destructive) { breakUp(with: other) }
                            } else {
                                Button("It's Official!") { makeOfficial(with: other) }
                            }
                        } message: { other in
                            Text(cat.mates.contains(other.id)
                                 ? "They'll think less of each other afterwards."
                                 : "\(name) and \(model.displayName(other)) will become mates.")
                        }
                    Picker("Show", selection: $tab) {
                        ForEach(MateTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if tab == .potential {
                        HStack {
                            Toggle("No mates", isOn: $singleOnly)
                            Toggle("Can have kits together", isOn: $kitsOnly)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                    }
                    CatPickerGrid(cats: shown, emptyText: emptyText(name)) { other in
                        CatPickerCell(
                            cat: other,
                            caption: "\(other.rank.label), \(other.moonsText)",
                            tag: tag(for: other, of: cat),
                            isSelected: other.id == selection
                        ) {
                            selection = other.id == selection ? nil : other.id
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mates for \(name)")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
        .onChange(of: tab) {
            selection = tab == .mates ? current.mates.first : nil
        }
        #if DEBUG
        .task { debugSelect() }
        #endif
    }

    private var current: Cat {
        model.cat(cat.id) ?? cat
    }

    private func tag(for other: Cat, of cat: Cat) -> String? {
        if cat.previousMates.contains(other.id) { return "Former mate" }
        return other.mates.isEmpty || tab == .mates ? nil : "Has a mate"
    }

    private func emptyText(_ name: String) -> String {
        tab == .mates ? "\(name) has no mates." : "No cats can become \(name)'s mate."
    }

    private var confirmTitle: String {
        guard let confirming else { return "" }
        let other = model.displayName(confirming)
        return current.mates.contains(confirming.id) ? "Break up with \(other)?" : "Make it official with \(other)?"
    }

    private var isConfirming: Binding<Bool> {
        Binding { confirming != nil } set: { if !$0 { confirming = nil } }
    }

    private func confirm() {
        confirming = model.cat(selection)
    }

    private func makeOfficial(with other: Cat) {
        Task { await model.setMates(cat.id, other.id) }
    }

    private func breakUp(with other: Cat) {
        Task { await model.breakUp(cat.id, other.id) }
    }

    #if DEBUG
    /// With `-sheet mate`, selects the first candidate, or the first mate with `-mateTab mates`.
    private func debugSelect() {
        guard UserDefaults.standard.string(forKey: "sheet") == CatAction.mate.rawValue else { return }
        if UserDefaults.standard.string(forKey: "mateTab") == "mates" {
            tab = .mates
            selection = current.mates.first
        } else if selection == nil {
            selection = model.mateCandidates(for: current, singleOnly: false, kitsOnly: false).first?.id
        }
    }
    #endif
}
