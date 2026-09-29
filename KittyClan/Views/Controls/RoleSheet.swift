import SwiftUI

struct RoleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat
    let viewCeremony: () -> Void

    @State private var confirming: Rank?
    @State private var isShowingCrowned = false

    var body: some View {
        let name = model.displayName(cat)
        let targets = model.roleTargets(for: cat)
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        CatSprite(cat: cat)
                            .frame(width: 72)
                        VStack(alignment: .leading) {
                            Text(name)
                                .font(.title2.bold())
                            Text(cat.rank.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if targets.isEmpty {
                        Text("\(name) is too young for a new role.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(targets, id: \.self) { rank in
                        Button(rank.roleAction, systemImage: rank.roleSymbol) { choose(rank) }
                            .disabled(model.isAdvancing)
                    }
                } header: {
                    Text("New role")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Change Role")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
            .confirmationDialog(confirmTitle(name), isPresented: isConfirming, titleVisibility: .visible, presenting: confirming) { rank in
                Button(rank.roleAction) { change(to: rank) }
            } message: { rank in
                Text(rank == .leader
                     ? "\(name) will receive nine lives from StarClan."
                     : "\(name) will leave their duties and live in the elders' den.")
            }
            .alert("\(model.cat(cat.id).map(model.displayName) ?? name) leads the Clan", isPresented: $isShowingCrowned) {
                Button("View Ceremony") {
                    viewCeremony()
                    dismiss()
                }
                Button("Done", role: .cancel) { dismiss() }
            } message: {
                Text("StarClan has granted nine lives.")
            }
        }
    }

    private var footer: String {
        guard let clan = model.clan else { return "" }
        var notes: [String] = []
        if !clan.leaderVacant { notes.append("The Clan already has a leader.") }
        if !clan.deputyVacant { notes.append("The Clan already has a deputy.") }
        if cat.rank == .medicineCat { notes.append("A medicine cat must become a warrior before leading.") }
        if cat.rank.isApprentice { notes.append("Apprentices graduate on their own when ready.") }
        return notes.joined(separator: " ")
    }

    private var isConfirming: Binding<Bool> {
        Binding { confirming != nil } set: { if !$0 { confirming = nil } }
    }

    private func confirmTitle(_ name: String) -> String {
        confirming == .leader ? "Make \(name) leader?" : "Retire \(name)?"
    }

    private func choose(_ rank: Rank) {
        if rank.needsRoleConfirmation {
            confirming = rank
        } else {
            change(to: rank)
        }
    }

    private func change(to rank: Rank) {
        Task {
            guard await model.changeRank(rank, for: cat.id) else { return }
            if rank == .leader {
                isShowingCrowned = true
            } else {
                dismiss()
            }
        }
    }
}
