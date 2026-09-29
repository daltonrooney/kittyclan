import SwiftUI

/// The saved Clans, to continue one, start another or let one go.
struct ClanChooserView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: SaveSummary?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.savedClans) { summary in
                        Button { open(summary) } label: {
                            SavedClanRow(summary: summary, isLast: summary.id == model.lastClanID)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = summary }
                        }
                        .contextMenu {
                            Button("Delete \(summary.name)", systemImage: "trash", role: .destructive) { pendingDelete = summary }
                        }
                    }
                } footer: {
                    Text("Swipe a Clan to delete it.")
                }
                Section {
                    Button("New Clan", systemImage: "plus.circle.fill", action: model.startNewClan)
                        .font(.headline)
                }
            }
            .navigationTitle("Your Clans")
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "this Clan")?",
                isPresented: isConfirmingDelete,
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { summary in
                Button("Delete \(summary.name)", role: .destructive) { model.deleteClan(summary.id) }
            } message: { summary in
                Text("\(summary.name) and all of its history will be gone forever.")
            }
            .alert("Something went wrong", isPresented: isShowingError) {
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    private var isShowingError: Binding<Bool> {
        Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }
    }

    private func open(_ summary: SaveSummary) {
        Task { await model.openClan(summary.id) }
    }
}

private struct SavedClanRow: View {
    let summary: SaveSummary
    let isLast: Bool

    var body: some View {
        HStack(spacing: 16) {
            LeaderSprite(appearance: summary.leader)
                .frame(width: 64, height: 64)
                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.name)
                        .font(.title3.bold())
                    if isLast {
                        Text("Last played")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.18), in: .capsule)
                    }
                }
                HStack(spacing: 14) {
                    Label("Moon \(summary.moon)", systemImage: "moon.fill")
                    Label("^[\(summary.living) cat](inflect: true)", systemImage: "pawprint.fill")
                    Label(summary.season.rawValue, systemImage: summary.season.symbol)
                    Label(summary.biome.label(camp: summary.camp), systemImage: summary.biome.symbol)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text("Played \(summary.savedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct LeaderSprite: View {
    @Environment(AppModel.self) private var model
    let appearance: CatAppearance?
    @State private var image: CGImage?

    var body: some View {
        Group {
            if appearance == nil {
                Image(systemName: "pawprint")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            } else {
                PixelSprite(image: image)
            }
        }
        .task(id: appearance) {
            guard let appearance else { return }
            image = await model.sprites?.image(for: appearance)
        }
    }
}
