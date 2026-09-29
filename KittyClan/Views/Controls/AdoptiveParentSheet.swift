import SwiftUI

/// Clangen's ChooseAdoptiveParentScreen: birth parents, adoptive parents and cats who could adopt.
struct AdoptiveParentSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var tab = AdoptiveParentTab.potential
    @State private var selection: Cat.ID?
    @State private var matesOfParentsOnly = false
    @State private var unrelatedOnly = false

    var body: some View {
        let cat = current
        let name = model.displayName(cat)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Show", selection: $tab) {
                        ForEach(AdoptiveParentTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if tab == .potential {
                        HStack {
                            Toggle("Mates of current parents", isOn: $matesOfParentsOnly)
                            Toggle("Not closely related", isOn: $unrelatedOnly)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                    }
                    CatPickerGrid(cats: shown(for: cat), emptyText: emptyText(name)) { parent in
                        CatPickerCell(
                            cat: parent,
                            caption: "\(parent.genderLabel), \(parent.moonsText)",
                            tag: tag(for: parent, of: cat),
                            isSelected: parent.id == selection
                        ) {
                            guard tab != .birth else { return }
                            selection = parent.id == selection ? nil : parent.id
                        }
                    }
                    Text("If a cat is added as an adoptive parent, they will be displayed on the family page and considered a full relative. Adoptive and blood parents will be treated the same; this also applies to siblings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if tab != .birth {
                    AdoptiveParentBar(cat: cat, selection: model.cat(selection), adopt: adopt, unadopt: unadopt)
                }
            }
            .navigationTitle("Adoptive Parents for \(name)")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
        .onChange(of: tab) { selection = nil }
        #if DEBUG
        .task { debugSelect() }
        #endif
    }

    private var current: Cat {
        model.cat(cat.id) ?? cat
    }

    private func shown(for cat: Cat) -> [Cat] {
        switch tab {
        case .potential: model.adoptiveParentCandidates(for: cat, matesOfParentsOnly: matesOfParentsOnly, unrelatedOnly: unrelatedOnly)
        case .adoptive: model.cats(cat.adoptiveParents)
        case .birth: model.cats(cat.parents)
        }
    }

    private func tag(for parent: Cat, of cat: Cat) -> String? {
        if parent.isDead { return "Dead" }
        if tab == .potential, cat.allParents.contains(where: { parent.mates.contains($0) }) { return "Parent's mate" }
        return nil
    }

    private func emptyText(_ name: String) -> String {
        switch tab {
        case .potential: "No cats can adopt \(name) right now."
        case .adoptive: "\(name) has no adoptive parents."
        case .birth: "\(name)'s birth parents are unknown."
        }
    }

    private func adopt() {
        guard let selection else { return }
        Task {
            await model.adopt(cat.id, by: selection)
            self.selection = nil
        }
    }

    private func unadopt() {
        guard let selection else { return }
        Task {
            await model.unadopt(cat.id, from: selection)
            self.selection = nil
        }
    }

    #if DEBUG
    /// With `-sheet adopt`, selects the first candidate, or the first adoptive parent with `-adoptTab adoptive`.
    private func debugSelect() {
        guard UserDefaults.standard.string(forKey: "sheet") == CatAction.adoptiveParents.rawValue, selection == nil else { return }
        if UserDefaults.standard.string(forKey: "adoptTab") == "adoptive" {
            tab = .adoptive
            selection = current.adoptiveParents.first
        } else {
            selection = model.adoptiveParentCandidates(for: current, matesOfParentsOnly: false, unrelatedOnly: false).first?.id
        }
    }
    #endif
}

enum AdoptiveParentTab: String, CaseIterable, Identifiable {
    case potential = "Potential parents"
    case adoptive = "Adoptive parents"
    case birth = "Birth parents"

    var id: Self { self }
}

private struct AdoptiveParentBar: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let selection: Cat?
    let adopt: () -> Void
    let unadopt: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("Adoptive parents must be at least 14 moons older.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selection, cat.adoptiveParents.contains(selection.id) {
                Button("Unset Adoptive Parent", role: .destructive, action: unadopt)
                    .buttonStyle(.bordered)
            } else {
                Button("Set Adoptive Parent", action: adopt)
                    .buttonStyle(.borderedProminent)
                    .tint(.brown)
                    .disabled(selection == nil)
            }
        }
        .disabled(model.isAdvancing)
        .padding()
        .background(.bar)
    }

    private var title: String {
        guard let selection else { return "Choose a cat" }
        return model.displayName(selection)
    }
}
