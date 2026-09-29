import SwiftUI

struct MentorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var selection: Cat.ID?
    @State private var noCurrentApprentices = false
    @State private var noFormerApprentices = false

    var body: some View {
        let cat = current
        let name = model.displayName(cat)
        let mentor = model.cat(cat.mentor)
        let candidates = model.mentorCandidates(
            for: cat, noCurrentApprentices: noCurrentApprentices, noFormerApprentices: noFormerApprentices
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Toggle("No current apprentices", isOn: $noCurrentApprentices)
                        Toggle("No former apprentices", isOn: $noFormerApprentices)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    CatPickerGrid(cats: candidates, emptyText: "No cats can mentor \(name) right now.") { candidate in
                        CatPickerCell(
                            cat: candidate,
                            caption: apprenticeCount(candidate),
                            tag: candidate.id == cat.mentor ? "Current mentor" : nil,
                            isSelected: candidate.id == selection
                        ) {
                            selection = candidate.id == selection ? nil : candidate.id
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                MentorChoiceBar(apprentice: name, mentor: mentor, selection: model.cat(selection), save: save, remove: remove)
            }
            .navigationTitle("Mentor for \(name)")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
        .onAppear { selection = current.mentor }
    }

    private var current: Cat {
        model.cat(cat.id) ?? cat
    }

    private func apprenticeCount(_ mentor: Cat) -> String {
        let current = mentor.apprentices.count
        let former = mentor.formerApprentices.count
        if current > 0 { return current == 1 ? "1 apprentice" : "\(current) apprentices" }
        if former > 0 { return former == 1 ? "1 former apprentice" : "\(former) former apprentices" }
        return mentor.rank.label
    }

    private func save() {
        guard let selection, selection != current.mentor else { return dismiss() }
        Task {
            await model.setMentor(selection, for: cat.id)
            dismiss()
        }
    }

    private func remove() {
        Task {
            await model.setMentor(nil, for: cat.id)
            selection = nil
        }
    }
}

private struct MentorChoiceBar: View {
    @Environment(AppModel.self) private var model
    let apprentice: String
    let mentor: Cat?
    let selection: Cat?
    let save: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                if let mentor {
                    Text("Current mentor: \(model.displayName(mentor))")
                        .font(.headline)
                    Text("If removed, a new mentor is chosen next moon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No mentor")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("A new mentor is chosen next moon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if mentor != nil {
                Button("Remove Mentor", role: .destructive, action: remove)
                    .buttonStyle(.bordered)
            }
            Button(saveTitle, action: save)
                .buttonStyle(.borderedProminent)
                .tint(.brown)
                .disabled(selection == nil || selection?.id == mentor?.id || model.isAdvancing)
        }
        .padding()
        .background(.bar)
    }

    private var saveTitle: String {
        guard let selection, selection.id != mentor?.id else { return "Choose Mentor" }
        return "Make \(model.displayName(selection)) Mentor"
    }
}
