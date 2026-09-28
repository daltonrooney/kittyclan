import SwiftUI

struct HungryCatsSection: View {
    @Environment(AppModel.self) private var model
    @State private var feedings = 0

    var body: some View {
        let hungry = model.hungryCats
        Section {
            if hungry.isEmpty {
                Label("Everyone is well fed!", systemImage: "face.smiling")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button(action: feed) {
                    Label("Feed hungry cats", systemImage: "fork.knife")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .disabled(model.isAdvancing || (model.clan?.freshKill.total ?? 0) <= 0)
                .sensoryFeedback(.success, trigger: feedings)
                ForEach(hungry) { entry in
                    HStack(spacing: 12) {
                        CatSprite(cat: entry.cat)
                            .frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                        Text(model.displayName(entry.cat))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NutritionBar(nutrition: entry.nutrition)
                            .frame(width: 140)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Hungry cats")
        } footer: {
            if !hungry.isEmpty {
                Text("Feeding takes prey from the fresh-kill pile, hungriest kits and elders first.")
            }
        }
    }

    private func feed() {
        let ids = model.hungryCats.map(\.id)
        Task {
            await model.feed(ids)
            feedings += 1
        }
    }
}
